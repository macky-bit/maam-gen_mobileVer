create or replace function public.select_subscription_plan(
  selected_subscription_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid;
  updated_rows integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select user_id into current_user_id
  from public."user"
  where auth_user_id = auth.uid()
  limit 1;

  if current_user_id is null then
    raise exception 'No StreamFlix profile is linked to this account';
  end if;

  if not exists (
    select 1 from public.subscription
    where subscription_id = selected_subscription_id
  ) then
    raise exception 'The selected subscription plan does not exist';
  end if;

  update public."user"
  set subscription_id = selected_subscription_id
  where user_id = current_user_id;

  update public.user_subscription
  set subscription_id = selected_subscription_id,
      started_at = now(),
      ends_at = null,
      status = 'Active'
  where user_id = current_user_id
    and status = 'Active';

  get diagnostics updated_rows = row_count;
  if updated_rows = 0 then
    insert into public.user_subscription (user_id, subscription_id, status)
    values (current_user_id, selected_subscription_id, 'Active');
  end if;
end;
$$;
revoke all on function public.select_subscription_plan(bigint) from public;
grant execute on function public.select_subscription_plan(bigint) to authenticated;
