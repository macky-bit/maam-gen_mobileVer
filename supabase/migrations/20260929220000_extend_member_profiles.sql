alter table public.member_profile
  add column profile_name varchar(50) not null,
  add column avatar_image text,
  add column is_kids boolean not null default false,
  add column pin_hash text,
  add column display_order smallint not null default 1,
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now(),
  add constraint member_profile_name_not_blank
    check (btrim(profile_name) <> ''),
  add constraint member_profile_display_order_positive
    check (display_order > 0),
  add constraint member_profile_pin_hash_not_blank
    check (pin_hash is null or btrim(pin_hash) <> '');

create unique index member_profile_active_name_unique
  on public.member_profile (user_id, lower(btrim(profile_name)))
  where is_active;

create unique index member_profile_active_order_unique
  on public.member_profile (user_id, display_order)
  where is_active;

create or replace function public.set_member_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger set_member_profile_updated_at
before update on public.member_profile
for each row
execute function public.set_member_profile_updated_at();

comment on column public.member_profile.profile_name is
  'Viewer-facing profile name within the subscriber account.';
comment on column public.member_profile.avatar_image is
  'Avatar asset key or image URL selected for this viewing profile.';
comment on column public.member_profile.is_kids is
  'Whether the viewing profile should receive child-appropriate content.';
comment on column public.member_profile.pin_hash is
  'Optional secure hash of a profile PIN; never store the raw PIN.';
comment on column public.member_profile.display_order is
  'One-based position of the profile in the account profile picker.';
