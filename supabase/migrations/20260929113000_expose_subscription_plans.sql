create or replace function public.get_subscription_plans()
returns table (
  subscription_id bigint,
  plan_name text,
  monthly_price numeric,
  max_user integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.subscription_id,
    s.plan_name::text,
    s.monthly_price,
    s.max_user
  from public.subscription as s
  order by s.monthly_price, s.subscription_id;
$$;

revoke execute on function public.get_subscription_plans()
  from public, anon;
grant execute on function public.get_subscription_plans()
  to authenticated;
