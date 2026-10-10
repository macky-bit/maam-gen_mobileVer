drop function if exists public.get_my_account_settings();

create function public.get_my_account_settings()
returns table (
  user_id uuid,
  first_name varchar,
  last_name varchar,
  username varchar,
  account_avatar text,
  email varchar,
  date_of_birth date,
  user_role varchar,
  subscription_id bigint,
  plan_name varchar,
  monthly_price numeric,
  max_user integer,
  payment_date timestamptz,
  payment_amount numeric,
  end_date timestamptz,
  payment_method varchar,
  reference_number varchar
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    account.user_id,
    account.first_name,
    account.last_name,
    account.username,
    account.avatar_image,
    account.email,
    account.date_of_birth,
    account.user_role,
    account.subscription_id,
    plan.plan_name,
    plan.monthly_price,
    plan.max_user,
    account.payment_date,
    account.payment_amount,
    account.end_date,
    account.payment_method,
    account.reference_number
  from public."user" as account
  left join public.subscription as plan
    on plan.subscription_id = account.subscription_id
  where account.auth_user_id = (select auth.uid())
  limit 1;
$$;

revoke execute on function public.get_my_account_settings()
  from public, anon;
grant execute on function public.get_my_account_settings()
  to authenticated;

create or replace function public.update_my_account_profile(
  selected_first_name text,
  selected_last_name text,
  selected_username text,
  selected_birth_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_first_name text := btrim(selected_first_name);
  normalized_last_name text := btrim(selected_last_name);
  normalized_username text := lower(btrim(selected_username));
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if normalized_first_name = '' or char_length(normalized_first_name) > 80 then
    raise exception 'First name must contain 1 to 80 characters'
      using errcode = '22023';
  end if;
  if char_length(normalized_last_name) > 80 then
    raise exception 'Last name must contain at most 80 characters'
      using errcode = '22023';
  end if;
  if normalized_username !~ '^[a-z0-9_.]{3,50}$' then
    raise exception 'Username must be 3 to 50 letters, numbers, dots, or underscores'
      using errcode = '22023';
  end if;
  if selected_birth_date is null or selected_birth_date > current_date then
    raise exception 'A valid birthdate is required' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public."user" as other_account
    where lower(other_account.username) = normalized_username
      and other_account.auth_user_id <> (select auth.uid())
  ) then
    raise exception 'Username is already in use' using errcode = '23505';
  end if;

  update public."user" as account
  set first_name = normalized_first_name,
      last_name = normalized_last_name,
      username = normalized_username,
      date_of_birth = selected_birth_date
  where account.auth_user_id = (select auth.uid());

  if not found then
    raise exception 'Application account does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.update_my_account_profile(text, text, text, date)
  from public, anon;
grant execute on function public.update_my_account_profile(text, text, text, date)
  to authenticated;

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

revoke execute on function public.update_my_member_profile(bigint, text, text, text, boolean)
  from public, anon;
grant execute on function public.update_my_member_profile(bigint, text, text, text, boolean)
  to authenticated;

create or replace function public.sync_streamflix_account_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email
    and new.email_confirmed_at is not null then
    update public."user" as account
    set email = new.email
    where account.auth_user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_sync on auth.users;
create trigger on_auth_user_email_sync
  after update of email on auth.users
  for each row execute function public.sync_streamflix_account_email();
