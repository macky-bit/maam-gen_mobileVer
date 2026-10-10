-- Email/password and OAuth sessions must resolve to the same application
-- account before subscription entitlements are checked.
create or replace function public.sync_auth_profile(target_auth_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  auth_user auth.users%rowtype;
  existing_profile_id uuid;
  existing_auth_user_id uuid;
  full_name text;
  first_name text;
  last_name text;
  generated_username text;
  avatar_url text;
begin
  select account.* into auth_user
  from auth.users as account
  where account.id = target_auth_user_id;

  if not found then
    raise exception 'Auth user % does not exist', target_auth_user_id
      using errcode = '23503';
  end if;

  -- Never attach an unverified email address to an existing paid account.
  if auth_user.email_confirmed_at is null then
    return;
  end if;

  if auth_user.email is null or btrim(auth_user.email) = '' then
    raise exception 'Auth user % has no email address', auth_user.id
      using errcode = '23502';
  end if;

  full_name := btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'full_name',
    auth_user.raw_user_meta_data ->> 'name',
    ''
  ));
  first_name := btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'first_name',
    auth_user.raw_user_meta_data ->> 'given_name',
    ''
  ));
  last_name := btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'last_name',
    auth_user.raw_user_meta_data ->> 'family_name',
    ''
  ));

  if first_name = '' then
    first_name := nullif(split_part(full_name, ' ', 1), '');
  end if;
  if last_name = '' and position(' ' in full_name) > 0 then
    last_name := btrim(substring(full_name from position(' ' in full_name) + 1));
  end if;

  first_name := coalesce(
    nullif(first_name, ''),
    nullif(split_part(auth_user.email, '@', 1), ''),
    'StreamFlix user'
  );
  last_name := coalesce(last_name, '');
  avatar_url := nullif(btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'avatar_url',
    auth_user.raw_user_meta_data ->> 'picture',
    ''
  )), '');

  generated_username := lower(regexp_replace(
    coalesce(
      nullif(auth_user.raw_user_meta_data ->> 'username', ''),
      split_part(auth_user.email, '@', 1)
    ),
    '[^a-zA-Z0-9_]+',
    '',
    'g'
  ));
  if generated_username = '' then
    generated_username := 'user';
  end if;
  generated_username := left(generated_username, 48)
    || '_'
    || replace(auth_user.id::text, '-', '');

  select app_user.user_id, app_user.auth_user_id
    into existing_profile_id, existing_auth_user_id
  from public."user" as app_user
  where app_user.auth_user_id = auth_user.id;

  if not found then
    select app_user.user_id, app_user.auth_user_id
      into existing_profile_id, existing_auth_user_id
    from public."user" as app_user
    where lower(app_user.email) = lower(auth_user.email);
  end if;

  if found then
    if existing_auth_user_id is not null
       and existing_auth_user_id <> auth_user.id then
      raise exception 'Profile email is already linked to another identity'
        using errcode = '23505';
    end if;

    update public."user"
    set auth_user_id = auth_user.id,
        avatar_image = coalesce(avatar_image, avatar_url)
    where user_id = existing_profile_id;
  else
    insert into public."user" (
      auth_user_id,
      first_name,
      last_name,
      username,
      avatar_image,
      email,
      password,
      user_role
    ) values (
      auth_user.id,
      first_name,
      last_name,
      generated_username,
      avatar_url,
      auth_user.email,
      null,
      'subscriber'
    );
  end if;
end;
$$;

revoke execute on function public.sync_auth_profile(uuid)
  from public, anon, authenticated;

create or replace function public.handle_auth_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_auth_profile(new.id);
  return new;
end;
$$;

drop trigger if exists on_google_auth_user_created on auth.users;
drop trigger if exists on_auth_user_profile_sync on auth.users;
create trigger on_auth_user_profile_sync
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.handle_auth_profile();

-- Keep the identity trigger for providers that attach after auth.users insert.
create or replace function public.handle_google_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider = 'google' then
    perform public.sync_auth_profile(new.user_id);
  end if;
  return new;
end;
$$;

-- Repair any confirmed email/password users created before this migration.
do $$
declare
  auth_user_id uuid;
begin
  for auth_user_id in
    select account.id
    from auth.users as account
    where account.email_confirmed_at is not null
  loop
    perform public.sync_auth_profile(auth_user_id);
  end loop;
end;
$$;
