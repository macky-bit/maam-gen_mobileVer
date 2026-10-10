do $$
begin
  if (select count(*) from public.content) <> 100 then
    raise exception 'Expected exactly 100 content rows before renumbering';
  end if;

  if exists (select 1 from public.content_comment)
    or exists (select 1 from public.previous_film_refresher)
    or exists (select 1 from public.reaction)
    or exists (select 1 from public.soundtrack)
    or exists (select 1 from public.watch_history) then
    raise exception 'Content-dependent rows must be empty before renumbering';
  end if;
end;
$$;

with ordered_content as (
  select
    content_id,
    row_number() over (
      order by category_id, popularity_rank, tmdb_id
    )::bigint as new_content_id
  from public.content
)
update public.content as content
set content_id = ordered.new_content_id
from ordered_content as ordered
where content.content_id = ordered.content_id;

select setval(
  pg_get_serial_sequence('public.content', 'content_id'),
  (select max(content_id) from public.content),
  true
);
