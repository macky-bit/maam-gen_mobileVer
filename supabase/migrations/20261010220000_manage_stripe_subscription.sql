CREATE OR REPLACE FUNCTION public.sync_stripe_subscription_plan(
  selected_stripe_subscription_id text,
  selected_plan_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  selected_user_id uuid;
BEGIN
  IF nullif(btrim(selected_stripe_subscription_id), '') IS NULL THEN
    RAISE EXCEPTION 'Stripe subscription identity is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.subscription AS plan
    WHERE plan.subscription_id = selected_plan_id
  ) THEN
    RAISE EXCEPTION 'Stripe references an unknown StreamFlix plan';
  END IF;

  UPDATE public.user_subscription AS membership
  SET subscription_id = selected_plan_id
  WHERE membership.stripe_subscription_id = selected_stripe_subscription_id
  RETURNING membership.user_id INTO selected_user_id;

  IF selected_user_id IS NULL THEN
    RAISE EXCEPTION 'Stripe references an unknown StreamFlix subscription';
  END IF;

  UPDATE public."user" AS account
  SET subscription_id = selected_plan_id
  WHERE account.user_id = selected_user_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sync_stripe_subscription_plan(text, bigint)
TO service_role, postgres;

REVOKE ALL ON FUNCTION public.sync_stripe_subscription_plan(text, bigint)
FROM PUBLIC, anon, authenticated;

