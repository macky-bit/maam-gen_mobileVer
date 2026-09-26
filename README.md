# StreamFlix Mobile

A Flutter mobile adaptation of the StreamFlix web design. The app keeps the
violet, gold, and deep-ink visual language while replacing desktop navigation
with a phone-first bottom navigation experience.

## Included

- Sign-in and registration presentation
- Home, movies, TV shows, search, and My List experiences
- Live TMDB catalog data and artwork
- Responsive title details and player presentation
- Profile, account, subscription, preferences, and support presentation

The web project's admin area is intentionally not included. There are no admin
routes, screens, imports, or assets in this Flutter application.

## Run

Pass either a TMDB API key or read-access token at build time:

```powershell
flutter run --dart-define=TMDB_API_KEY=your_key
```

or:

```powershell
flutter run --dart-define=TMDB_READ_ACCESS_TOKEN=your_token
```

Without credentials, the application still opens and shows a setup message in
place of the catalog.
