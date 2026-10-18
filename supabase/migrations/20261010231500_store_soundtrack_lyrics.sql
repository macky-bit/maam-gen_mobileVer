ALTER TABLE public.soundtrack
  ADD COLUMN IF NOT EXISTS synced_lyrics text,
  ADD COLUMN IF NOT EXISTS lyrics_storage_path text,
  ADD COLUMN IF NOT EXISTS synced_lyrics_storage_path text,
  ADD COLUMN IF NOT EXISTS lyrics_source_id bigint,
  ADD COLUMN IF NOT EXISTS lyrics_source_url text,
  ADD COLUMN IF NOT EXISTS lyrics_instrumental boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lyrics_updated_at timestamptz;
ALTER TABLE public.soundtrack
  DROP CONSTRAINT IF EXISTS soundtrack_lyrics_source_id_positive;
ALTER TABLE public.soundtrack
  ADD CONSTRAINT soundtrack_lyrics_source_id_positive
  CHECK (lyrics_source_id IS NULL OR lyrics_source_id > 0);
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'soundtrack-lyrics',
  'soundtrack-lyrics',
  false,
  524288,
  ARRAY['text/plain']
)
ON CONFLICT (id) DO UPDATE
SET public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
DROP POLICY IF EXISTS soundtrack_lyrics_authenticated_read ON storage.objects;
CREATE POLICY soundtrack_lyrics_authenticated_read
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'soundtrack-lyrics');
DROP POLICY IF EXISTS soundtrack_lyrics_admin_insert ON storage.objects;
CREATE POLICY soundtrack_lyrics_admin_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'soundtrack-lyrics'
  AND public.is_any_admin()
);
DROP POLICY IF EXISTS soundtrack_lyrics_admin_update ON storage.objects;
CREATE POLICY soundtrack_lyrics_admin_update
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'soundtrack-lyrics'
  AND public.is_any_admin()
)
WITH CHECK (
  bucket_id = 'soundtrack-lyrics'
  AND public.is_any_admin()
);
DROP POLICY IF EXISTS soundtrack_lyrics_admin_delete ON storage.objects;
CREATE POLICY soundtrack_lyrics_admin_delete
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'soundtrack-lyrics'
  AND public.is_any_admin()
);
