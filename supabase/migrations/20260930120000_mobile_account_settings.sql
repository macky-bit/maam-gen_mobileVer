create or replace function public.get_my_account_settings()
returns table (
  email varchar,
  date_of_birth date,
  plan_name varchar,
  end_date timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select account.email, account.date_of_birth, plan.plan_name, account.end_date
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

create or replace function public.update_my_birth_date(
  selected_birth_date date
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
  if selected_birth_date is null or selected_birth_date > current_date then
    raise exception 'A valid birthdate is required' using errcode = '22023';
  end if;

  update public."user" as account
  set date_of_birth = selected_birth_date
  where account.auth_user_id = (select auth.uid());

  if not found then
    raise exception 'Application account does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.update_my_birth_date(date)
  from public, anon;
grant execute on function public.update_my_birth_date(date)
  to authenticated;

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

revoke execute on function public.set_my_member_profile_pin(bigint, text)
  from public, anon;
grant execute on function public.set_my_member_profile_pin(bigint, text)
  to authenticated;
