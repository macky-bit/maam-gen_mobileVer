create or replace function public.protect_content_comment_moderation_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status
    and not public.is_admin_role('commentManager'::character varying)
    and not public.is_master_admin()
  then
    raise exception 'Only community moderators can change comment status';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_content_comment_moderation_fields on public.content_comment;
create trigger protect_content_comment_moderation_fields
before update on public.content_comment
for each row execute function public.protect_content_comment_moderation_fields();
drop policy if exists content_comment_owner_update on public.content_comment;
create policy content_comment_owner_update
on public.content_comment for update to authenticated
using (
  user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
)
with check (
  user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
