WITH dashboard_titles AS (
  SELECT
    content.content_id,
    category.category_name,
    row_number() OVER (
      PARTITION BY category.category_name
      ORDER BY content.popularity_rank ASC NULLS LAST, content.content_id ASC
    ) AS dashboard_position
  FROM public.content
  JOIN public.category
    ON category.category_id = content.category_id
  WHERE content.availability_status = 'available'
    AND content.tmdb_id IS NOT NULL
    AND category.category_name IN ('Movie', 'TV Series')
), seeded_counts (category_name, dashboard_position, stream_count) AS (
  VALUES
    ('Movie', 1, 12486230::bigint),
    ('Movie', 2, 10928417::bigint),
    ('Movie', 3, 9475221::bigint),
    ('Movie', 4, 8934176::bigint),
    ('Movie', 5, 7842901::bigint),
    ('Movie', 6, 6901552::bigint),
    ('Movie', 7, 6340118::bigint),
    ('Movie', 8, 5827693::bigint),
    ('Movie', 9, 5441320::bigint),
    ('Movie', 10, 4980441::bigint),
    ('TV Series', 1, 11984220::bigint),
    ('TV Series', 2, 10310005::bigint),
    ('TV Series', 3, 9194500::bigint),
    ('TV Series', 4, 8562910::bigint),
    ('TV Series', 5, 7604820::bigint),
    ('TV Series', 6, 6812990::bigint),
    ('TV Series', 7, 6218030::bigint),
    ('TV Series', 8, 5682700::bigint),
    ('TV Series', 9, 5211140::bigint),
    ('TV Series', 10, 4759290::bigint)
)
UPDATE public.content
SET total_streams_count = seeded_counts.stream_count
FROM dashboard_titles
JOIN seeded_counts
  ON seeded_counts.category_name = dashboard_titles.category_name
 AND seeded_counts.dashboard_position = dashboard_titles.dashboard_position
WHERE content.content_id = dashboard_titles.content_id;
