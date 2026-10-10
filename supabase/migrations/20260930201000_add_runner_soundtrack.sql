alter table public.soundtrack
  add column if not exists track_title text,
  add column if not exists external_url text;

insert into public.soundtrack (
  content_id,
  song_title,
  track_title,
  external_url
)
select
  17,
  'Runner — Final Trailer Music',
  'Runner — Final Trailer Music',
  'https://www.youtube.com/watch?v=m8JUmBgHejI'
where not exists (
  select 1
  from public.soundtrack
  where content_id = 17
    and external_url = 'https://www.youtube.com/watch?v=m8JUmBgHejI'
);
