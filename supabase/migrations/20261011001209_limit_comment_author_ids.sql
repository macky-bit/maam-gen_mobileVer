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
  with current_account as (
    select account.user_id
    from public."user" as account
    where account.auth_user_id = (select auth.uid())
    limit 1
  )
  select
    comment.comment_id,
    comment.comment_text,
    comment.commented_at,
    case
      when comment.user_id = current_account.user_id then comment.user_id
    end as user_id,
    comment.status,
    case
      when comment.user_id = current_account.user_id
        then comment.member_profile_id
    end as member_profile_id,
    'Community member'::text as author_name,
    null::text as author_avatar
  from public.content_comment as comment
  left join current_account on true
  where comment.content_id = selected_content_id
    and lower(comment.status) = 'active'
  order by comment.commented_at desc;
$$;

revoke all on function public.get_content_comments_with_authors(bigint)
  from public, anon;
grant execute on function public.get_content_comments_with_authors(bigint)
  to authenticated, postgres, service_role;
