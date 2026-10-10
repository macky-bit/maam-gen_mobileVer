begin;

update public."user"
set end_date = now() + interval '1 day'
where user_id in (
  select user_id
  from (
    select distinct on (subscription_id) subscription_id, user_id
    from public."user"
    where subscription_id in (1, 2, 3)
      and auth_user_id is not null
    order by subscription_id, user_id
  ) as one_account_per_plan
);

select set_config(
  'test.standard_auth_id',
  (
    select auth_user_id::text
    from public."user"
    where subscription_id = 1
      and auth_user_id is not null
    limit 1
  ),
  true
);

select set_config(
  'test.basic_auth_id',
  (
    select auth_user_id::text
    from public."user"
    where subscription_id = 2
      and auth_user_id is not null
    limit 1
  ),
  true
);

select set_config(
  'test.premium_auth_id',
  (
    select auth_user_id::text
    from public."user"
    where subscription_id = 3
      and auth_user_id is not null
    limit 1
  ),
  true
);

set local role authenticated;

do $test$
declare
  avatar_path text;
  context_row record;
begin
  select name into avatar_path
  from storage.objects
  where bucket_id = 'avatar'
  order by name
  limit 1;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.standard_auth_id'),
    true
  );

  begin
    perform public.create_my_member_profile('Kids', avatar_path, true, null);
    raise exception 'Standard allowed a Kids profile' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  perform public.create_my_member_profile('Standard Adult', avatar_path, false, null);

  select * into context_row
  from public.get_my_member_profile_context();

  if context_row.max_profiles <> 1
    or context_row.allows_kids
    or context_row.active_profile_count <> 1
    or context_row.can_add_profile then
    raise exception 'Standard profile context validation failed';
  end if;

  begin
    perform public.create_my_member_profile('Second', avatar_path, false, null);
    raise exception 'Standard profile limit was not enforced' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.basic_auth_id'),
    true
  );

  perform public.create_my_member_profile('Kids', avatar_path, true, null);
  perform public.create_my_member_profile('Adult', avatar_path, false, '1234');

  select * into context_row
  from public.get_my_member_profile_context();

  if context_row.max_profiles <> 2
    or not context_row.allows_kids
    or context_row.active_profile_count <> 2
    or context_row.can_add_profile then
    raise exception 'Basic profile context validation failed';
  end if;

  begin
    perform public.create_my_member_profile('Third', avatar_path, false, null);
    raise exception 'Profile limit was not enforced' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    current_setting('test.premium_auth_id'),
    true
  );

  perform public.create_my_member_profile('Premium Kids', avatar_path, true, null);
  perform public.create_my_member_profile('Premium 2', avatar_path, false, null);
  perform public.create_my_member_profile('Premium 3', avatar_path, false, null);
  perform public.create_my_member_profile('Premium 4', avatar_path, false, null);

  select * into context_row
  from public.get_my_member_profile_context();

  if context_row.max_profiles <> 4
    or not context_row.allows_kids
    or context_row.active_profile_count <> 4
    or context_row.can_add_profile then
    raise exception 'Premium profile context validation failed';
  end if;

  begin
    perform public.create_my_member_profile('Premium 5', avatar_path, false, null);
    raise exception 'Premium profile limit was not enforced' using errcode = 'XX000';
  exception
    when sqlstate 'P0001' then null;
  end;
end;
$test$;

rollback;
