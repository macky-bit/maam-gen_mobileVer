CREATE OR REPLACE FUNCTION public.delete_my_member_profile(selected_profile_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  current_user_id uuid;
  active_profile_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '28000';
  END IF;

  SELECT account.user_id
  INTO current_user_id
  FROM public."user" AS account
  WHERE account.auth_user_id = auth.uid()
  FOR UPDATE;

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Application account does not exist' USING ERRCODE = 'P0002';
  END IF;

  PERFORM 1
  FROM public.member_profile AS profile
  WHERE profile.member_profile_id = selected_profile_id
    AND profile.user_id = current_user_id
    AND profile.is_active
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile does not exist' USING ERRCODE = 'P0002';
  END IF;

  SELECT count(*)::integer
  INTO active_profile_count
  FROM public.member_profile AS profile
  WHERE profile.user_id = current_user_id
    AND profile.is_active;

  IF active_profile_count <= 1 THEN
    RAISE EXCEPTION 'At least one profile is required' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.member_profile AS profile
  SET
    is_active = false,
    pin_hash = NULL,
    pin_failed_attempts = 0,
    pin_locked_until = NULL
  WHERE profile.member_profile_id = selected_profile_id
    AND profile.user_id = current_user_id
    AND profile.is_active;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_my_member_profile(bigint)
TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.delete_my_member_profile(bigint) FROM PUBLIC;
