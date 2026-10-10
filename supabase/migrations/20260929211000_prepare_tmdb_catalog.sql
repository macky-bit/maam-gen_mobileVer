-- Technical fields required to reference and refresh TMDB catalog records.
alter table public.content
  add column tmdb_id bigint,
  add column popularity_rank integer,
  add column catalog_source varchar(20) not null default 'manual',
  add column synced_at timestamptz;

alter table public.content
  add constraint content_tmdb_reference_unique
    unique (category_id, tmdb_id),
  add constraint content_popularity_rank_check
    check (popularity_rank is null or popularity_rank between 1 and 50),
  add constraint content_catalog_source_check
    check (catalog_source in ('manual', 'tmdb'));

create index content_category_rank_idx
  on public.content (category_id, popularity_rank)
  where availability_status = 'available';

comment on column public.content.tmdb_id is
  'Permanent external identifier supplied by The Movie Database.';
comment on column public.content.popularity_rank is
  'Current rank within the imported top-50 movie or TV catalog.';
comment on column public.content.catalog_source is
  'Origin of the catalog record. TMDB imports use tmdb.';
