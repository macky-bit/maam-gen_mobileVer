alter table public.member_profile
  add column if not exists pin_failed_attempts smallint not null default 0,
  add column if not exists pin_locked_until timestamp with time zone;
alter table public.member_profile
  drop constraint if exists member_profile_pin_failed_attempts_range;
alter table public.member_profile
  add constraint member_profile_pin_failed_attempts_range
    check (pin_failed_attempts >= 0 and pin_failed_attempts <= 5);
comment on column public.member_profile.pin_failed_attempts is
  'Failed PIN checks since the last successful verification or lock reset.';
comment on column public.member_profile.pin_locked_until is
  'Temporary server-side lock expiry after repeated failed PIN checks.';
drop function if exists public.get_my_member_profiles();
create function public.get_my_member_profiles()
returns table (
  member_profile_id bigint,
  profile_name character varying,
  avatar_image text,
  is_kids boolean,
  has_pin boolean,
  display_order smallint,
  is_active boolean,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.member_profile_id,
    profile.profile_name,
    profile.avatar_image,
    profile.is_kids,
    profile.pin_hash is not null as has_pin,
    profile.display_order,
    profile.is_active,
    profile.created_at,
    profile.updated_at
  from public.member_profile as profile
  join public."user" as account
    on account.user_id = profile.user_id
  where account.auth_user_id = (select auth.uid())
    and profile.is_active
  order by profile.display_order;
$$;
revoke all on function public.get_my_member_profiles() from public, anon;
grant execute on function public.get_my_member_profiles()
  to authenticated, postgres, service_role;
create or replace function public.set_my_member_profile_pin(
  selected_profile_id bigint,
  selected_pin text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if selected_pin is not null and selected_pin !~ '^[0-9]{4}$' then
    raise exception 'Profile PIN must contain exactly four digits'
      using errcode = '22023';
  end if;

  update public.member_profile as profile
  set pin_hash = case
        when selected_pin is null then null
        else extensions.crypt(selected_pin, extensions.gen_salt('bf'))
      end,
      pin_failed_attempts = 0,
      pin_locked_until = null
  from public."user" as account
  where profile.member_profile_id = selected_profile_id
    and profile.user_id = account.user_id
    and account.auth_user_id = (select auth.uid())
    and profile.is_active;

  if not found then
    raise exception 'Member profile does not exist' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.set_my_member_profile_pin(bigint, text)
  from public, anon;
grant execute on function public.set_my_member_profile_pin(bigint, text)
  to authenticated, postgres, service_role;
create or replace function public.verify_my_member_profile_pin(
  selected_profile_id bigint,
  selected_pin text
)
returns table (
  is_verified boolean,
  retry_after_seconds integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored_pin_hash text;
  failed_attempts smallint;
  locked_until timestamp with time zone;
  checked_at timestamp with time zone := clock_timestamp();
  next_failed_attempts smallint;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if selected_pin is null or selected_pin !~ '^[0-9]{4}$' then
    raise exception 'Profile PIN must contain exactly four digits'
      using errcode = '22023';
  end if;

  select
    profile.pin_hash,
    profile.pin_failed_attempts,
    profile.pin_locked_until
  into stored_pin_hash, failed_attempts, locked_until
  from public.member_profile as profile
  join public."user" as account
    on account.user_id = profile.user_id
  where profile.member_profile_id = selected_profile_id
    and account.auth_user_id = (select auth.uid())
    and profile.is_active
  for update of profile;

  if not found then
    raise exception 'Member profile does not exist' using errcode = 'P0002';
  end if;

  if stored_pin_hash is null then
    update public.member_profile
    set pin_failed_attempts = 0,
        pin_locked_until = null
    where member_profile_id = selected_profile_id;
    return query select true, 0;
    return;
  end if;

  if locked_until is not null and locked_until > checked_at then
    return query
      select false, greatest(1, ceil(extract(epoch from (locked_until - checked_at)))::integer);
    return;
  end if;

  if extensions.crypt(selected_pin, stored_pin_hash) = stored_pin_hash then
    update public.member_profile
    set pin_failed_attempts = 0,
        pin_locked_until = null
    where member_profile_id = selected_profile_id;
    return query select true, 0;
    return;
  end if;

  next_failed_attempts := case
    when locked_until is not null and locked_until <= checked_at then 1
    else least(failed_attempts + 1, 5)
  end;

  update public.member_profile
  set pin_failed_attempts = next_failed_attempts,
      pin_locked_until = case
        when next_failed_attempts >= 5 then checked_at + interval '15 minutes'
        else null
      end
  where member_profile_id = selected_profile_id;

  return query
    select false, case when next_failed_attempts >= 5 then 900 else 0 end;
end;
$$;
revoke all on function public.verify_my_member_profile_pin(bigint, text)
  from public, anon;
grant execute on function public.verify_my_member_profile_pin(bigint, text)
  to authenticated, postgres, service_role;
create or replace function public.update_my_member_profile(
  selected_profile_id bigint,
  selected_profile_name text,
  selected_avatar_path text,
  selected_pin text default null,
  remove_pin boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text := btrim(selected_profile_name);
  normalized_avatar text := btrim(selected_avatar_path);
  normalized_pin text := nullif(btrim(selected_pin), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if normalized_name = '' or char_length(normalized_name) > 50 then
    raise exception 'Profile name must contain 1 to 50 characters'
      using errcode = '22023';
  end if;
  if normalized_pin is not null and normalized_pin !~ '^[0-9]{4}$' then
    raise exception 'Profile PIN must contain exactly four digits'
      using errcode = '22023';
  end if;
  if not exists (
    select 1
    from storage.objects as avatar
    where avatar.bucket_id = 'avatar'
      and avatar.name = normalized_avatar
  ) then
    raise exception 'Selected avatar does not exist' using errcode = '22023';
  end if;

  update public.member_profile as profile
  set profile_name = normalized_name,
      avatar_image = normalized_avatar,
      pin_hash = case
        when remove_pin then null
        when normalized_pin is not null
          then extensions.crypt(normalized_pin, extensions.gen_salt('bf'))
        else profile.pin_hash
      end,
      pin_failed_attempts = case
        when remove_pin or normalized_pin is not null then 0
        else profile.pin_failed_attempts
      end,
      pin_locked_until = case
        when remove_pin or normalized_pin is not null then null
        else profile.pin_locked_until
      end
  from public."user" as account
  where profile.member_profile_id = selected_profile_id
    and profile.user_id = account.user_id
    and account.auth_user_id = (select auth.uid())
    and profile.is_active;

  if not found then
    raise exception 'Member profile does not exist' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.update_my_member_profile(bigint, text, text, text, boolean)
  from public, anon;
grant execute on function public.update_my_member_profile(bigint, text, text, text, boolean)
  to authenticated, postgres, service_role;
