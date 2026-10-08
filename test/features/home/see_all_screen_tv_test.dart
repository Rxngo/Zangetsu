import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';
import 'package:watch_app/core/zmode/zmode_ids.dart';
import 'package:watch_app/features/home/see_all_screen_tv.dart';
import 'package:watch_app/l10n/app_localizations.dart';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const item1 = MediaItem(
    id: '1',
    title: 'Attack on Titan',
    url: '/aot',
    type: ProviderType.anime,
    sourceId: 'test',
  );
  const item2 = MediaItem(
    id: '2',
    title: 'Demon Slayer',
    url: '/ds',
    type: ProviderType.anime,
    sourceId: 'test',
  );

  testWidgets(
    'SeeAllScreenTv renders poster cards and first card has autofocus',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SeeAllScreenTv(
            title: 'Top Anime',
            items: const [item1, item2],
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title is visible in the app bar.
      expect(find.text('Top Anime'), findsOneWidget);

      // Both poster titles are rendered as poster cards.
      expect(find.text('Attack on Titan'), findsOneWidget);
      expect(find.text('Demon Slayer'), findsOneWidget);

      // At least 2 TvFocusable cards are present.
      final focusables = tester
          .widgetList<TvFocusable>(find.byType(TvFocusable))
          .toList();
      expect(focusables.length, greaterThanOrEqualTo(2));

      // The very first poster has autofocus (Back in the app bar does not).
      final focused = tester
          .widgetList<TvFocusable>(find.byType(TvFocusable))
          .where((w) => w.autofocus);
      expect(focused, isNotEmpty);
    },
  );

  testWidgets('SeeAllScreenTv calls onTap with the correct item on OK-key', (
    tester,
  ) async {
    MediaItem? tapped;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SeeAllScreenTv(
          title: 'Top Anime',
          items: const [item1, item2],
          onTap: (item) => tapped = item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger onTap on the autofocused poster (not the Back control).
    final poster = tester
        .widgetList<TvFocusable>(find.byType(TvFocusable))
        .firstWhere((w) => w.autofocus);
    poster.onTap();

    expect(tapped, equals(item1));
  });

  testWidgets('searchable service grid opens search and runs its query', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SeeAllScreenTv(
          title: 'Netflix',
          items: const [item1],
          onTap: (_) {},
          filterKind: ZKind.movie,
          onSearch: (query, filters, page) async {
            queries.add(query);
            return const MediaItemPage(items: [item2], hasMore: false);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tv-see-all-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-see-all-filter')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-see-all-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tv-see-all-search-field')),
      'Dune',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(queries, ['Dune']);

    await tester.tap(find.byKey(const ValueKey('tv-see-all-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-meta-filter-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-meta-filter-status')), findsNothing);
  });

  testWidgets('TV service search can advance past an empty result page', (
    tester,
  ) async {
    final requestedPages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SeeAllScreenTv(
          title: 'Netflix',
          items: const [item1],
          onTap: (_) {},
          filterKind: ZKind.movie,
          onSearch: (query, filters, page) async {
            requestedPages.add(page);
            return page == 1
                ? const MediaItemPage(items: [], hasMore: true)
                : const MediaItemPage(items: [item2], hasMore: false);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tv-see-all-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tv-see-all-search-field')),
      'Dune',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(requestedPages, [1]);
    expect(find.byKey(const ValueKey('tv-see-all-next-page')), findsOneWidget);
    tester
        .widget<TvFocusable>(find.byKey(const ValueKey('tv-see-all-next-page')))
        .onTap();
    await tester.pumpAndSettle();

    expect(requestedPages, [1, 2]);
    expect(find.text('Demon Slayer'), findsOneWidget);
  });
}
