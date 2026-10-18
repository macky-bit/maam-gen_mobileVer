drop policy if exists content_comment_owner_insert on public.content_comment;
create policy content_comment_owner_insert
on public.content_comment for insert to authenticated
with check (
  user_id in (
    select app_user.user_id
    from public."user" as app_user
    where app_user.auth_user_id = (select auth.uid())
  )
  and (
    member_profile_id is null
    or member_profile_id in (
      select profile.member_profile_id
      from public.get_my_member_profiles() as profile
    )
  )
);
