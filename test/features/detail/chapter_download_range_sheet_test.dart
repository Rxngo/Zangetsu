import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/theme/app_colors.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/features/detail/chapter_download_range_sheet.dart';
import 'package:watch_app/l10n/app_localizations.dart';

void main() {
  testWidgets('start can move past the preset end and extend the range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = List.generate(
      100,
      (i) => Episode(
        id: 'c${i + 1}',
        title: 'Chapter ${i + 1}',
        number: (i + 1).toDouble(),
        url: '/c${i + 1}',
      ),
    );
    final result = <({int from, int to})?>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result.add(
                  await showModalBottomSheet<({int from, int to})>(
                    context: context,
                    builder: (_) => ChapterDownloadRangeSheet(
                      chapters: episodes,
                      initialFromIndex: 0,
                      initialToIndex: 9,
                      unavailableUrls: const {},
                    ),
                  ),
                );
              },
              child: const Text('Open range sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open range sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Find chapter'), findsOneWidget);
    final searchDecoration = tester.widget<TextField>(find.byType(TextField));
    expect(searchDecoration.decoration!.filled, isTrue);
    expect(searchDecoration.decoration!.fillColor, AppColors.surface2);
    await tester.enterText(find.byType(TextField), 'Chapter 50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ch. 50 · Chapter 50'));
    await tester.pumpAndSettle();

    // Both endpoints become Chapter 50 when Start moves past the old End.
    expect(find.text('Ch. 50 · Chapter 50'), findsNWidgets(2));
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Chapter 70');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ch. 70 · Chapter 70'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(result, [(from: 49, to: 69)]);
  });

  testWidgets('custom range returns the selected inclusive chapter indexes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = List.generate(
      12,
      (i) => Episode(
        id: 'c${i + 1}',
        title: 'Chapter ${i + 1}',
        number: (i + 1).toDouble(),
        url: '/c${i + 1}',
      ),
    );
    final result = <({int from, int to})?>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result.add(
                  await showModalBottomSheet<({int from, int to})>(
                    context: context,
                    builder: (_) => ChapterDownloadRangeSheet(
                      chapters: episodes,
                      initialFromIndex: 3,
                      initialToIndex: 10,
                      unavailableUrls: const {},
                    ),
                  ),
                );
              },
              child: const Text('Open range sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open range sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chapter 8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(result, [(from: 3, to: 7)]);
  });

  testWidgets('episode range uses episode wording in its searchable picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final episodes = List.generate(
      12,
      (i) => Episode(
        id: 'e${i + 1}',
        title: 'Episode ${i + 1}',
        number: (i + 1).toDouble(),
        url: '/e${i + 1}',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => ChapterDownloadRangeSheet(
                  chapters: episodes,
                  initialFromIndex: 0,
                  initialToIndex: 9,
                  unavailableUrls: const {},
                  isChapter: false,
                ),
              ),
              child: const Text('Open episode range'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open episode range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Find episode'), findsOneWidget);
    expect(find.text('E1 · Episode 1'), findsWidgets);
  });
}
