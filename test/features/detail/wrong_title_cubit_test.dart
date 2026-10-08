import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/zmode/match_store.dart';
import 'package:watch_app/core/zmode/zmode_source_prefs.dart';
import 'package:watch_app/core/zmode/source_matcher.dart';
import 'package:watch_app/core/zmode/zmode_ids.dart';
import 'package:watch_app/features/detail/cubit/wrong_title_cubit.dart';

class _Src implements SourceRepository {
  _Src({this.fail = false, this.byQuery = const {}, this.pending = const {}});
  final bool fail;
  final searched = <String>[];
  final queries = <String>[];
  final Map<String, List<MediaItem>> byQuery;
  final Map<String, Completer<List<MediaItem>>> pending;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  // Added with the on-demand resolver: SourceMatcher now asks whether a JS
  // provider is loaded before searching it. These fakes are already "loaded".
  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  List<({String id, String name})> get pickableSources => loadedSources;
  @override
  String baseUrlFor(String id) =>
      id.startsWith('ani:') || id.startsWith('mihon:') || id.startsWith('lnr:')
      ? 'https://example.test'
      : '';
  @override
  bool hasSource(String sourceId) => true;
  @override
  Future<List<MediaItem>> search(
    String q, {
    String category = 'sub',
    String? sourceId,
  }) async {
    searched.add(sourceId!);
    queries.add(q);
    if (fail) throw StateError('dead');
    if (pending[q] case final completer?) return completer.future;
    if (byQuery.containsKey(q)) return byQuery[q]!;
    return [
      MediaItem(
        id: 'fmab',
        title: 'FMA: Brotherhood',
        url: 'https://$sourceId/fmab',
        type: ProviderType.anime,
        sourceId: sourceId,
      ),
    ];
  }
}

void main() {
  late Directory dir;
  late MatchStore store;
  late ZSourcePrefs prefs;
  const fma = ZCanonical(ZKind.anime, 'mal:5114');

  WrongTitleCubit build(_Src src, {String sourceId = 'allanime'}) =>
      WrongTitleCubit(
        sources: src,
        matcher: SourceMatcher(
          sources: src,
          store: store,
          prefs: prefs,
          candidates: (_) => [
            (id: 'allanime', name: 'AllAnime'),
            (id: 'hianime', name: 'HiAnime'),
          ],
        ),
        canonical: fma,
        sourceId: sourceId,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wrongshow_cubit');
    Hive.init(dir.path);
    store = await MatchStore.open();
    prefs = await ZSourcePrefs.open();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('starts with no results, scoped to the given source', () {
    final c = build(_Src());
    expect(c.sourceId, 'allanime');
    expect(c.state.results, isEmpty);
    expect(c.state.loading, isFalse);
  });

  test('search only ever searches the fixed source', () async {
    final src = _Src();
    final c = build(src, sourceId: 'hianime');
    await c.search('fma');
    expect(src.searched, ['hianime']);
    expect(c.state.results.single.sourceId, 'hianime');
    expect(c.state.loading, isFalse);
  });

  test('a dead source empties results instead of throwing', () async {
    final c = build(_Src(fail: true));
    await c.search('fma');
    expect(c.state.results, isEmpty);
    expect(c.state.loading, isFalse);
  });

  test(
    'retries up to three metadata aliases and merges results as they arrive',
    () async {
      final aliasSearch = Completer<List<MediaItem>>();
      final first = MediaItem(
        id: 'unrelated',
        title: 'Unrelated result',
        url: 'https://hianime/unrelated',
        type: ProviderType.anime,
        sourceId: 'hianime',
      );
      final duplicate = MediaItem(
        id: 'unrelated-copy',
        title: 'Unrelated result',
        url: 'https://hianime/unrelated',
        type: ProviderType.anime,
        sourceId: 'hianime',
      );
      const japaneseTitle = '鋼の錬金術師';
      final correct = MediaItem(
        id: 'fma',
        title: japaneseTitle,
        url: 'https://hianime/fma',
        type: ProviderType.anime,
        sourceId: 'hianime',
      );
      final src = _Src(
        byQuery: {
          'English title': [first],
          'Romaji title': [duplicate],
        },
        pending: {japaneseTitle: aliasSearch},
      );
      final c = build(src, sourceId: 'hianime');

      final search = c.search(
        'English title',
        retryWithMetadataAliases: true,
        metadataAliases: const [
          'English title',
          'Romaji title',
          japaneseTitle,
          'Synonym one',
          'Synonym two',
        ],
      );
      await Future<void>.delayed(Duration.zero);

      expect(src.queries, ['English title', 'Romaji title', japaneseTitle]);
      expect(c.state.query, 'English title');
      expect(c.state.loading, isTrue);
      expect(c.state.results, [first], reason: 'primary results stay visible');

      aliasSearch.complete([correct]);
      await search;

      expect(src.queries, ['English title', 'Romaji title', japaneseTitle]);
      expect(c.state.results, [first, correct]);
      expect(c.state.loading, isFalse);
    },
  );

  test(
    'does not retry aliases when a clear metadata-title match exists',
    () async {
      final result = MediaItem(
        id: 'fma',
        title: '鋼の錬金術師',
        url: 'https://hianime/fma',
        type: ProviderType.anime,
        sourceId: 'hianime',
      );
      final src = _Src(
        byQuery: {
          'English title': [result],
        },
      );
      final c = build(src, sourceId: 'hianime');

      await c.search(
        'English title',
        retryWithMetadataAliases: true,
        metadataAliases: const ['鋼の錬金術師', 'Romaji title'],
      );

      expect(src.queries, ['English title']);
      expect(c.state.results, [result]);
      expect(c.state.loading, isFalse);
    },
  );

  test(
    'manual searches remain literal and do not retry metadata aliases',
    () async {
      final src = _Src();
      final c = build(src, sourceId: 'hianime');

      await c.search('my typed query');

      expect(src.queries, ['my typed query']);
    },
  );

  test('alias fallback makes at most three additional requests', () async {
    final src = _Src(byQuery: {'Main title': const []});
    final c = build(src, sourceId: 'hianime');

    await c.search(
      'Main title',
      retryWithMetadataAliases: true,
      metadataAliases: const [
        'Main title',
        'Alias one',
        'Alias two',
        'Alias three',
        'Alias four',
      ],
    );

    expect(src.queries, [
      'Main title',
      'Alias one',
      'Alias two',
      'Alias three',
    ]);
  });

  test(
    'changing source retries aliases only on the newly selected source',
    () async {
      final src = _Src(byQuery: {'Main title': const []});
      final c = build(src);

      await c.search(
        'Main title',
        retryWithMetadataAliases: true,
        metadataAliases: const ['Alias title'],
      );
      await c.setSource('hianime');

      expect(src.queries, [
        'Main title',
        'Alias title',
        'Main title',
        'Alias title',
      ]);
      expect(src.searched, ['allanime', 'allanime', 'hianime', 'hianime']);
    },
  );

  test('choose pins the pick for its source', () async {
    final c = build(_Src(), sourceId: 'hianime');
    await c.search('fma');
    final m = await c.choose(c.state.results.single);
    expect(m.pinned, isTrue);
    expect(store.get(fma, 'hianime')?.showId, 'fmab');
    // For this title only — the kind default is not a place to record one
    // show's correction.
    expect(prefs.get(fma.kind), isNull);
  });
}
