import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/media_item.dart' show normalizeTitle;
import '../../core/models/provider_info.dart';
import '../../core/mode/content_mode.dart';
import '../../core/playback/my_list.dart';
import '../../core/schedule/airing_service.dart';
import '../../core/schedule/coming_soon_service.dart';
import '../../core/schedule/schedule_models.dart';
import '../../core/tracker/tracker.dart';
import '../../core/tracker/tracker_hub.dart';

class ScheduleState extends Equatable {
  const ScheduleState({
    this.airingAll = const [],
    this.airingByDay = const {},
    this.myListByDay = const {},
    this.comingSoon = const [],
    this.loadingAiring = true,
    this.loadingSoon = true,
    this.errorAiring = false,
    this.offline = false,
    this.errorSoon = false,
    // ── redesign additions (phone) ──
    this.selectedDay,
    this.myListOnly = false,
    this.followed = const FollowedShows(),
    this.soonByDay = const {},
    this.connectedTrackerNames = const [],
    this.trackerFilterName,
    this.trackerFollowedByName = const {},
    this.loadingTrackerName,
  });

  final List<AiringEntry> airingAll;

  /// All week airing entries grouped by local day (the week view / TV Anime).
  final Map<DateTime, List<AiringEntry>> airingByDay;

  /// Week airing narrowed to tracked anime, grouped by day (TV My List tab).
  /// Kept for the unchanged TV screen; the phone redesign uses [followed]
  /// with [myListOnly] instead.
  final Map<DateTime, List<AiringEntry>> myListByDay;

  final List<ComingSoonEntry> comingSoon;
  final bool loadingAiring;
  final bool loadingSoon;
  final bool errorAiring;

  /// Nothing reached the network on the last load. Distinct from an empty
  /// schedule: "nothing airing this week" is a claim, and it should not be
  /// made on a dropped connection.
  final bool offline;
  final bool errorSoon;

  // ── redesign additions ──
  /// The day whose episode list is shown. Null until first load (→ today).
  final DateTime? selectedDay;

  /// My List filter toggle — when on, the anime list/grid narrows to shows the
  /// user follows.
  final bool myListOnly;

  /// MAL ids of anime in My List — drives the green "you follow this" dot and
  /// the [myListOnly] filter. Matches on MAL id OR title — see [FollowedShows].
  final FollowedShows followed;

  /// Coming-soon movies/TV grouped by local release day (both views).
  final Map<DateTime, List<ComingSoonEntry>> soonByDay;

  /// Connected anime-capable trackers available in the schedule filter.
  final List<String> connectedTrackerNames;

  /// Selected tracker name; null means All unless [myListOnly] is true.
  final String? trackerFilterName;

  /// Session-cached tracker libraries, converted to the same title/id matcher
  /// used by the existing local My List filter.
  final Map<String, FollowedShows> trackerFollowedByName;

  /// Name of the tracker whose list is currently being fetched, if any.
  final String? loadingTrackerName;

  /// Active filter, or null when the schedule shows every airing.
  FollowedShows? get activeFollowed {
    if (myListOnly) return followed;
    final name = trackerFilterName;
    return name == null
        ? null
        : trackerFollowedByName[name] ?? const FollowedShows();
  }

  ScheduleState copyWith({
    List<AiringEntry>? airingAll,
    Map<DateTime, List<AiringEntry>>? airingByDay,
    Map<DateTime, List<AiringEntry>>? myListByDay,
    List<ComingSoonEntry>? comingSoon,
    bool? loadingAiring,
    bool? loadingSoon,
    bool? errorAiring,
    bool? offline,
    bool? errorSoon,
    DateTime? selectedDay,
    bool? myListOnly,
    FollowedShows? followed,
    Map<DateTime, List<ComingSoonEntry>>? soonByDay,
    List<String>? connectedTrackerNames,
    String? trackerFilterName,
    bool clearTrackerFilterName = false,
    Map<String, FollowedShows>? trackerFollowedByName,
    String? loadingTrackerName,
    bool clearLoadingTrackerName = false,
  }) => ScheduleState(
    airingAll: airingAll ?? this.airingAll,
    airingByDay: airingByDay ?? this.airingByDay,
    myListByDay: myListByDay ?? this.myListByDay,
    comingSoon: comingSoon ?? this.comingSoon,
    loadingAiring: loadingAiring ?? this.loadingAiring,
    loadingSoon: loadingSoon ?? this.loadingSoon,
    errorAiring: errorAiring ?? this.errorAiring,
    offline: offline ?? this.offline,
    errorSoon: errorSoon ?? this.errorSoon,
    selectedDay: selectedDay ?? this.selectedDay,
    myListOnly: myListOnly ?? this.myListOnly,
    followed: followed ?? this.followed,
    soonByDay: soonByDay ?? this.soonByDay,
    connectedTrackerNames: connectedTrackerNames ?? this.connectedTrackerNames,
    trackerFilterName: clearTrackerFilterName
        ? null
        : trackerFilterName ?? this.trackerFilterName,
    trackerFollowedByName: trackerFollowedByName ?? this.trackerFollowedByName,
    loadingTrackerName: clearLoadingTrackerName
        ? null
        : loadingTrackerName ?? this.loadingTrackerName,
  );

  @override
  List<Object?> get props => [
    airingAll,
    airingByDay,
    myListByDay,
    comingSoon,
    loadingAiring,
    loadingSoon,
    errorAiring,
    errorSoon,
    offline,
    selectedDay,
    myListOnly,
    followed,
    soonByDay,
    connectedTrackerNames,
    trackerFilterName,
    trackerFollowedByName,
    loadingTrackerName,
  ];
}

class ScheduleCubit extends Cubit<ScheduleState> {
  ScheduleCubit(
    this._airing,
    this._soon,
    this._myList, {
    List<Duration>? retryDelays,
    TrackerHub? trackerHub,
  }) : _retryDelays = retryDelays ?? _defaultRetryDelays,
       _trackerHub = trackerHub,
       super(const ScheduleState()) {
    final hub = _trackerHub;
    if (hub != null) {
      _syncConnectedTrackers();
      for (final tracker in hub.trackers) {
        void listener() => _onTrackerChanged(tracker);
        _trackerListeners[tracker] = listener;
        tracker.addListener(listener);
      }
    }
  }

  final AiringService _airing;
  final ComingSoonService _soon;
  final MyListStore _myList;
  final TrackerHub? _trackerHub;

  final Map<String, int> _trackerRequestVersions = {};
  final Set<String> _fetchingTrackers = {};
  final Map<Tracker, VoidCallback> _trackerListeners = {};

  // Backoff between retries when a fetch comes back empty. Both services
  // already swallow errors and return [] on failure, and neither AniList's
  // weekly airing nor TMDB's upcoming window is ever legitimately empty — so
  // an empty result means the request failed (e.g. network not ready at the
  // startup load) and is worth retrying. Stays on the loading spinner across
  // retries rather than flashing a false "nothing here". Injectable so tests
  // can pass `const []` and skip the real delays.
  static const List<Duration> _defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];
  final List<Duration> _retryDelays;

  bool _inFlight = false;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> load() async {
    if (_inFlight) return; // don't stack retry loops (e.g. refresh mid-retry)
    _inFlight = true;
    // Seed today on the first load so the day strip has a selection.
    final now = DateTime.now();
    if (state.selectedDay == null) {
      emit(state.copyWith(selectedDay: _dayOf(now)));
    }
    try {
      await Future.wait([_loadAiring(), _loadSoon()]);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> refresh() => load();

  void selectDay(DateTime day) =>
      emit(state.copyWith(selectedDay: _dayOf(day)));

  void selectAllAirings() {
    emit(
      state.copyWith(
        myListOnly: false,
        clearTrackerFilterName: true,
        clearLoadingTrackerName: true,
      ),
    );
  }

  void selectMyListFilter() {
    emit(
      state.copyWith(
        myListOnly: true,
        clearTrackerFilterName: true,
        clearLoadingTrackerName: true,
      ),
    );
  }

  /// Kept for existing callers: tapping My List still toggles between it and
  /// All, and always clears a selected tracker filter.
  void toggleMyListOnly() =>
      state.myListOnly ? selectAllAirings() : selectMyListFilter();

  /// Read and cache the selected tracker's anime list on demand. Merely
  /// opening Schedule never causes a tracker API request.
  Future<void> selectTrackerFilter(String trackerName) async {
    Tracker? tracker;
    for (final candidate in _connectedAnimeTrackers) {
      if (candidate.displayName == trackerName) {
        tracker = candidate;
        break;
      }
    }
    if (tracker == null) {
      selectAllAirings();
      return;
    }

    emit(
      state.copyWith(
        myListOnly: false,
        trackerFilterName: trackerName,
        clearLoadingTrackerName: true,
      ),
    );
    if (state.trackerFollowedByName.containsKey(trackerName)) return;
    if (_fetchingTrackers.contains(trackerName)) {
      emit(state.copyWith(loadingTrackerName: trackerName));
      return;
    }

    await _fetchTracker(tracker);
  }

  List<Tracker> get _connectedAnimeTrackers =>
      _trackerHub?.connectedForMode(ContentMode.anime).toList() ?? const [];

  void _syncConnectedTrackers() {
    emit(
      state.copyWith(
        connectedTrackerNames: [
          for (final tracker in _connectedAnimeTrackers) tracker.displayName,
        ],
      ),
    );
  }

  void _onTrackerChanged(Tracker tracker) {
    final hub = _trackerHub;
    if (hub == null) return;
    final names = [
      for (final connected in hub.connectedForMode(ContentMode.anime))
        connected.displayName,
    ];
    if (listEquals(names, state.connectedTrackerNames)) return;

    // A disconnect during a fetch invalidates that response so it cannot
    // repopulate a now-disconnected filter. Other tracker requests stay valid.
    if (!names.contains(tracker.displayName)) {
      _trackerRequestVersions[tracker.displayName] =
          (_trackerRequestVersions[tracker.displayName] ?? 0) + 1;
      _fetchingTrackers.remove(tracker.displayName);
    }
    final followed = Map<String, FollowedShows>.of(state.trackerFollowedByName)
      ..remove(tracker.displayName);
    final selectedDisconnected =
        state.trackerFilterName == tracker.displayName &&
        !names.contains(tracker.displayName);
    emit(
      state.copyWith(
        connectedTrackerNames: names,
        trackerFollowedByName: followed,
        myListOnly: selectedDisconnected ? false : state.myListOnly,
        clearTrackerFilterName: selectedDisconnected,
        clearLoadingTrackerName:
            state.loadingTrackerName == tracker.displayName,
      ),
    );
  }

  Future<void> _fetchTracker(Tracker tracker) async {
    final name = tracker.displayName;
    final version = (_trackerRequestVersions[name] ?? 0) + 1;
    _trackerRequestVersions[name] = version;
    _fetchingTrackers.add(name);
    emit(state.copyWith(loadingTrackerName: name));

    var followed = const FollowedShows();
    try {
      final items = await tracker.fetchList();
      followed = _followedShowsFromTracker(items);
    } catch (_) {
      // Tracker implementations are best-effort, but keep the schedule usable
      // even if a third-party implementation throws unexpectedly.
    }

    if (isClosed || _trackerRequestVersions[name] != version) return;
    _fetchingTrackers.remove(name);
    final cache = Map<String, FollowedShows>.of(state.trackerFollowedByName)
      ..[name] = followed;
    emit(
      state.copyWith(
        trackerFollowedByName: cache,
        clearLoadingTrackerName: state.loadingTrackerName == name,
      ),
    );
  }

  FollowedShows _followedShowsFromTracker(List<TrackerListItem> items) {
    final anime = items.where((entry) => entry.item.type == ProviderType.anime);
    return FollowedShows(
      malIds: {
        for (final entry in anime)
          if (entry.item.malId != null) entry.item.malId!,
      },
      titles: {
        for (final entry in anime) ...[
          normalizeTitle(entry.item.title),
          if (entry.item.englishTitle != null)
            normalizeTitle(entry.item.englishTitle!),
        ],
      }..removeWhere((title) => title.isEmpty),
    );
  }

  @override
  Future<void> close() {
    _trackerListeners.forEach((tracker, listener) {
      tracker.removeListener(listener);
    });
    return super.close();
  }

  Future<void> _loadAiring() async {
    emit(state.copyWith(loadingAiring: true, errorAiring: false));
    var entries = await _airing.weekAiring();
    for (var i = 0; entries.isEmpty && i < _retryDelays.length; i++) {
      await Future<void>.delayed(_retryDelays[i]);
      if (isClosed) return; // widget disposed mid-retry
      entries = await _airing.weekAiring();
    }
    if (isClosed) return;
    final followed = _followedShows();
    emit(
      state.copyWith(
        airingAll: entries,
        airingByDay: groupByLocalDay(entries),
        myListByDay: groupByLocalDay(filterByFollowed(entries, followed)),
        followed: followed,
        loadingAiring: false,
        errorAiring:
            entries.isEmpty, // still empty after retries → genuine miss
        offline: entries.isEmpty && _airing.lastFailureOffline,
      ),
    );
  }

  Future<void> _loadSoon() async {
    emit(state.copyWith(loadingSoon: true, errorSoon: false));
    var soon = await _soon.upcoming();
    for (var i = 0; soon.isEmpty && i < _retryDelays.length; i++) {
      await Future<void>.delayed(_retryDelays[i]);
      if (isClosed) return;
      soon = await _soon.upcoming();
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        comingSoon: soon,
        soonByDay: groupSoonByLocalDay(soon),
        loadingSoon: false,
        errorSoon: soon.isEmpty,
        offline: soon.isEmpty && _soon.lastFailureOffline,
      ),
    );
  }

  /// What the My List filter matches against.
  ///
  /// Both ids AND titles: most list entries have no malId (it only arrives with
  /// metadata enrichment), so an id-only set was usually empty and the filter
  /// hid everything.
  FollowedShows _followedShows() {
    final mine = _myList
        .all()
        .where((m) => m.type == ProviderType.anime)
        .toList();
    return FollowedShows(
      malIds: {
        for (final m in mine)
          if (m.malId != null) m.malId!,
      },
      titles: {
        for (final m in mine) ...[
          normalizeTitle(m.title),
          if (m.englishTitle != null) normalizeTitle(m.englishTitle!),
        ],
      }..removeWhere((t) => t.isEmpty),
    );
  }
}
