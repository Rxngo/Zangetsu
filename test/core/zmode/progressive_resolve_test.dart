import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/source_health_store.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/zmode/match_store.dart';
import 'package:watch_app/core/zmode/playback_resolver.dart';
import 'package:watch_app/core/zmode/source_matcher.dart';
import 'package:watch_app/core/zmode/source_score_store.dart';
import 'package:watch_app/core/zmode/zmode_ids.dart';
import 'package:watch_app/core/zmode/zmode_source_prefs.dart';

/// Progressive resolve yields the first genuine hit without awaiting the
/// whole sweep. Uses the same fakes as playback_resolver_test.dart:
/// two sources, one fast with streams, one slow.
void main() {
  const show = ZCanonical(ZKind.anime, 'mal:100');
  const ep2 = 'zm://anime/mal:100/ep/2';

  late Directory dir;
  late MatchStore store;
  late ZSourcePrefs prefs;
  late SourceHealthStore health;
  late SourceScoreStore scores;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('progressive-resolve');
    Hive.init(dir.path);
    await SourceHealthStore.init();
    health = SourceHealthStore();
    store = await MatchStore.open();
    prefs = await ZSourcePrefs.open();
    scores = await SourceScoreStore.open();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  PlaybackResolver resolver({
    required SourceRepository sources,
    required SourceMatcher matcher,
    String? preferred,
    Duration? budget,
  }) {
    if (preferred != null) prefs.set(show.kind, preferred);
    final r = PlaybackResolver(
      matcher: matcher,
      sources: sources,
      store: store,
      prefs: prefs,
      health: health,
      candidates: (_) => [(id: 'src-a', name: 'A'), (id: 'src-b', name: 'B')],
      perSourceBudget: budget,
      scores: scores,
    );
    r.bindTitleLookup((_) async => (title: 'FMA', alt: null, malId: 100));
    return r;
  }

  SourceMatcher matcherFor(SourceRepository src) => SourceMatcher(
        sources: src,
        store: store,
        prefs: prefs,
        candidates: (_) => (src as _ProgSrc).loadedSources,
      );

  group('resolveProgressive', () {
    test('yields first hit before slow source answers', () async {
      // Fake setup mirrors playback_resolver_test.dart's resolver harness:
      // source "fast" answers 2 streams in 50ms, source "slow" answers
      // 3 streams after 5s. Collect EVERY event: the first must land well
      // before the slow source answers, the stream ends with done.
      final src = _ProgSrc.fastSlow();
      final r = resolver(sources: src, matcher: matcherFor(src));
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      final events = <ProgressiveResolve>[];
      final sw = Stopwatch()..start();
      var firstAtMs = -1;
      await for (final e in stream) {
        if (events.isEmpty) firstAtMs = sw.elapsedMilliseconds;
        events.add(e);
      }
      expect(
        firstAtMs,
        lessThan(2000),
        reason: 'first hit must not wait for the 5s slow source',
      );
      expect(events.length, 3, reason: 'fast hit, slow hit, done');
      expect(events.first.match.sourceId, 'src-a');
      expect(events.first.streams.length, 2);
      expect(events.first.done, isFalse);
      expect(events[1].match.sourceId, 'src-b');
      expect(events[1].streams.length, 3);
      expect(events.last.done, isTrue);
    });

    test('pinned source is honored, never substituted', () async {
      // Pin the fast source: the first paint is the source the viewer chose.
      final src = _ProgSrc.fastSlow();
      await store.pin(
        show,
        const SourceMatch(
          sourceId: 'src-a',
          showUrl: 'https://a/show',
          showId: 'a',
          showTitle: 'FMA',
          pinned: true,
        ),
      );
      final r = resolver(sources: src, matcher: matcherFor(src));
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      final ProgressiveResolve first = await stream.first;
      expect(first.match.sourceId, 'src-a');
      expect(first.done, isFalse);
    });

    test('pinned source failing is never substituted', () async {
      // The load-bearing half of the pin rule: the pinned source lacks the
      // episode, so the stream ends with the full sweep's verdict instead
      // of handing over the other source's streams.
      final src = _ProgSrc.fastSlow(aHasEp2: false);
      await store.pin(
        show,
        const SourceMatch(
          sourceId: 'src-a',
          showUrl: 'https://a/show',
          showId: 'a',
          showTitle: 'FMA',
          pinned: true,
        ),
      );
      final r = resolver(sources: src, matcher: matcherFor(src));
      await expectLater(
        r.resolveProgressive(ep2),
        emitsError(isA<EpisodeNotAvailable>()),
      );
      expect(
        src.log.where((l) => l.endsWith(':src-b')),
        isEmpty,
        reason: 'src-b answered behind the pinned failure and must be dropped',
      );
    });

    test('leaving drops late arrivals (generation guard)', () async {
      // The viewer leaves right after first paint: the slow source's late
      // arrival is dropped and the stream ends with PlaybackAborted,
      // the same signal the full sweep throws.
      final src = _ProgSrc.fastSlow();
      final r = resolver(sources: src, matcher: matcherFor(src));
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      final events = <ProgressiveResolve>[];
      Object? error;
      try {
        await for (final e in stream) {
          events.add(e);
          r.abortSweeps(); // the viewer pressed back
        }
      } catch (e) {
        error = e;
      }
      expect(
        events.length,
        1,
        reason: 'only the first paint landed before leaving',
      );
      expect(error, isA<PlaybackAborted>());
    });
  });
}

/// Same construction pattern as playback_resolver_test.dart's _SweepSrc:
/// two candidates, per-source episode lists, per-source streams.
/// Timing is the only addition: "fast" (src-a) answers 2 streams in 50ms,
/// "slow" (src-b) answers 3 streams after 5s.
class _ProgSrc implements SourceRepository {
  _ProgSrc.fastSlow({this.aHasEp2 = true})
      : aEps = const [
          Episode(id: '1', title: 'Ep 1', number: 1, url: 'https://a/1'),
          Episode(id: '2', title: 'Ep 2', number: 2, url: 'https://a/2'),
        ],
        bEps = const [
          Episode(id: '1', title: 'Ep 1', number: 1, url: 'https://b/1'),
          Episode(id: '2', title: 'Ep 2', number: 2, url: 'https://b/2'),
        ];

  final List<Episode> aEps;
  final List<Episode> bEps;

  /// When false, src-a lists only ep 1 — the pinned-failure case.
  final bool aHasEp2;

  /// Every episode-list and stream fetch, per source.
  final log = <String>[];

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<({String id, String name})> get loadedSources => [
        (id: 'src-a', name: 'A'),
        (id: 'src-b', name: 'B'),
      ];

  @override
  List<({String id, String name})> get pickableSources => loadedSources;

  @override
  bool hasSource(String sourceId) => true;

  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  String displayName(String sourceId) => sourceId;

  @override
  Future<List<MediaItem>> search(String q, {String category = 'sub', String? sourceId}) async {
    if (sourceId == 'src-a') {
      return [MediaItem(id: 'a', title: 'FMA', url: 'https://a/show', type: ProviderType.anime, sourceId: 'src-a')];
    }
    if (sourceId == 'src-b') {
      return [MediaItem(id: 'b', title: 'FMA', url: 'https://b/show', type: ProviderType.anime, sourceId: 'src-b')];
    }
    return const [];
  }

  @override
  Future<List<Episode>> episodes(String url, {String category = 'sub', String? sourceId}) async {
    log.add('episodes:$url:$sourceId');
    if (sourceId == 'src-a') return aHasEp2 ? aEps : const [Episode(id: '1', title: 'Ep 1', number: 1, url: 'https://a/1')];
    if (sourceId == 'src-b') return bEps;
    return const [];
  }

  @override
  Future<List<VideoSource>> sources(String episodeUrl, {String? sourceId, bool fast = false}) async {
    log.add('sources:$episodeUrl:$sourceId');
    if (sourceId == 'src-a') {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return const [VideoSource(url: 'https://a/s1'), VideoSource(url: 'https://a/s2')];
    }
    if (sourceId == 'src-b') {
      await Future<void>.delayed(const Duration(seconds: 5));
      return const [
        VideoSource(url: 'https://b/s1'),
        VideoSource(url: 'https://b/s2'),
        VideoSource(url: 'https://b/s3'),
      ];
    }
    return const [];
  }
}
