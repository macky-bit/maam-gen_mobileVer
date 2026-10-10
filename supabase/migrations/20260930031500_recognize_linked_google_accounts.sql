create or replace function public.get_my_google_onboarding_state()
returns table (
  requires_onboarding boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      exists (
        select 1
        from auth.identities as identity
        where identity.user_id = auth_account.id
          and identity.provider = 'google'
      )
      or coalesce(auth_account.raw_app_meta_data ->> 'provider', '') = 'google'
      or coalesce(
        auth_account.raw_app_meta_data -> 'providers',
        '[]'::jsonb
      ) ? 'google'
    )
    and (
      coalesce(
        (auth_account.raw_user_meta_data
          ->> 'streamflix_onboarding_complete')::boolean,
        false
      ) = false
      or app_account.date_of_birth is null
      or coalesce(auth_account.encrypted_password, '') = ''
    )
  from auth.users as auth_account
  left join public."user" as app_account
    on app_account.auth_user_id = auth_account.id
  where auth_account.id = (select auth.uid())
  limit 1;
$$;
