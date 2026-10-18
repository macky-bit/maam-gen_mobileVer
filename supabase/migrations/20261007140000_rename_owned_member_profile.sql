create or replace function public.rename_my_member_profile(
  selected_profile_id bigint,
  selected_profile_name text
)
returns varchar
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text := btrim(regexp_replace(selected_profile_name, '\s+', ' ', 'g'));
  updated_name varchar;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if normalized_name = '' or char_length(normalized_name) > 50 then
    raise exception 'Profile name must contain 1 to 50 characters'
      using errcode = '22023';
  end if;

  update public.member_profile as profile
  set profile_name = normalized_name
  from public."user" as account
  where profile.member_profile_id = selected_profile_id
    and profile.user_id = account.user_id
    and account.auth_user_id = (select auth.uid())
    and profile.is_active
  returning profile.profile_name into updated_name;

  if not found then
    raise exception 'Member profile does not exist' using errcode = 'P0002';
  end if;

  return updated_name;
end;
$$;
revoke execute on function public.rename_my_member_profile(bigint, text)
  from public, anon;
grant execute on function public.rename_my_member_profile(bigint, text)
  to authenticated;
