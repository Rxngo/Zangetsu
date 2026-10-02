import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/features/detail/chapter_download_selection.dart';

void main() {
  final chapters = List.generate(
    20,
    (i) => Episode(
      id: 'chapter-${i + 1}',
      title: 'Chapter ${i + 1}',
      number: (i + 1).toDouble(),
      url: '/chapter-${i + 1}',
    ),
  );

  group('selectNextChapterDownloads', () {
    test(
      'starts at the unfinished resume chapter and selects the next count',
      () {
        final selected = selectNextChapterDownloads(
          chapters: chapters,
          startIndex: 3,
          count: 10,
        );

        expect(selected, chapters.sublist(3, 13));
      },
    );

    test('includes an unfinished resume chapter', () {
      final selected = selectNextChapterDownloads(
        chapters: chapters,
        startIndex: 2,
        count: 3,
      );

      expect(selected, chapters.sublist(2, 5));
    });

    test('skips unavailable chapters and fills the requested count', () {
      final selected = selectNextChapterDownloads(
        chapters: chapters,
        startIndex: 3,
        count: 4,
        unavailableUrls: const {'/chapter-4', '/chapter-6'},
      );

      expect(selected, [chapters[4], chapters[6], chapters[7], chapters[8]]);
    });

    test('does not wrap or return more than the remaining chapters', () {
      final selected = selectNextChapterDownloads(
        chapters: chapters,
        startIndex: 18,
        count: 10,
      );

      expect(selected, chapters.sublist(18));
    });
  });

  group('selectChapterDownloadRange', () {
    test('uses inclusive exact row indexes and skips unavailable chapters', () {
      final selected = selectChapterDownloadRange(
        chapters: chapters,
        fromIndex: 3,
        toIndex: 7,
        unavailableUrls: const {'/chapter-5'},
      );

      expect(selected, [chapters[3], chapters[5], chapters[6], chapters[7]]);
    });

    test('returns an empty list for an invalid or reversed range', () {
      expect(
        selectChapterDownloadRange(
          chapters: chapters,
          fromIndex: 7,
          toIndex: 3,
        ),
        isEmpty,
      );
      expect(
        selectChapterDownloadRange(
          chapters: chapters,
          fromIndex: -1,
          toIndex: 3,
        ),
        isEmpty,
      );
    });
  });

  group('replaceSeasonSelectionWithRange', () {
    test('replaces only this season with the inclusive selected range', () {
      final selected = replaceSeasonSelectionWithRange(
        selectedIds: {'chapter-1', 'chapter-3', 'other-season-1'},
        seasonEpisodes: chapters.take(5).toList(),
        fromIndex: 1,
        toIndex: 3,
      );

      expect(selected, {
        'chapter-2',
        'chapter-3',
        'chapter-4',
        'other-season-1',
      });
    });

    test('does not modify the selection for an invalid range', () {
      final existing = {'chapter-1', 'other-season-1'};

      expect(
        replaceSeasonSelectionWithRange(
          selectedIds: existing,
          seasonEpisodes: chapters.take(5).toList(),
          fromIndex: 4,
          toIndex: 2,
        ),
        existing,
      );
      expect(existing, {'chapter-1', 'other-season-1'});
    });
  });

  test(
    'resolves a resume chapter in a filtered list by its chapter number',
    () {
      final filtered = [chapters[0], chapters[2], chapters[4], chapters[6]];
      expect(
        resolveChapterDownloadStartIndex(
          chapters: filtered,
          resumeChapterId: 'chapter-4',
          resumeChapterUrl: '/chapter-4',
          resumeChapterNumber: 4,
        ),
        2,
      );
    },
  );
}
