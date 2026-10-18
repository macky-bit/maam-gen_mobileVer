import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/show.dart';
import 'package:stream_flix/screens/catalog_screen.dart';
import 'package:stream_flix/theme/app_theme.dart';
import 'package:stream_flix/widgets/show_card.dart';

void main() {
  testWidgets('only explicitly ranked rows display rank numbers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shows = [_show(1, 'Trending title'), _show(2, 'Top series')];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CatalogScreen(
            catalog: Future.value(
              CatalogData(
                featured: null,
                rows: [
                  CatalogRow('Trending Now', [shows.first]),
                  CatalogRow('Top 10 TV Shows', [shows.last], ranked: true),
                ],
              ),
            ),
            onSelect: (_) {},
            onRefresh: () async {},
            continueWatching: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    final cards = tester
        .widgetList<ShowCard>(find.byType(ShowCard))
        .toList(growable: false);
    expect(cards, hasLength(2));
    expect(cards.first.rank, isNull);
    expect(cards.last.rank, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('database genre chips filter catalog rows', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final drama = _show(1, 'Drama title', genres: const ['Drama']);
    final comedy = _show(2, 'Comedy title', genres: const ['Comedy']);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CatalogScreen(
            catalog: Future.value(
              CatalogData(
                featured: null,
                rows: [
                  CatalogRow('Popular Movies', [drama, comedy]),
                ],
                genres: const ['Drama', 'Comedy'],
              ),
            ),
            onSelect: (_) {},
            onRefresh: () async {},
            continueWatching: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShowCard), findsNWidgets(2));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Comedy'));
    await tester.pump();

    expect(find.byType(ShowCard), findsOneWidget);
    expect(find.text('Comedy title'), findsOneWidget);
    expect(find.text('Drama title'), findsNothing);
  });
}

Show _show(int id, String title, {List<String> genres = const []}) => Show(
  id: id,
  title: title,
  overview: 'A catalog title.',
  posterPath: '',
  backdropPath: '',
  year: '2026',
  score: 84,
  mediaType: 'movie',
  genreIds: const [28],
  genreNames: genres,
);
