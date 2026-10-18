-- Connect title engagement in WatchScreen to Community Admin.

-- Public read policies safely call these security-definer role checks. With no
-- authenticated UID they return false, while allowing PostgREST to evaluate
-- the policy instead of failing with permission denied.
grant execute on function public.is_master_admin() to anon;
grant execute on function public.is_admin_role(varchar) to anon;
alter table public.reaction
  add column if not exists status varchar(30) not null default 'Active';
alter table public.reaction
  drop constraint if exists reaction_status_check;
alter table public.reaction
  add constraint reaction_status_check
  check (status in ('Active', 'Hidden')) not valid;
-- Keep the newest legacy reaction before enforcing one reaction per user/title.
with ranked_reactions as (
  select reaction_id,
    row_number() over (
      partition by content_id, user_id
      order by created_at desc nulls last, reaction_id desc
    ) as duplicate_rank
  from public.reaction
)
delete from public.reaction reaction
using ranked_reactions ranked
where reaction.reaction_id = ranked.reaction_id
  and ranked.duplicate_rank > 1;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reaction_content_user_unique'
      and conrelid = 'public.reaction'::regclass
  ) then
    alter table public.reaction
      add constraint reaction_content_user_unique unique (content_id, user_id);
  end if;
end;
$$;
drop policy if exists comment_manager_can_view_reactions on public.reaction;
drop policy if exists anyone_can_read_reactions on public.reaction;
create policy anyone_can_read_reactions
on public.reaction for select to public
using (
  status = 'Active'
  or public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
);
drop policy if exists reaction_admin_update on public.reaction;
create policy reaction_admin_update
on public.reaction for update to authenticated
using (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
)
with check (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
);
drop policy if exists reaction_owner_insert on public.reaction;
create policy reaction_owner_insert
on public.reaction for insert to authenticated
with check (
  user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists reaction_owner_delete on public.reaction;
create policy reaction_owner_delete
on public.reaction for delete to authenticated
using (
  user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists comment_manager_can_delete_reactions on public.reaction;
create policy comment_manager_can_delete_reactions
on public.reaction for delete to authenticated
using (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
);
drop policy if exists anyone_can_read_comments on public.content_comment;
drop policy if exists content_comment_read on public.content_comment;
create policy content_comment_read
on public.content_comment for select to public
using (
  lower(status) = 'active'
  or public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
);
drop policy if exists user_can_insert_own_comment on public.content_comment;
drop policy if exists content_comment_owner_insert on public.content_comment;
create policy content_comment_owner_insert
on public.content_comment for insert to authenticated
with check (
  user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists allow_comment_delete on public.content_comment;
drop policy if exists content_comment_owner_or_admin_delete on public.content_comment;
create policy content_comment_owner_or_admin_delete
on public.content_comment for delete to authenticated
using (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
  or user_id in (
    select app_user.user_id
    from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists content_comment_admin_update on public.content_comment;
create policy content_comment_admin_update
on public.content_comment for update to authenticated
using (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
)
with check (
  public.is_admin_role('commentManager'::character varying)
  or public.is_master_admin()
);
alter table public.content_comment
  drop constraint if exists content_comment_text_length_check;
alter table public.content_comment
  add constraint content_comment_text_length_check
  check (char_length(btrim(comment_text)) between 1 and 1000) not valid;
