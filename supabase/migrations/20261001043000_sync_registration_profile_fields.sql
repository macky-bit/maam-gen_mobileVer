-- Keep the public StreamFlix profile in sync with the fields collected by
-- the registration UI. Passwords remain exclusively in Supabase Auth.

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
  desired_username text;
  selected_username text;
  avatar_url text;
  birth_date date;
begin
  select account.* into auth_user
  from auth.users as account
  where account.id = target_auth_user_id;

  if not found then
    raise exception 'Auth user % does not exist', target_auth_user_id using errcode = '23503';
  end if;
  if auth_user.email_confirmed_at is null then return; end if;
  if auth_user.email is null or btrim(auth_user.email) = '' then
    raise exception 'Auth user % has no email address', auth_user.id using errcode = '23502';
  end if;

  full_name := btrim(coalesce(auth_user.raw_user_meta_data ->> 'full_name', auth_user.raw_user_meta_data ->> 'name', ''));
  first_name := btrim(coalesce(auth_user.raw_user_meta_data ->> 'first_name', auth_user.raw_user_meta_data ->> 'given_name', ''));
  last_name := btrim(coalesce(auth_user.raw_user_meta_data ->> 'last_name', auth_user.raw_user_meta_data ->> 'family_name', ''));
  if first_name = '' then first_name := nullif(split_part(full_name, ' ', 1), ''); end if;
  if last_name = '' and position(' ' in full_name) > 0 then
    last_name := btrim(substring(full_name from position(' ' in full_name) + 1));
  end if;
  first_name := coalesce(nullif(first_name, ''), nullif(split_part(auth_user.email, '@', 1), ''), 'StreamFlix user');
  last_name := coalesce(last_name, '');

  avatar_url := nullif(btrim(coalesce(auth_user.raw_user_meta_data ->> 'avatar_url', auth_user.raw_user_meta_data ->> 'picture', '')), '');
  desired_username := lower(regexp_replace(
    coalesce(nullif(auth_user.raw_user_meta_data ->> 'username', ''), split_part(auth_user.email, '@', 1)),
    '[^a-zA-Z0-9_]+', '', 'g'
  ));
  if desired_username = '' then desired_username := 'user'; end if;
  selected_username := left(desired_username, 60);

  begin
    birth_date := nullif(auth_user.raw_user_meta_data ->> 'date_of_birth', '')::date;
  exception when others then
    birth_date := null;
  end;

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
    if existing_auth_user_id is not null and existing_auth_user_id <> auth_user.id then
      raise exception 'Profile email is already linked to another identity' using errcode = '23505';
    end if;
    update public."user"
    set auth_user_id = auth_user.id,
        avatar_image = coalesce(avatar_image, avatar_url),
        date_of_birth = coalesce(date_of_birth, birth_date)
    where user_id = existing_profile_id;
  else
    if exists (select 1 from public."user" where lower(username) = lower(selected_username)) then
      selected_username := left(selected_username, 60) || '_' || left(replace(auth_user.id::text, '-', ''), 12);
    end if;

    insert into public."user" (
      auth_user_id, first_name, last_name, username, avatar_image,
      email, password, date_of_birth, user_role
    ) values (
      auth_user.id, first_name, last_name, selected_username, avatar_url,
      auth_user.email, null, birth_date, 'subscriber'
    );
  end if;
end;
$$;
revoke execute on function public.sync_auth_profile(uuid) from public, anon, authenticated;
grant execute on function public.sync_auth_profile(uuid) to postgres, service_role;
