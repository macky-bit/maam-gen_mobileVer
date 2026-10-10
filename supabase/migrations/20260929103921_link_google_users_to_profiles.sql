-- Maintain a one-to-one link between verified Google identities and app profiles.
create unique index if not exists app_user_auth_user_id_key
  on public."user" (auth_user_id)
  where auth_user_id is not null;

-- Email matching is used only for verified Google identities. Make that match
-- deterministic and case-insensitive so an identity cannot claim two profiles.
create unique index if not exists app_user_email_normalized_key
  on public."user" (lower(email));

create or replace function public.sync_google_profile(auth_user_id uuid)
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
  select a.* into auth_user
  from auth.users as a
  where a.id = auth_user_id;

  if not found then
    raise exception 'Auth user % does not exist', auth_user_id
      using errcode = '23503';
  end if;

  -- Email/password and other providers keep their existing onboarding path.
  if coalesce(auth_user.raw_app_meta_data ->> 'provider', '') <> 'google'
     and not exists (
       select 1
       from auth.identities as i
       where i.user_id = auth_user.id
         and i.provider = 'google'
     ) then
    return;
  end if;

  if auth_user.email is null or btrim(auth_user.email) = '' then
    raise exception 'Google identity % has no email address', auth_user.id
      using errcode = '23502';
  end if;

  full_name := btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'full_name',
    auth_user.raw_user_meta_data ->> 'name',
    ''
  ));
  first_name := btrim(coalesce(auth_user.raw_user_meta_data ->> 'given_name', ''));
  last_name := btrim(coalesce(auth_user.raw_user_meta_data ->> 'family_name', ''));

  if first_name = '' then
    first_name := nullif(split_part(full_name, ' ', 1), '');
  end if;
  if last_name = '' and position(' ' in full_name) > 0 then
    last_name := btrim(substring(full_name from position(' ' in full_name) + 1));
  end if;

  first_name := coalesce(
    nullif(first_name, ''),
    nullif(split_part(auth_user.email, '@', 1), ''),
    'Google user'
  );
  last_name := coalesce(last_name, '');
  avatar_url := nullif(btrim(coalesce(
    auth_user.raw_user_meta_data ->> 'avatar_url',
    auth_user.raw_user_meta_data ->> 'picture',
    ''
  )), '');

  generated_username := lower(regexp_replace(
    split_part(auth_user.email, '@', 1),
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

  select u.user_id, u.auth_user_id
    into existing_profile_id, existing_auth_user_id
  from public."user" as u
  where u.auth_user_id = auth_user.id;

  if not found then
    select u.user_id, u.auth_user_id
      into existing_profile_id, existing_auth_user_id
    from public."user" as u
    where lower(u.email) = lower(auth_user.email);
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

  return;
end;
$$;

revoke execute on function public.sync_google_profile(uuid)
  from public, anon, authenticated;

create or replace function public.handle_google_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_google_profile(new.id);
  return new;
end;
$$;

create or replace function public.handle_google_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider = 'google' then
    perform public.sync_google_profile(new.user_id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_google_auth_user_created on auth.users;
create trigger on_google_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_google_auth_user();

drop trigger if exists on_google_identity_created on auth.identities;
create trigger on_google_identity_created
  after insert on auth.identities
  for each row execute function public.handle_google_identity();

-- Link any pre-existing unlinked profile to its verified Google identity.
update public."user" as u
set auth_user_id = a.id,
    avatar_image = coalesce(
      u.avatar_image,
      nullif(btrim(coalesce(
        a.raw_user_meta_data ->> 'avatar_url',
        a.raw_user_meta_data ->> 'picture',
        ''
      )), '')
    )
from auth.users as a
where u.auth_user_id is null
  and lower(u.email) = lower(a.email)
  and exists (
    select 1
    from auth.identities as i
    where i.user_id = a.id
      and i.provider = 'google'
  );

-- Create missing app profiles for Google users that predate the trigger.
with google_users as (
  select
    a.id,
    a.email,
    a.raw_user_meta_data,
    btrim(coalesce(
      a.raw_user_meta_data ->> 'full_name',
      a.raw_user_meta_data ->> 'name',
      ''
    )) as full_name
  from auth.users as a
  where a.email is not null
    and exists (
      select 1
      from auth.identities as i
      where i.user_id = a.id
        and i.provider = 'google'
    )
), prepared as (
  select
    id,
    email,
    coalesce(
      nullif(btrim(raw_user_meta_data ->> 'given_name'), ''),
      nullif(split_part(full_name, ' ', 1), ''),
      nullif(split_part(email, '@', 1), ''),
      'Google user'
    ) as first_name,
    coalesce(
      nullif(btrim(raw_user_meta_data ->> 'family_name'), ''),
      case
        when position(' ' in full_name) > 0
          then btrim(substring(full_name from position(' ' in full_name) + 1))
        else ''
      end,
      ''
    ) as last_name,
    lower(coalesce(
      nullif(regexp_replace(
        split_part(email, '@', 1),
        '[^a-zA-Z0-9_]+',
        '',
        'g'
      ), ''),
      'user'
    )) || '_' || replace(id::text, '-', '') as username,
    nullif(btrim(coalesce(
      raw_user_meta_data ->> 'avatar_url',
      raw_user_meta_data ->> 'picture',
      ''
    )), '') as avatar_url
  from google_users
)
insert into public."user" (
  auth_user_id,
  first_name,
  last_name,
  username,
  avatar_image,
  email,
  password,
  user_role
)
select
  p.id,
  p.first_name,
  p.last_name,
  p.username,
  p.avatar_url,
  p.email,
  null,
  'subscriber'
from prepared as p
where not exists (
  select 1
  from public."user" as u
  where u.auth_user_id = p.id
     or lower(u.email) = lower(p.email)
);
