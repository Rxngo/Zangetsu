import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/tracker/tracker.dart';
import 'package:watch_app/core/tracker/tracker_hub.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/schedule/airing_service.dart';
import 'package:watch_app/core/schedule/coming_soon_service.dart';
import 'package:watch_app/core/schedule/schedule_models.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/features/schedule/schedule_cubit.dart';

class _FakeAiring implements AiringService {
  @override
  bool lastFailureOffline = false;

  _FakeAiring(this._out);
  final List<AiringEntry> _out;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<List<AiringEntry>> weekAiring({DateTime? now}) async => _out;
}

/// Returns empty for the first [emptyFirst] calls, then [_out] — models a
/// transient failure the retry loop should recover from.
class _FlakyAiring implements AiringService {
  @override
  bool lastFailureOffline = false;

  _FlakyAiring(this._out, this.emptyFirst);
  final List<AiringEntry> _out;
  int emptyFirst;
  int calls = 0;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<List<AiringEntry>> weekAiring({DateTime? now}) async =>
      calls++ < emptyFirst ? const [] : _out;
}

class _FakeSoon implements ComingSoonService {
  @override
  bool lastFailureOffline = false;

  _FakeSoon(this._out);
  final List<ComingSoonEntry> _out;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<List<ComingSoonEntry>> upcoming() async => _out;
}

class _FakeMyList implements MyListStore {
  _FakeMyList(this._items);
  final List<MediaItem> _items;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  List<MediaItem> all() => _items;
}

class _FakeTracker extends ChangeNotifier implements Tracker {
  _FakeTracker(this._items);

  final List<TrackerListItem> _items;
  int fetchCount = 0;

  @override
  String get displayName => 'AniList';
  @override
  bool get supportsReading => true;
  @override
  bool isConnected = true;
  @override
  Future<List<TrackerListItem>> fetchList() async {
    fetchCount++;
    return _items;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AiringEntry _entry(int? mal) => AiringEntry(
  malId: mal,
  title: 't$mal',
  coverUrl: null,
  episode: 1,
  airsAtLocal: DateTime(2026, 7, 10, 12),
  format: 'TV',
);

void main() {
  test(
    'load populates airing (grouped) + comingSoon, clears loading',
    () async {
      final c = ScheduleCubit(
        _FakeAiring([_entry(1), _entry(2)]),
        _FakeSoon([
          const ComingSoonEntry(
            tmdbId: 9,
            isTv: false,
            title: 'm',
            posterUrl: null,
            releaseDate: null,
          ),
        ]),
        _FakeMyList(const []),
      );
      await c.load();
      expect(c.state.airingAll.length, 2);
      expect(c.state.airingByDay.values.expand((x) => x).length, 2);
      expect(c.state.comingSoon.length, 1);
      expect(c.state.loadingAiring, isFalse);
      expect(c.state.loadingSoon, isFalse);
      expect(c.state.errorAiring, isFalse);
    },
  );

  test(
    'myListByDay narrows to My List malIds while airingByDay keeps all',
    () async {
      final c = ScheduleCubit(
        _FakeAiring([_entry(1), _entry(2), _entry(3)]),
        _FakeSoon(const []),
        _FakeMyList([
          const MediaItem(
            id: 'a',
            title: 'A',
            url: '/a',
            type: ProviderType.anime,
            sourceId: 's',
            malId: 2,
          ),
        ]),
        retryDelays: const [], // empty soon is intentional here — skip retries
      );
      await c.load();
      // My List tab shows only tracked anime…
      final mine = c.state.myListByDay.values.expand((x) => x).toList();
      expect(mine.map((e) => e.malId).toList(), [2]);
      // …while the Anime tab still shows everything.
      expect(c.state.airingByDay.values.expand((x) => x).length, 3);
    },
  );

  test('retries a transient empty airing result, then populates', () async {
    final c = ScheduleCubit(
      _FlakyAiring([_entry(1), _entry(2)], 2), // empty twice, then real
      _FakeSoon([
        const ComingSoonEntry(
          tmdbId: 9,
          isTv: false,
          title: 'm',
          posterUrl: null,
          releaseDate: null,
        ),
      ]),
      _FakeMyList(const []),
      retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    );
    await c.load();
    expect(c.state.airingAll.length, 2); // recovered after 2 empty tries
    expect(c.state.errorAiring, isFalse);
  });

  test('gives up after exhausting retries → errorAiring', () async {
    final c = ScheduleCubit(
      _FakeAiring(const []), // always empty
      _FakeSoon([
        const ComingSoonEntry(
          tmdbId: 9,
          isTv: false,
          title: 'm',
          posterUrl: null,
          releaseDate: null,
        ),
      ]),
      _FakeMyList(const []),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    await c.load();
    expect(c.state.airingAll, isEmpty);
    expect(c.state.errorAiring, isTrue);
    expect(c.state.loadingAiring, isFalse);
  });

  test(
    'tracker filter is lazy, cached, and leaves My List behavior intact',
    () async {
      final tracker = _FakeTracker([
        TrackerListItem(
          item: const MediaItem(
            id: 'mal:2',
            title: 'Tracked',
            url: '',
            type: ProviderType.anime,
            sourceId: '',
            malId: 2,
          ),
          status: WatchStatus.planning,
        ),
        TrackerListItem(
          item: const MediaItem(
            id: 'anime:no-mal-id',
            title: 't1',
            url: '',
            type: ProviderType.anime,
            sourceId: '',
          ),
          status: WatchStatus.watching,
        ),
        TrackerListItem(
          item: const MediaItem(
            id: 'manga:4',
            title: 'Not Anime',
            url: '',
            type: ProviderType.manga,
            sourceId: '',
            malId: 4,
          ),
          status: WatchStatus.planning,
        ),
      ]);
      final cubit = ScheduleCubit(
        _FakeAiring([_entry(1), _entry(2)]),
        _FakeSoon(const []),
        _FakeMyList([_item(1)]),
        trackerHub: TrackerHub([tracker]),
        retryDelays: const [],
      );

      expect(tracker.fetchCount, 0);
      expect(cubit.state.connectedTrackerNames, ['AniList']);
      await cubit.load();
      expect(tracker.fetchCount, 0); // opening/loading Schedule stays lazy
      await cubit.selectTrackerFilter('AniList');

      expect(tracker.fetchCount, 1);
      expect(cubit.state.activeFollowed!.matches(_entry(2)), isTrue);
      expect(cubit.state.activeFollowed!.matches(_entry(1)), isTrue);
      expect(cubit.state.activeFollowed!.matches(_entry(4)), isFalse);

      cubit.selectMyListFilter();
      expect(cubit.state.activeFollowed!.matches(_entry(1)), isTrue);
      expect(cubit.state.activeFollowed!.matches(_entry(2)), isFalse);
      await cubit.selectTrackerFilter('AniList');
      expect(tracker.fetchCount, 1); // cached for this schedule session

      tracker.isConnected = false;
      tracker.notifyListeners();
      expect(cubit.state.connectedTrackerNames, isEmpty);
      expect(cubit.state.trackerFilterName, isNull);

      await cubit.close();
      tracker.dispose();
    },
  );
}

MediaItem _item(int malId) => MediaItem(
  id: 'local:$malId',
  title: 'Local $malId',
  url: '',
  type: ProviderType.anime,
  sourceId: '',
  malId: malId,
);
