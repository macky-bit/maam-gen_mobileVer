alter table public.content_comment
  add column if not exists member_profile_id bigint;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'content_comment_member_profile_id_fkey'
  ) then
    alter table public.content_comment
      add constraint content_comment_member_profile_id_fkey
      foreign key (member_profile_id)
      references public.member_profile(member_profile_id)
      on update cascade
      on delete set null;
  end if;
end;
$$;

create index if not exists content_comment_member_profile_id_idx
  on public.content_comment(member_profile_id);

comment on column public.content_comment.member_profile_id is
  'Viewing profile used when the comment was posted; null for legacy comments.';

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

  if (
    new.content_id is distinct from old.content_id
    or new.user_id is distinct from old.user_id
    or new.member_profile_id is distinct from old.member_profile_id
  )
    and not public.is_admin_role('commentManager'::character varying)
    and not public.is_master_admin()
  then
    raise exception 'Comment authorship cannot be changed';
  end if;

  return new;
end;
$$;

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
    or exists (
      select 1
      from public.member_profile as profile
      where profile.member_profile_id = content_comment.member_profile_id
        and profile.user_id = content_comment.user_id
        and profile.is_active
    )
  )
);

create or replace function public.get_content_comments_with_authors(
  selected_content_id bigint
)
returns table (
  comment_id bigint,
  comment_text text,
  commented_at timestamp without time zone,
  user_id uuid,
  status character varying,
  member_profile_id bigint,
  author_name text,
  author_avatar text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    comment.comment_id,
    comment.comment_text,
    comment.commented_at,
    comment.user_id,
    comment.status,
    comment.member_profile_id,
    coalesce(
      nullif(btrim(profile.profile_name), ''),
      nullif(btrim(account.username), ''),
      nullif(btrim(concat_ws(' ', account.first_name, account.last_name)), ''),
      'Community member'
    ) as author_name,
    coalesce(
      nullif(btrim(profile.avatar_image), ''),
      nullif(btrim(account.avatar_image), '')
    ) as author_avatar
  from public.content_comment as comment
  join public."user" as account
    on account.user_id = comment.user_id
  left join public.member_profile as profile
    on profile.member_profile_id = comment.member_profile_id
   and profile.user_id = comment.user_id
  where comment.content_id = selected_content_id
    and lower(comment.status) = 'active'
  order by comment.commented_at desc;
$$;

revoke all on function public.get_content_comments_with_authors(bigint)
  from public;
grant execute on function public.get_content_comments_with_authors(bigint)
  to anon, authenticated, postgres, service_role;
