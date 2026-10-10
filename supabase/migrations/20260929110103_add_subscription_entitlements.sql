-- Preserve the exact activation instant instead of truncating to a calendar date.
alter table public."user"
  alter column payment_date type timestamptz
    using case
      when payment_date is null then null
      else payment_date::timestamp at time zone 'UTC'
    end,
  alter column end_date type timestamptz
    using case
      when end_date is null then null
      else end_date::timestamp at time zone 'UTC'
    end;

create or replace function public.get_my_subscription_state()
returns table (
  is_active boolean,
  subscription_id bigint,
  plan_name varchar,
  monthly_price numeric,
  max_user integer,
  payment_date timestamptz,
  end_date timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(u.end_date > now() and u.subscription_id is not null, false),
    u.subscription_id,
    s.plan_name,
    s.monthly_price,
    s.max_user,
    u.payment_date,
    u.end_date
  from public."user" as u
  left join public.subscription as s
    on s.subscription_id = u.subscription_id
  where u.auth_user_id = (select auth.uid())
  limit 1;
$$;

revoke execute on function public.get_my_subscription_state()
  from public, anon;
grant execute on function public.get_my_subscription_state()
  to authenticated;

create or replace function public.activate_my_subscription(
  selected_subscription_id bigint
)
returns table (
  subscription_id bigint,
  plan_name varchar,
  monthly_price numeric,
  max_user integer,
  payment_date timestamptz,
  end_date timestamptz,
  payment_method varchar,
  reference_number varchar
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_auth_user_id uuid := auth.uid();
  selected_plan public.subscription%rowtype;
  activated_at timestamptz := now();
  affected_rows integer;
begin
  if current_auth_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  select s.* into selected_plan
  from public.subscription as s
  where s.subscription_id = selected_subscription_id;

  if not found then
    raise exception 'Subscription plan does not exist' using errcode = '22023';
  end if;

  update public."user" as u
  set subscription_id = selected_plan.subscription_id,
      payment_date = activated_at,
      payment_amount = selected_plan.monthly_price,
      payment_method = 'prototype',
      reference_number = 'prototype_'
        || replace(gen_random_uuid()::text, '-', ''),
      end_date = activated_at + interval '1 month'
  where u.auth_user_id = current_auth_user_id
    and (u.end_date is null or u.end_date <= activated_at);

  get diagnostics affected_rows = row_count;
  if affected_rows = 0 then
    if exists (
      select 1
      from public."user" as u
      where u.auth_user_id = current_auth_user_id
        and u.end_date > activated_at
    ) then
      raise exception 'Subscription is already active' using errcode = 'P0001';
    end if;
    raise exception 'Application profile does not exist' using errcode = 'P0002';
  end if;

  return query
  select
    selected_plan.subscription_id,
    selected_plan.plan_name,
    selected_plan.monthly_price,
    selected_plan.max_user,
    u.payment_date,
    u.end_date,
    u.payment_method,
    u.reference_number
  from public."user" as u
  where u.auth_user_id = current_auth_user_id;
end;
$$;

revoke execute on function public.activate_my_subscription(bigint)
  from public, anon;
grant execute on function public.activate_my_subscription(bigint)
  to authenticated;
