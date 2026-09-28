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
      // 3 streams after 5s. Collect the FIRST event only.
      final src = _ProgSrc.fastSlow();
      final r = resolver(sources: src, matcher: matcherFor(src));
      // ignore: undefined_method
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      final ProgressiveResolve first = await stream.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('no first hit before slow answered'),
      );
      expect(first.streams.length, 2);
      fail('not implemented: resolveProgressive does not exist yet');
    });

    test('pinned source is honored, never substituted', () async {
      final src = _ProgSrc.fastSlow();
      final r = resolver(sources: src, matcher: matcherFor(src));
      // ignore: undefined_method
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      final ProgressiveResolve first = await stream.first;
      expect(first.sourceId, 'src-a');
      fail('not implemented: resolveProgressive does not exist yet');
    });

    test('leaving drops late arrivals (generation guard)', () async {
      final src = _ProgSrc.fastSlow();
      final r = resolver(sources: src, matcher: matcherFor(src));
      // ignore: undefined_method
      final Stream<ProgressiveResolve> stream = r.resolveProgressive(ep2);
      await stream.first;
      r.invalidateWinner(ep2);
      await expectLater(
        // ignore: undefined_method
        r.resolveProgressive(ep2),
        emitsThrough(isA<ProgressiveResolve>()),
      );
      fail('not implemented: resolveProgressive does not exist yet');
    });
  });
}

/// Same construction pattern as playback_resolver_test.dart's _SweepSrc:
/// two candidates, per-source episode lists, per-source streams.
/// Timing is the only addition: "fast" (src-a) answers 2 streams in 50ms,
/// "slow" (src-b) answers 3 streams after 5s.
class _ProgSrc implements SourceRepository {
  _ProgSrc.fastSlow()
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
    if (sourceId == 'src-a') return aEps;
    if (sourceId == 'src-b') return bEps;
    return const [];
  }

  @override
  Future<List<VideoSource>> sources(String episodeUrl, {String? sourceId, bool fast = false}) async {
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
