alter table public.backup_job
  add column if not exists dataset_key varchar(50),
  add column if not exists table_names text[] not null default '{}'::text[],
  add column if not exists file_count integer not null default 0,
  add column if not exists error_message text;
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'database-backups',
  'database-backups',
  false,
  52428800,
  array['text/csv', 'application/json']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'system_admin_read_database_backups'
  ) then
    create policy system_admin_read_database_backups
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'database-backups'
        and public.is_admin_role('systemManager')
      );
  end if;
end
$$;
comment on column public.backup_job.dataset_key is
  'Stable identifier for the selected CSV backup dataset.';
comment on column public.backup_job.table_names is
  'Public-schema tables exported as individual CSV files.';
comment on column public.backup_job.storage_path is
  'Private database-backups bucket folder containing the CSV files.';
