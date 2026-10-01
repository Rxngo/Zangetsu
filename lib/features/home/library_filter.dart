import 'dart:math';

import '../../core/models/watch_status.dart';
import 'cubit/my_list_cubit.dart';

/// Picks one entry from the already-filtered library view, or null when it is
/// empty. The optional [random] keeps the choice deterministic in tests.
T? pickRandomLibraryEntry<T>(List<T> entries, {Random? random}) {
  if (entries.isEmpty) return null;
  return entries[(random ?? Random()).nextInt(entries.length)];
}

/// Fixed tab order matching the phone My List screen.
const libraryStatusTabOrder = [
  WatchStatus.watching,
  WatchStatus.planning,
  WatchStatus.completed,
  WatchStatus.paused,
  WatchStatus.dropped,
];

/// Statuses that actually have at least one entry, in [libraryStatusTabOrder].
List<WatchStatus> presentLibraryStatuses(List<MyListEntry> entries) =>
    libraryStatusTabOrder
        .where((s) => entries.any((e) => e.status == s))
        .toList();

/// Filter a library list the same way the phone tabs do.
List<MyListEntry> filterLibraryEntries(
  List<MyListEntry> entries, {
  WatchStatus? status,
  String? customList,
  bool Function(MyListEntry)? inCategory,
}) {
  return [
    for (final e in entries)
      if ((status == null || e.status == status) &&
          (customList == null || e.customLists.contains(customList)) &&
          (inCategory == null || inCategory(e)))
        e,
  ];
}
