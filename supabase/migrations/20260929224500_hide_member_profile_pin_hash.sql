drop policy if exists member_profile_owner_select
  on public.member_profile;

create or replace function public.get_my_member_profiles()
returns table (
  member_profile_id bigint,
  profile_name varchar,
  avatar_image text,
  is_kids boolean,
  display_order smallint,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.member_profile_id,
    profile.profile_name,
    profile.avatar_image,
    profile.is_kids,
    profile.display_order,
    profile.is_active,
    profile.created_at,
    profile.updated_at
  from public.member_profile as profile
  join public."user" as account
    on account.user_id = profile.user_id
  where account.auth_user_id = (select auth.uid())
    and profile.is_active
  order by profile.display_order;
$$;

revoke execute on function public.get_my_member_profiles()
  from public, anon;
grant execute on function public.get_my_member_profiles()
  to authenticated;
