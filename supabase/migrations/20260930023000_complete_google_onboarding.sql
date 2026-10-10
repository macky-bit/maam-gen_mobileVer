create or replace function public.complete_my_google_onboarding(
  selected_birth_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_auth_user_id uuid := auth.uid();
begin
  if current_auth_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if selected_birth_date is null or selected_birth_date > current_date then
    raise exception 'A valid birthdate is required' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from auth.identities as identity
    where identity.user_id = current_auth_user_id
      and identity.provider = 'google'
  ) then
    raise exception 'Google authentication is required' using errcode = '42501';
  end if;

  update public."user" as account
  set date_of_birth = selected_birth_date,
      password = null
  where account.auth_user_id = current_auth_user_id;

  if not found then
    raise exception 'Application account does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.complete_my_google_onboarding(date)
  from public, anon;
grant execute on function public.complete_my_google_onboarding(date)
  to authenticated;

-- Password credentials belong only in auth.users. Remove any values manually
-- placed in the legacy application column for linked accounts.
update public."user"
set password = null
where auth_user_id is not null
  and password is not null;
