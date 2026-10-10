-- Clear the legacy catalog before importing the TMDB-backed catalog.
-- Existing foreign keys cascade this deletion to content-dependent rows.
-- Category and genre reference data are intentionally preserved.
delete from public.content;
