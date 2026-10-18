-- Keep the administrator directory's last-login value aligned with the
-- timestamp maintained by Supabase Auth. This records successful sign-ins at
-- the database boundary, so every login path (including OAuth) is covered.

create or replace function public.sync_admin_last_login_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.last_sign_in_at is not null
     and new.last_sign_in_at is distinct from old.last_sign_in_at then
    update public.admin
    set
      last_login = new.last_sign_in_at,
      updated_at = now()
    where auth_user_id = new.id;
  end if;

  return new;
end;
$function$;
revoke all on function public.sync_admin_last_login_from_auth() from public, anon, authenticated;
drop trigger if exists sync_admin_last_login_from_auth on auth.users;
create trigger sync_admin_last_login_from_auth
after update of last_sign_in_at on auth.users
for each row
execute function public.sync_admin_last_login_from_auth();
-- Admin access can be assigned after an Auth user has already signed in. In
-- that case, initialize the admin row from the existing Auth timestamp.
create or replace function public.initialize_admin_last_login()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.last_login is null and new.auth_user_id is not null then
    select auth_user.last_sign_in_at
    into new.last_login
    from auth.users as auth_user
    where auth_user.id = new.auth_user_id;
  end if;

  return new;
end;
$function$;
revoke all on function public.initialize_admin_last_login() from public, anon, authenticated;
drop trigger if exists initialize_admin_last_login on public.admin;
create trigger initialize_admin_last_login
before insert or update of auth_user_id on public.admin
for each row
execute function public.initialize_admin_last_login();
-- Populate existing administrators without inventing synthetic login dates.
update public.admin as administrator
set
  last_login = auth_user.last_sign_in_at,
  updated_at = now()
from auth.users as auth_user
where auth_user.id = administrator.auth_user_id
  and auth_user.last_sign_in_at is not null
  and administrator.last_login is distinct from auth_user.last_sign_in_at;
