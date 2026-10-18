insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'feedback-attachments',
  'feedback-attachments',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists user_can_insert_own_feedback on public.platform_feedback;
create policy user_can_insert_own_feedback
on public.platform_feedback for insert to authenticated
with check (
  user_id in (
    select app_user.user_id from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists feedback_owner_upload_attachments on storage.objects;
create policy feedback_owner_upload_attachments
on storage.objects for insert to authenticated
with check (
  bucket_id = 'feedback-attachments'
  and (storage.foldername(name))[1] in (
    select app_user.user_id::text from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists feedback_owner_delete_attachments on storage.objects;
create policy feedback_owner_delete_attachments
on storage.objects for delete to authenticated
using (
  bucket_id = 'feedback-attachments'
  and (storage.foldername(name))[1] in (
    select app_user.user_id::text from public."user" app_user
    where app_user.auth_user_id = (select auth.uid())
  )
);
drop policy if exists feedback_attachment_admin_read on storage.objects;
create policy feedback_attachment_admin_read
on storage.objects for select to authenticated
using (
  bucket_id = 'feedback-attachments'
  and (
    public.is_admin_role('feedbackManager'::character varying)
    or public.is_master_admin()
  )
);
