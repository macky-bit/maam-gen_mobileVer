drop function if exists public.get_my_account_settings();

create function public.get_my_account_settings()
returns table (
  first_name varchar,
  last_name varchar,
  email varchar,
  date_of_birth date,
  plan_name varchar,
  monthly_price numeric,
  max_user integer,
  payment_date timestamptz,
  payment_amount numeric,
  end_date timestamptz,
  payment_method varchar
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    account.first_name,
    account.last_name,
    account.email,
    account.date_of_birth,
    plan.plan_name,
    plan.monthly_price,
    plan.max_user,
    account.payment_date,
    account.payment_amount,
    account.end_date,
    account.payment_method
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

drop function if exists public.update_my_account_profile(text, text, text, date);

create function public.update_my_account_profile(
  selected_first_name text,
  selected_last_name text,
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
  if selected_birth_date is null or selected_birth_date > current_date then
    raise exception 'A valid birthdate is required' using errcode = '22023';
  end if;

  update public."user" as account
  set first_name = normalized_first_name,
      last_name = normalized_last_name,
      date_of_birth = selected_birth_date
  where account.auth_user_id = (select auth.uid());

  if not found then
    raise exception 'Application account does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.update_my_account_profile(text, text, date)
  from public, anon;
grant execute on function public.update_my_account_profile(text, text, date)
  to authenticated;
