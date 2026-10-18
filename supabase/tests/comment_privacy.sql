begin;

do $test$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'content_comment'
      and policyname = 'content_comment_owner_insert'
      and with_check like '%get_my_member_profiles%'
  ) then
    raise exception 'Comment inserts do not validate profiles through the owner RPC';
  end if;

  if has_function_privilege(
    'anon',
    'public.get_content_comments_with_authors(bigint)',
    'execute'
  ) then
    raise exception 'Anonymous users can execute the comments RPC';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.get_content_comments_with_authors(bigint)',
    'execute'
  ) then
    raise exception 'Authenticated users cannot execute the comments RPC';
  end if;

  if exists (
    select 1
    from public.get_content_comments_with_authors(
      coalesce(
        (
          select content_id
          from public.content_comment
          where lower(status) = 'active'
          limit 1
        ),
        -1
      )
    )
    where author_name <> 'Community member'
       or author_avatar is not null
       or user_id is not null
       or member_profile_id is not null
  ) then
    raise exception 'The comments RPC exposes author identity without a caller';
  end if;
end;
$test$;

rollback;
