begin;
alter table public."user"
  add column if not exists stripe_customer_id text;
alter table public.subscription
  add column if not exists stripe_price_id text;
-- Align the catalog with the Stripe products supplied for each named tier.
update public.subscription
set plan_name = 'Basic',
    stripe_price_id = 'price_1UOEDyLGgTIH0kAM5vLUzKhi'
where monthly_price = 199 and max_user = 1;
update public.subscription
set plan_name = 'Standard',
    stripe_price_id = 'price_1UOEElLGgTIH0kAMacbcvLjP'
where monthly_price = 299 and max_user = 2;
update public.subscription
set plan_name = 'Premium',
    stripe_price_id = 'price_1UOEFDLGgTIH0kAM7GzVwjp7'
where monthly_price = 499 and max_user = 4;
create unique index if not exists subscription_stripe_price_unique
  on public.subscription (stripe_price_id)
  where stripe_price_id is not null;
create unique index if not exists app_user_stripe_customer_unique
  on public."user" (stripe_customer_id)
  where stripe_customer_id is not null;
alter table public.user_subscription
  add column if not exists stripe_subscription_id text,
  add column if not exists stripe_checkout_session_id text;
create unique index if not exists user_subscription_stripe_subscription_unique
  on public.user_subscription (stripe_subscription_id)
  where stripe_subscription_id is not null;
create unique index if not exists user_subscription_stripe_checkout_unique
  on public.user_subscription (stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;
alter table public.payment_transaction
  add column if not exists stripe_invoice_id text,
  add column if not exists stripe_payment_intent_id text,
  add column if not exists stripe_checkout_session_id text,
  add column if not exists currency varchar(3),
  add column if not exists receipt_url text;
create unique index if not exists payment_transaction_stripe_invoice_unique
  on public.payment_transaction (stripe_invoice_id)
  where stripe_invoice_id is not null;
create table if not exists public.stripe_webhook_event (
  event_id text primary key,
  event_type text not null,
  processed_at timestamptz not null default now()
);
alter table public.stripe_webhook_event enable row level security;
revoke all on table public.stripe_webhook_event from public, anon, authenticated;
grant select, insert on table public.stripe_webhook_event to service_role;
create or replace function public.process_stripe_billing_event(
  p_event_id text,
  p_event_type text,
  p_data jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_rows integer;
  app_user_id uuid;
  plan_id bigint;
  membership_id bigint;
  normalized_status text;
begin
  if nullif(btrim(p_event_id), '') is null
    or nullif(btrim(p_event_type), '') is null then
    raise exception 'Stripe event identity is required';
  end if;

  insert into public.stripe_webhook_event (event_id, event_type)
  values (p_event_id, p_event_type)
  on conflict (event_id) do nothing;

  get diagnostics inserted_rows = row_count;
  if inserted_rows = 0 then
    return false;
  end if;

  if p_event_type in ('checkout.session.completed', 'invoice.paid') then
    app_user_id := nullif(p_data ->> 'user_id', '')::uuid;
    plan_id := nullif(p_data ->> 'plan_id', '')::bigint;

    if app_user_id is null or plan_id is null then
      raise exception 'Stripe payment metadata is incomplete';
    end if;
    if not exists (select 1 from public."user" where user_id = app_user_id) then
      raise exception 'Stripe payment references an unknown StreamFlix user';
    end if;
    if not exists (select 1 from public.subscription where subscription_id = plan_id) then
      raise exception 'Stripe payment references an unknown StreamFlix plan';
    end if;

    update public.user_subscription
    set status = 'Canceled',
        ends_at = coalesce(ends_at, now())
    where user_id = app_user_id
      and lower(status) = 'active'
      and stripe_subscription_id is distinct from nullif(p_data ->> 'stripe_subscription_id', '');

    select user_subscription_id
      into membership_id
    from public.user_subscription
    where stripe_subscription_id = nullif(p_data ->> 'stripe_subscription_id', '')
       or (
         stripe_subscription_id is null
         and user_id = app_user_id
         and lower(status) = 'active'
       )
    order by (stripe_subscription_id is not null) desc, created_at desc
    limit 1;

    if membership_id is null then
      insert into public.user_subscription (
        user_id,
        subscription_id,
        started_at,
        ends_at,
        status,
        stripe_subscription_id,
        stripe_checkout_session_id
      ) values (
        app_user_id,
        plan_id,
        coalesce(nullif(p_data ->> 'period_start', '')::timestamptz, now()),
        nullif(p_data ->> 'period_end', '')::timestamptz,
        'Active',
        nullif(p_data ->> 'stripe_subscription_id', ''),
        nullif(p_data ->> 'checkout_session_id', '')
      ) returning user_subscription_id into membership_id;
    else
      update public.user_subscription
      set subscription_id = plan_id,
          started_at = coalesce(nullif(p_data ->> 'period_start', '')::timestamptz, started_at, now()),
          ends_at = nullif(p_data ->> 'period_end', '')::timestamptz,
          status = 'Active',
          stripe_subscription_id = coalesce(nullif(p_data ->> 'stripe_subscription_id', ''), stripe_subscription_id),
          stripe_checkout_session_id = coalesce(nullif(p_data ->> 'checkout_session_id', ''), stripe_checkout_session_id)
      where user_subscription_id = membership_id;
    end if;

    update public."user"
    set subscription_id = plan_id,
        stripe_customer_id = coalesce(nullif(p_data ->> 'stripe_customer_id', ''), stripe_customer_id),
        payment_date = case when p_event_type = 'invoice.paid' then now() else payment_date end,
        payment_amount = case
          when p_event_type = 'invoice.paid' then coalesce(nullif(p_data ->> 'amount_total', '')::numeric, 0) / 100
          else payment_amount
        end,
        payment_method = case when p_event_type = 'invoice.paid' then 'Stripe' else payment_method end,
        reference_number = case
          when p_event_type = 'invoice.paid' then coalesce(
            nullif(p_data ->> 'stripe_invoice_id', ''),
            nullif(p_data ->> 'stripe_payment_intent_id', ''),
            p_event_id
          )
          else reference_number
        end,
        end_date = nullif(p_data ->> 'period_end', '')::timestamptz
    where user_id = app_user_id;

    if p_event_type = 'invoice.paid'
      and nullif(p_data ->> 'stripe_invoice_id', '') is not null then
      insert into public.payment_transaction (
        user_id,
        user_subscription_id,
        amount,
        payment_method,
        reference_number,
        status,
        paid_at,
        stripe_invoice_id,
        stripe_payment_intent_id,
        stripe_checkout_session_id,
        currency,
        receipt_url
      ) values (
        app_user_id,
        membership_id,
        coalesce(nullif(p_data ->> 'amount_total', '')::numeric, 0) / 100,
        'Stripe',
        nullif(p_data ->> 'stripe_invoice_id', ''),
        'Paid',
        now(),
        nullif(p_data ->> 'stripe_invoice_id', ''),
        nullif(p_data ->> 'stripe_payment_intent_id', ''),
        nullif(p_data ->> 'checkout_session_id', ''),
        upper(nullif(p_data ->> 'currency', '')),
        nullif(p_data ->> 'receipt_url', '')
      ) on conflict do nothing;
    end if;

  elsif p_event_type in (
    'customer.subscription.updated',
    'customer.subscription.deleted',
    'invoice.payment_failed'
  ) then
    normalized_status := case
      when p_event_type = 'customer.subscription.deleted' then 'Canceled'
      when p_event_type = 'invoice.payment_failed' then 'Past Due'
      when lower(coalesce(p_data ->> 'stripe_status', '')) in ('active', 'trialing') then 'Active'
      when lower(coalesce(p_data ->> 'stripe_status', '')) = 'past_due' then 'Past Due'
      else 'Inactive'
    end;

    update public.user_subscription
    set status = normalized_status,
        ends_at = coalesce(
          nullif(p_data ->> 'period_end', '')::timestamptz,
          case when normalized_status = 'Canceled' then now() else ends_at end
        )
    where stripe_subscription_id = nullif(p_data ->> 'stripe_subscription_id', '')
    returning user_id into app_user_id;

    if app_user_id is not null then
      if normalized_status = 'Active' then
        update public."user"
        set subscription_id = (
              select subscription_id
              from public.user_subscription
              where stripe_subscription_id = nullif(p_data ->> 'stripe_subscription_id', '')
            ),
            end_date = nullif(p_data ->> 'period_end', '')::timestamptz
        where user_id = app_user_id;
      elsif not exists (
        select 1
        from public.user_subscription
        where user_id = app_user_id
          and lower(status) = 'active'
          and (ends_at is null or ends_at > now())
      ) then
        update public."user"
        set subscription_id = null,
            end_date = coalesce(nullif(p_data ->> 'period_end', '')::timestamptz, now())
        where user_id = app_user_id;
      end if;
    end if;
  end if;

  return true;
end;
$$;
revoke all on function public.process_stripe_billing_event(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.process_stripe_billing_event(text, text, jsonb)
  to service_role, postgres;
-- Direct client-side activation is retired. Only the verified Stripe webhook
-- may create or activate paid subscriptions.
revoke execute on function public.select_subscription_plan(bigint)
  from public, anon, authenticated;
commit;
