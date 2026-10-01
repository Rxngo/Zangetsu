import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/core/schedule/airing_service.dart';
import 'package:watch_app/core/schedule/coming_soon_service.dart';
import 'package:watch_app/core/schedule/schedule_models.dart';
import 'package:watch_app/core/tracker/tracker.dart';
import 'package:watch_app/core/tracker/tracker_hub.dart';
import 'package:watch_app/features/schedule/schedule_cubit.dart';
import 'package:watch_app/features/schedule/schedule_screen.dart';
import 'package:watch_app/l10n/app_localizations.dart';

// A cubit we can seed with a fixed state, so no services/sl needed.
class _StubCubit extends ScheduleCubit {
  _StubCubit(
    super.a,
    super.b,
    super.c,
    ScheduleState seed, {
    super.trackerHub,
  }) {
    emit(seed);
  }
  @override
  Future<void> load() async {}
}

class _FA implements AiringService {
  @override
  bool lastFailureOffline = false;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FS implements ComingSoonService {
  @override
  bool lastFailureOffline = false;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FM implements MyListStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTracker extends ChangeNotifier implements Tracker {
  _FakeTracker(this.displayName, this._items);

  @override
  final String displayName;
  final List<TrackerListItem> _items;
  int fetchCount = 0;

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

void main() {
  testWidgets('renders Anime timeline + Movies & TV segment', (tester) async {
    // Key the seed to today's local midnight so the selected day matches.
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final seed = ScheduleState(
      selectedDay: today,
      airingByDay: {
        today: [
          AiringEntry(
            malId: 1,
            title: 'My Anime',
            coverUrl: null,
            episode: 7,
            airsAtLocal: today.add(const Duration(hours: 18, minutes: 30)),
            format: 'TV',
          ),
          AiringEntry(
            malId: 2,
            title: 'Other Anime',
            coverUrl: null,
            episode: 3,
            airsAtLocal: today.add(const Duration(hours: 19)),
            format: 'TV',
          ),
        ],
      },
      soonByDay: {
        today: [
          ComingSoonEntry(
            tmdbId: 5,
            isTv: false,
            title: 'Big Movie',
            posterUrl: null,
            releaseDate: today,
          ),
        ],
      },
      loadingAiring: false,
      loadingSoon: false,
      connectedTrackerNames: const ['AniList', 'MyAnimeList'],
    );
    final aniList = _FakeTracker('AniList', [
      TrackerListItem(
        item: const MediaItem(
          id: 'mal:1',
          title: 'My Anime',
          url: '',
          type: ProviderType.anime,
          sourceId: '',
          malId: 1,
        ),
        status: WatchStatus.planning,
      ),
    ]);
    final mal = _FakeTracker('MyAnimeList', const []);
    late _StubCubit cubit;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<ScheduleCubit>(
          create: (_) => cubit = _StubCubit(
            _FA(),
            _FS(),
            _FM(),
            seed,
            trackerHub: TrackerHub([aniList, mal]),
          ),
          child: const ScheduleBody(), // the phone view widget, cubit-driven
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Anime'), findsOneWidget);
    expect(find.text('Other Anime'), findsOneWidget);
    expect(find.textContaining('Episode 7'), findsOneWidget);
    expect(aniList.fetchCount, 0);
    expect(
      find.byKey(const ValueKey('schedule-filter-source')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-filter-source')));
    await tester.pumpAndSettle();
    final filterRect = tester.getRect(
      find.byKey(const ValueKey('schedule-filter-source')),
    );
    final menuItemRect = tester.getRect(
      find.byKey(const ValueKey('schedule-filter-option-all')),
    );
    expect(menuItemRect.top, greaterThanOrEqualTo(filterRect.bottom));
    final allLabelRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-filter-option-all')),
        matching: find.text('All'),
      ),
    );
    final myListLabelRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-filter-option-my-list')),
        matching: find.text('My List'),
      ),
    );
    final aniListLabelRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-filter-option-AniList')),
        matching: find.text('AniList'),
      ),
    );
    expect(myListLabelRect.left, closeTo(allLabelRect.left, 0.1));
    expect(aniListLabelRect.left, closeTo(allLabelRect.left, 0.1));
    expect(
      tester.getSize(
        find.byKey(const ValueKey('schedule-filter-leading-my-list')),
      ),
      const Size(24, 24),
    );
    expect(find.text('All'), findsNWidgets(2));
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('MAL'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('schedule-filter-option-AniList')),
    );
    await tester.pumpAndSettle();
    expect(aniList.fetchCount, 1);
    expect(cubit.state.trackerFilterName, 'AniList');
    expect(find.text('My Anime'), findsOneWidget);
    expect(find.text('Other Anime'), findsNothing);
    // Switch to the Movies & TV segment.
    await tester.tap(find.text('Movies & TV'));
    await tester.pumpAndSettle();
    expect(find.text('Big Movie'), findsOneWidget);
  });
}
