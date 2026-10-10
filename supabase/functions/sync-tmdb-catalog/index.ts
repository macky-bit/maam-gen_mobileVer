import { createClient } from "npm:@supabase/supabase-js@2";

const tmdbBaseUrl = "https://api.themoviedb.org/3";
const imageBaseUrl = "https://image.tmdb.org/t/p/w500";

const genreMap: Record<number, number> = {
  28: 9,
  12: 3,
  16: 12,
  35: 6,
  80: 13,
  18: 1,
  10751: 14,
  14: 11,
  36: 4,
  27: 10,
  9648: 7,
  10749: 5,
  878: 8,
  53: 2,
  10759: 9,
  10762: 14,
  10765: 8,
  10766: 1,
  10768: 4,
};

type MediaType = "movie" | "tv";

type PopularItem = {
  id: number;
  title?: string;
  name?: string;
  overview?: string;
  release_date?: string;
  first_air_date?: string;
  poster_path?: string | null;
};

type CatalogRow = {
  category_id: number;
  genre_id: number | null;
  title: string;
  synopsis: string;
  release_year: number | null;
  runtime: number | null;
  age_rating: string;
  thumbnail: string;
  video_file: null;
  subtitle: null;
  total_streams_count: number;
  availability_status: string;
  tmdb_id: number;
  popularity_rank: number;
  catalog_source: string;
  synced_at: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function yearFrom(value?: string) {
  if (!value || value.length < 4) return null;
  const year = Number(value.slice(0, 4));
  return Number.isInteger(year) ? year : null;
}

function movieCertification(detail: Record<string, unknown>) {
  const releaseDates = detail.release_dates as
    | {
        results?: Array<{
          iso_3166_1?: string;
          release_dates?: Array<{ certification?: string }>;
        }>;
      }
    | undefined;
  const countries = releaseDates?.results ?? [];
  for (const code of ["PH", "US"]) {
    const country = countries.find((entry) => entry.iso_3166_1 === code);
    const rating = country?.release_dates?.find(
      (entry) => entry.certification?.trim(),
    )?.certification;
    if (rating) return rating.trim().slice(0, 20);
  }
  return "NR";
}

function tvCertification(detail: Record<string, unknown>) {
  const ratings = detail.content_ratings as
    | { results?: Array<{ iso_3166_1?: string; rating?: string }> }
    | undefined;
  const countries = ratings?.results ?? [];
  for (const code of ["PH", "US"]) {
    const rating = countries.find((entry) => entry.iso_3166_1 === code)?.rating;
    if (rating?.trim()) return rating.trim().slice(0, 20);
  }
  return "NR";
}

async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  mapper: (value: T, index: number) => Promise<R>,
) {
  const results = new Array<R>(values.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex++;
      results[index] = await mapper(values[index], index);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(concurrency, values.length) }, worker),
  );
  return results;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const expectedSecret = Deno.env.get("SYNC_SECRET");
  if (!expectedSecret || request.headers.get("x-sync-secret") !== expectedSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const tmdbApiKey = Deno.env.get("TMDB_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!tmdbApiKey || !supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Required server configuration is missing" }, 500);
  }

  try {
    const payload = await request.json().catch(() => ({}));
    const dryRun = payload?.dry_run === true;
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: categories, error: categoryError } = await supabase
      .from("category")
      .select("category_id, category_name")
      .in("category_name", ["Movie", "TV Series"]);
    if (categoryError) throw categoryError;

    const movieCategory = categories?.find(
      (category) => category.category_name === "Movie",
    )?.category_id;
    const tvCategory = categories?.find(
      (category) => category.category_name === "TV Series",
    )?.category_id;
    if (!movieCategory || !tvCategory) {
      throw new Error("Movie and TV Series categories are required");
    }

    async function tmdb(path: string, params: Record<string, string> = {}) {
      const url = new URL(`${tmdbBaseUrl}${path}`);
      url.searchParams.set("api_key", tmdbApiKey!);
      url.searchParams.set("language", "en-US");
      for (const [name, value] of Object.entries(params)) {
        url.searchParams.set(name, value);
      }
      const response = await fetch(url, {
        headers: { accept: "application/json" },
      });
      if (!response.ok) {
        throw new Error(`TMDB ${path} failed with ${response.status}`);
      }
      return await response.json() as Record<string, unknown>;
    }

    async function popular(mediaType: MediaType) {
      const pages = await Promise.all(
        [1, 2, 3, 4].map((page) =>
          tmdb(`/${mediaType}/popular`, { page: String(page) })
        ),
      );
      const candidates = pages.flatMap(
        (page) => (page.results as PopularItem[] | undefined) ?? [],
      );
      const uniqueItems: PopularItem[] = [];
      const seenIds = new Set<number>();
      for (const item of candidates) {
        if (seenIds.has(item.id)) continue;
        seenIds.add(item.id);
        uniqueItems.push(item);
        if (uniqueItems.length === 50) break;
      }
      return uniqueItems;
    }

    async function enrich(
      item: PopularItem,
      rank: number,
      mediaType: MediaType,
      categoryId: number,
      syncedAt: string,
    ): Promise<CatalogRow> {
      const detail = await tmdb(`/${mediaType}/${item.id}`, {
        append_to_response: mediaType === "movie"
          ? "release_dates"
          : "content_ratings",
      });
      const genres = (detail.genres as Array<{ id: number }> | undefined) ?? [];
      const mappedGenre = genres
        .map((genre) => genreMap[genre.id])
        .find((genreId) => genreId != null) ?? null;
      const episodeRunTimes = detail.episode_run_time as number[] | undefined;
      const lastEpisode = detail.last_episode_to_air as
        | { runtime?: number | null }
        | undefined;
      const runtime = mediaType === "movie"
        ? (detail.runtime as number | null | undefined) ?? null
        : episodeRunTimes?.find((minutes) => minutes > 0) ??
          lastEpisode?.runtime ?? null;
      const posterPath = (detail.poster_path ?? item.poster_path) as
        | string
        | null
        | undefined;
      const title = String(
        mediaType === "movie"
          ? detail.title ?? item.title ?? "Untitled"
          : detail.name ?? item.name ?? "Untitled",
      ).slice(0, 255);
      const releaseDate = String(
        mediaType === "movie"
          ? detail.release_date ?? item.release_date ?? ""
          : detail.first_air_date ?? item.first_air_date ?? "",
      );

      return {
        category_id: categoryId,
        genre_id: mappedGenre,
        title,
        synopsis: String(detail.overview ?? item.overview ?? ""),
        release_year: yearFrom(releaseDate),
        runtime: runtime && runtime > 0 ? Math.round(runtime) : null,
        age_rating: mediaType === "movie"
          ? movieCertification(detail)
          : tvCertification(detail),
        thumbnail: posterPath ? `${imageBaseUrl}${posterPath}` : "",
        video_file: null,
        subtitle: null,
        total_streams_count: 0,
        availability_status: "available",
        tmdb_id: item.id,
        popularity_rank: rank + 1,
        catalog_source: "tmdb",
        synced_at: syncedAt,
      };
    }

    const [movies, series] = await Promise.all([popular("movie"), popular("tv")]);
    if (movies.length !== 50 || series.length !== 50) {
      throw new Error("TMDB did not return exactly 50 movies and 50 series");
    }

    const syncedAt = new Date().toISOString();
    const [movieRows, seriesRows] = await Promise.all([
      mapWithConcurrency(movies, 5, (item, rank) =>
        enrich(item, rank, "movie", movieCategory, syncedAt)
      ),
      mapWithConcurrency(series, 5, (item, rank) =>
        enrich(item, rank, "tv", tvCategory, syncedAt)
      ),
    ]);
    const rows = [...movieRows, ...seriesRows];

    const validation = {
      movies: movieRows.length,
      series: seriesRows.length,
      missing_runtime: rows.filter((row) => row.runtime == null).length,
      unrated: rows.filter((row) => row.age_rating === "NR").length,
      missing_thumbnail: rows.filter((row) => !row.thumbnail).length,
      missing_release_year: rows.filter((row) => row.release_year == null).length,
    };
    if (dryRun) {
      return jsonResponse({ dry_run: true, validation });
    }

    const { error: upsertError } = await supabase
      .from("content")
      .upsert(rows, { onConflict: "category_id,tmdb_id" });
    if (upsertError) throw upsertError;

    for (const [categoryId, mediaRows] of [
      [movieCategory, movieRows],
      [tvCategory, seriesRows],
    ] as const) {
      const ids = mediaRows.map((row) => row.tmdb_id).join(",");
      const { error: staleError } = await supabase
        .from("content")
        .delete()
        .eq("catalog_source", "tmdb")
        .eq("category_id", categoryId)
        .not("tmdb_id", "in", `(${ids})`);
      if (staleError) throw staleError;
    }

    return jsonResponse({ imported: rows.length, validation, synced_at: syncedAt });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error
      ? error.message
      : typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : "Catalog sync failed";
    return jsonResponse(
      { error: message },
      500,
    );
  }
});
