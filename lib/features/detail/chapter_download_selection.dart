import '../../core/models/episode.dart';

/// Selects up to [count] queueable chapters from [startIndex] forward.
///
/// The index is the reader's resume target: an unfinished chapter is included,
/// while a finished chapter is expected to have already advanced via
/// `adjacentChapterIndex`. Downloaded or already queued chapters are skipped
/// without consuming the requested count.
List<Episode> selectNextChapterDownloads({
  required List<Episode> chapters,
  required int startIndex,
  required int count,
  Set<String> unavailableUrls = const {},
}) {
  if (chapters.isEmpty ||
      startIndex < 0 ||
      startIndex >= chapters.length ||
      count <= 0) {
    return const [];
  }

  final selected = <Episode>[];
  final seenUrls = <String>{};
  for (
    var i = startIndex;
    i < chapters.length && selected.length < count;
    i++
  ) {
    final chapter = chapters[i];
    if (unavailableUrls.contains(chapter.url) || !seenUrls.add(chapter.url)) {
      continue;
    }
    selected.add(chapter);
  }
  return selected;
}

/// Selects an inclusive chapter-row range, skipping already unavailable rows.
///
/// Indexes, rather than chapter numbers, keep scanlation releases with the same
/// number distinguishable and preserve the provider's order.
List<Episode> selectChapterDownloadRange({
  required List<Episode> chapters,
  required int fromIndex,
  required int toIndex,
  Set<String> unavailableUrls = const {},
}) {
  if (fromIndex < 0 || toIndex < fromIndex || toIndex >= chapters.length) {
    return const [];
  }

  final selected = <Episode>[];
  final seenUrls = <String>{};
  for (var i = fromIndex; i <= toIndex; i++) {
    final chapter = chapters[i];
    if (unavailableUrls.contains(chapter.url) || !seenUrls.add(chapter.url)) {
      continue;
    }
    selected.add(chapter);
  }
  return selected;
}

/// Replaces [selectedIds] for one season with the inclusive range of indexes.
///
/// IDs from other seasons are retained. Invalid indexes return an unchanged
/// copy, so callers can safely apply a picker result without clearing an
/// existing selection accidentally.
Set<String> replaceSeasonSelectionWithRange({
  required Set<String> selectedIds,
  required List<Episode> seasonEpisodes,
  required int fromIndex,
  required int toIndex,
}) {
  if (fromIndex < 0 ||
      toIndex < fromIndex ||
      toIndex >= seasonEpisodes.length) {
    return {...selectedIds};
  }

  final updated = {...selectedIds}
    ..removeAll(seasonEpisodes.map((episode) => episode.id));
  updated.addAll(
    seasonEpisodes.sublist(fromIndex, toIndex + 1).map((episode) => episode.id),
  );
  return updated;
}

/// Maps the reading resume target into the currently filtered chapter list.
///
/// Exact URL/id matches win. If the user has filtered to a different
/// scanlation group, start at its first chapter number at or beyond the resume
/// number. The provider's original ordering remains authoritative.
int resolveChapterDownloadStartIndex({
  required List<Episode> chapters,
  required String? resumeChapterId,
  required String? resumeChapterUrl,
  required double? resumeChapterNumber,
}) {
  if (chapters.isEmpty) return 0;

  var index = chapters.indexWhere(
    (chapter) =>
        (resumeChapterId != null && chapter.id == resumeChapterId) ||
        (resumeChapterUrl != null && chapter.url == resumeChapterUrl),
  );
  if (index >= 0) return index;

  final number = resumeChapterNumber;
  if (number != null) {
    index = chapters.indexWhere(
      (chapter) => chapter.number != null && chapter.number! >= number,
    );
    if (index >= 0) return index;
  }
  return 0;
}
