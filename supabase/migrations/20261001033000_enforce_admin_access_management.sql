-- Enforce administrator status in every authorization check and expose
-- narrowly-scoped Master Admin operations for granting and revoking access.

create or replace function public.is_master_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admin
    where auth_user_id = (select auth.uid())
      and lower(replace(role, ' ', '')) = 'masteradmin'
      and lower(coalesce(status, 'Active')) = 'active'
  ) or exists (
    select 1
    from public."user"
    where auth_user_id = (select auth.uid())
      and lower(replace(user_role, ' ', '')) = 'masteradmin'
      and lower(coalesce(account_status, 'Active')) = 'active'
  );
$$;
create or replace function public.is_admin_role(required_role varchar)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_master_admin() or exists (
    select 1
    from public.admin
    where auth_user_id = (select auth.uid())
      and lower(replace(role, ' ', '')) = lower(replace(required_role, ' ', ''))
      and lower(coalesce(status, 'Active')) = 'active'
  );
$$;
create or replace function public.is_any_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_master_admin() or exists (
    select 1
    from public.admin
    where auth_user_id = (select auth.uid())
      and lower(coalesce(status, 'Active')) = 'active'
  );
$$;
create or replace function public.get_admin_role()
returns varchar
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when public.is_master_admin() then 'masterAdmin'::varchar
    else (
      select role
      from public.admin
      where auth_user_id = (select auth.uid())
        and lower(coalesce(status, 'Active')) = 'active'
      limit 1
    )
  end;
$$;
create or replace function public.get_my_admin_access()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'adminId', admin_id,
        'role', role,
        'status', coalesce(status, 'Active')
      )
      from public.admin
      where auth_user_id = (select auth.uid())
      limit 1
    ),
    (
      select jsonb_build_object(
        'adminId', null,
        'role', 'masterAdmin',
        'status', coalesce(account_status, 'Active')
      )
      from public."user"
      where auth_user_id = (select auth.uid())
        and lower(replace(user_role, ' ', '')) = 'masteradmin'
      limit 1
    )
  );
$$;
create or replace function public.find_user_for_admin(target_uuid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'userId', u.user_id,
    'authUserId', u.auth_user_id,
    'name', trim(concat_ws(' ', u.first_name, u.last_name)),
    'email', u.email,
    'username', u.username,
    'accountStatus', coalesce(u.account_status, 'Active'),
    'existingAdminId', a.admin_id,
    'existingRole', a.role,
    'existingStatus', a.status
  )
  into result
  from public."user" u
  left join public.admin a on a.auth_user_id = u.auth_user_id
  where u.user_id = target_uuid or u.auth_user_id = target_uuid
  order by (u.auth_user_id = target_uuid) desc
  limit 1;

  return result;
end;
$$;
create or replace function public.grant_admin_access(target_uuid uuid, assigned_role varchar)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_user public."user"%rowtype;
  existing_admin public.admin%rowtype;
  saved_admin public.admin%rowtype;
  normalized_role varchar;
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;

  normalized_role := case lower(replace(assigned_role, ' ', ''))
    when 'masteradmin' then 'masterAdmin'
    when 'contentmanager' then 'contentManager'
    when 'commentmanager' then 'commentManager'
    when 'feedbackmanager' then 'feedbackManager'
    when 'usermanager' then 'userManager'
    when 'systemmanager' then 'systemManager'
    else null
  end;
  if normalized_role is null then
    raise exception 'Invalid administrator role.' using errcode = '22023';
  end if;

  select * into target_user
  from public."user"
  where user_id = target_uuid or auth_user_id = target_uuid
  order by (auth_user_id = target_uuid) desc
  limit 1;

  if not found then
    raise exception 'No StreamFlix user was found for that UUID.' using errcode = 'P0002';
  end if;
  if target_user.auth_user_id is null then
    raise exception 'This user is not linked to a Supabase Auth account.' using errcode = '22023';
  end if;

  select * into existing_admin
  from public.admin
  where auth_user_id = target_user.auth_user_id
  limit 1;

  if found then
    update public.admin
    set role = normalized_role,
        status = 'Active',
        full_name = trim(concat_ws(' ', target_user.first_name, target_user.last_name)),
        email = target_user.email,
        username = target_user.username,
        updated_at = now()
    where admin_id = existing_admin.admin_id
    returning * into saved_admin;
  else
    insert into public.admin (auth_user_id, full_name, email, username, password, role, status)
    values (
      target_user.auth_user_id,
      trim(concat_ws(' ', target_user.first_name, target_user.last_name)),
      target_user.email,
      target_user.username,
      'managed_by_supabase_auth',
      normalized_role,
      'Active'
    )
    returning * into saved_admin;
  end if;

  return jsonb_build_object('adminId', saved_admin.admin_id, 'role', saved_admin.role, 'status', saved_admin.status);
end;
$$;
create or replace function public.set_admin_access_status(target_admin_id uuid, new_status varchar)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.admin%rowtype;
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;
  if new_status not in ('Active', 'Inactive') then
    raise exception 'Invalid administrator status.' using errcode = '22023';
  end if;

  select * into target from public.admin where admin_id = target_admin_id;
  if not found then raise exception 'Administrator not found.' using errcode = 'P0002'; end if;
  if target.auth_user_id = (select auth.uid()) and new_status = 'Inactive' then
    raise exception 'You cannot deactivate your own Master Admin access.' using errcode = '22023';
  end if;
  if lower(replace(target.role, ' ', '')) = 'masteradmin' and new_status = 'Inactive'
     and (select count(*) from public.admin where lower(replace(role, ' ', '')) = 'masteradmin' and lower(coalesce(status, 'Active')) = 'active') <= 1 then
    raise exception 'At least one active Master Admin is required.' using errcode = '22023';
  end if;

  update public.admin set status = new_status, updated_at = now() where admin_id = target_admin_id;
end;
$$;
create or replace function public.set_admin_access_role(target_admin_id uuid, assigned_role varchar)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.admin%rowtype;
  normalized_role varchar;
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;
  normalized_role := case lower(replace(assigned_role, ' ', ''))
    when 'masteradmin' then 'masterAdmin'
    when 'contentmanager' then 'contentManager'
    when 'commentmanager' then 'commentManager'
    when 'feedbackmanager' then 'feedbackManager'
    when 'usermanager' then 'userManager'
    when 'systemmanager' then 'systemManager'
    else null
  end;
  if normalized_role is null then raise exception 'Invalid administrator role.' using errcode = '22023'; end if;

  select * into target from public.admin where admin_id = target_admin_id;
  if not found then raise exception 'Administrator not found.' using errcode = 'P0002'; end if;
  if target.auth_user_id = (select auth.uid()) and lower(replace(normalized_role, ' ', '')) <> 'masteradmin' then
    raise exception 'You cannot remove your own Master Admin role.' using errcode = '22023';
  end if;
  if lower(replace(target.role, ' ', '')) = 'masteradmin'
     and lower(replace(normalized_role, ' ', '')) <> 'masteradmin'
     and lower(coalesce(target.status, 'Active')) = 'active'
     and (select count(*) from public.admin where lower(replace(role, ' ', '')) = 'masteradmin' and lower(coalesce(status, 'Active')) = 'active') <= 1 then
    raise exception 'At least one active Master Admin is required.' using errcode = '22023';
  end if;

  update public.admin set role = normalized_role, updated_at = now() where admin_id = target_admin_id;
end;
$$;
create or replace function public.update_admin_profile(target_admin_id uuid, new_name varchar, new_email varchar, new_username varchar)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;
  update public.admin
  set full_name = trim(new_name), email = trim(new_email), username = trim(new_username), updated_at = now()
  where admin_id = target_admin_id;
  if not found then raise exception 'Administrator not found.' using errcode = 'P0002'; end if;
end;
$$;
create or replace function public.remove_admin_access(target_admin_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.admin%rowtype;
begin
  if not public.is_master_admin() then
    raise exception 'Master Admin access is required.' using errcode = '42501';
  end if;
  select * into target from public.admin where admin_id = target_admin_id;
  if not found then raise exception 'Administrator not found.' using errcode = 'P0002'; end if;
  if target.auth_user_id = (select auth.uid()) then
    raise exception 'You cannot remove your own Master Admin access.' using errcode = '22023';
  end if;
  if lower(replace(target.role, ' ', '')) = 'masteradmin'
     and lower(coalesce(target.status, 'Active')) = 'active'
     and (select count(*) from public.admin where lower(replace(role, ' ', '')) = 'masteradmin' and lower(coalesce(status, 'Active')) = 'active') <= 1 then
    raise exception 'At least one active Master Admin is required.' using errcode = '22023';
  end if;
  delete from public.admin where admin_id = target_admin_id;
end;
$$;
-- Admin rows are read directly; all mutations go through the guarded RPCs above.
drop policy if exists master_admin_manage_admins on public.admin;
revoke execute on function public.get_my_admin_access() from public;
revoke execute on function public.find_user_for_admin(uuid) from public;
revoke execute on function public.grant_admin_access(uuid, varchar) from public;
revoke execute on function public.set_admin_access_status(uuid, varchar) from public;
revoke execute on function public.set_admin_access_role(uuid, varchar) from public;
revoke execute on function public.update_admin_profile(uuid, varchar, varchar, varchar) from public;
revoke execute on function public.remove_admin_access(uuid) from public;
grant execute on function public.get_my_admin_access() to authenticated;
grant execute on function public.find_user_for_admin(uuid) to authenticated;
grant execute on function public.grant_admin_access(uuid, varchar) to authenticated;
grant execute on function public.set_admin_access_status(uuid, varchar) to authenticated;
grant execute on function public.set_admin_access_role(uuid, varchar) to authenticated;
grant execute on function public.update_admin_profile(uuid, varchar, varchar, varchar) to authenticated;
grant execute on function public.remove_admin_access(uuid) to authenticated;
