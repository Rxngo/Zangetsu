import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/aniyomi/aniyomi_repo.dart';
import 'package:watch_app/core/mihon/mihon_repo.dart';

/// A NON-github base, so each index file costs exactly one request and the
/// recorded order is the fetcher's own walk rather than a mirror sweep. The
/// jsDelivr fallback gets its own test below.
const _base = 'https://example.com/repo';

void main() {
  group('AniyomiRepo.fetchIndex', () {
    setUp(() => GetIt.instance.reset());
    tearDown(() => GetIt.instance.reset());

    void registerDio(_RoutingAdapter adapter) {
      GetIt.instance.registerSingleton<Dio>(
        Dio()..httpClientAdapter = adapter,
      );
    }

    // The bug this exists for: the fetcher read ONLY index.min.json, so
    // `Secozzi/aniyomi-extensions` — whose maintainer reduced that file to a
    // one-line "switch to Animiru 0.20+" stub while leaving index.json and
    // index.pb intact — came back as a repo holding nothing but the stub.
    test('a decodable index.pb wins and index.json is never requested',
        () async {
      final adapter = _RoutingAdapter({
        '$_base/index.pb': _pbStore(pkg: 'p.pb', name: 'FromPb'),
        '$_base/index.json': _mihonIndex(pkg: 'p.json', name: 'FromJson'),
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Stub'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries.map((e) => e.name), ['FromPb']);
      expect(entries.single.pkg, 'p.pb');
      expect(adapter.requested, ['$_base/index.pb']);
    });

    test('falls back to index.json when index.pb 404s', () async {
      final adapter = _RoutingAdapter({
        '$_base/index.json': _mihonIndex(pkg: 'p.json', name: 'FromJson'),
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Stub'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries.single.name, 'FromJson');
      expect(adapter.requested.first, '$_base/index.pb');
      expect(adapter.requested, [
        '$_base/index.pb',
        '$_base/index.json',
      ]);
    });

    test('an index.pb that will not decode falls through instead of failing '
        'the repo', () async {
      final adapter = _RoutingAdapter({
        // 200 OK, garbage bytes. Dart's gzip is lenient enough to inflate this
        // to nothing rather than throwing, so it decodes to ZERO entries — a
        // hole that would otherwise surface as "No extensions found" while a
        // perfectly good index.json sat untouched.
        '$_base/index.pb': [0x1f, 0x8b, 0x08, 0x00, 0xff, 0xfe],
        '$_base/index.json': _mihonIndex(pkg: 'p.json', name: 'FromJson'),
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Stub'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries.single.name, 'FromJson');
      // The broken pb is not retried against a mirror either — it carries the
      // same data as index.json, which is being read now.
      expect(
        adapter.requested.where((u) => u.endsWith('/index.pb')),
        hasLength(1),
      );
    });

    test('a pb that is valid protobuf but truncated throws and falls through',
        () async {
      final adapter = _RoutingAdapter({
        '$_base/index.pb': gzip.encode([1, 2, 3, 4, 5, 6, 7, 8, 9])
            .sublist(0, 8),
        '$_base/index.json': _mihonIndex(pkg: 'p.json', name: 'FromJson'),
      });
      registerDio(adapter);

      expect((await AniyomiRepo.fetchIndex(_base)).single.name, 'FromJson');
    });

    test('falls back to index.min.json when pb and json are both absent',
        () async {
      final adapter = _RoutingAdapter({
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Legacy'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries.single.name, 'Legacy');
      expect(adapter.requested, [
        '$_base/index.pb',
        '$_base/index.json',
        '$_base/index.min.json',
      ]);
    });

    // The yuzono/anime-repo shape: a repo that never migrated and publishes
    // nothing but the legacy array. Must not regress — it is the reason
    // index.min.json stays in the list at all.
    test('a repo serving ONLY index.min.json still works', () async {
      final adapter = _RoutingAdapter({
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Legacy'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries, hasLength(1));
      expect(entries.single.pkg, 'p.min');
      // Built from the directory, not the file it was fetched from.
      expect(entries.single.apkUrl, '$_base/apk/legacy-v1.0.apk');
    });

    test('a reachable but unparseable JSON index raises instead of quietly '
        'serving the legacy stub', () async {
      final adapter = _RoutingAdapter({
        '$_base/index.json': '{"totally":"different"}',
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Stub'),
      });
      registerDio(adapter);

      await expectLater(
        AniyomiRepo.fetchIndex(_base),
        throwsA(
          isA<MihonRepoException>().having(
            (e) => e.toString(),
            'message',
            contains('unrecognised repo index format'),
          ),
        ),
      );
      // Returning the stub here would look exactly like the bug this was
      // written to fix, so the legacy file is never even requested.
      expect(adapter.requested, isNot(contains('$_base/index.min.json')));
    });

    test('a fully unreachable repo throws rather than returning empty',
        () async {
      final adapter = _RoutingAdapter(const {});
      registerDio(adapter);

      await expectLater(
        AniyomiRepo.fetchIndex(_base),
        throwsA(isA<MihonRepoException>()),
      );
      expect(adapter.requested, hasLength(3));
    });

    test('an empty index.json body is treated as absent, not as the index',
        () async {
      final adapter = _RoutingAdapter({
        '$_base/index.json': '   ',
        '$_base/index.min.json': _legacyIndex(pkg: 'p.min', name: 'Legacy'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(_base);

      expect(entries.single.name, 'Legacy');
    });

    test('a github-raw repo retries index.pb through the jsDelivr mirror',
        () async {
      const gh = 'https://raw.githubusercontent.com/o/r/main';
      final adapter = _RoutingAdapter({
        'https://gcore.jsdelivr.net/gh/o/r@main/index.pb': _pbStore(
          pkg: 'p.mirror',
          name: 'ViaMirror',
        ),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex(gh);

      expect(entries.single.name, 'ViaMirror');
      expect(adapter.requested, [
        '$gh/index.pb',
        'https://gcore.jsdelivr.net/gh/o/r@main/index.pb',
      ]);
    });

    test('a pasted index URL is normalised to the directory first', () async {
      final adapter = _RoutingAdapter({
        '$_base/index.json': _mihonIndex(pkg: 'p.json', name: 'FromJson'),
      });
      registerDio(adapter);

      final entries = await AniyomiRepo.fetchIndex('$_base/index.min.json');

      expect(entries.single.name, 'FromJson');
      expect(
        adapter.requested.any((u) => u.contains('index.min.json/')),
        isFalse,
      );
    });
  });
}

String _mihonIndex({required String pkg, required String name}) => jsonEncode({
      'name': 'TestRepo',
      'extensionList': {
        'extensions': [
          {
            'name': name,
            'packageName': pkg,
            'versionName': '1.0.0',
            'versionCode': '1',
            'resources': {'apkUrl': 'https://cdn.example/apk/$pkg-v1.0.0.apk'},
            'sources': [
              {'id': 1, 'name': name, 'language': 'en', 'homeUrl': 'https://e'},
            ],
          },
        ],
      },
    });

String _legacyIndex({required String pkg, required String name}) => jsonEncode([
      {
        'name': name,
        'pkg': pkg,
        'apk': 'legacy-v1.0.apk',
        'lang': 'en',
        'version': '1.0',
        'code': 1,
        'nsfw': 0,
        'sources': <Object>[],
      },
    ]);

/// Builds a gzip'd `NetworkExtensionStore` holding one extension — the
/// proto3 encoders mirror test/core/mihon/mihon_pb_index_test.dart rather than
/// committing a binary fixture.
List<int> _pbStore({required String pkg, required String name}) {
  List<int> varint(int v) {
    final out = <int>[];
    var n = v;
    while (true) {
      final b = n & 0x7f;
      n >>= 7;
      if (n == 0) {
        out.add(b);
        break;
      }
      out.add(b | 0x80);
    }
    return out;
  }

  List<int> tag(int f, int w) => varint((f << 3) | w);
  List<int> varintField(int f, int v) => [...tag(f, 0), ...varint(v)];
  List<int> lenField(int f, List<int> p) =>
      [...tag(f, 2), ...varint(p.length), ...p];
  List<int> strField(int f, String s) => lenField(f, utf8.encode(s));

  // Source { id=1, name=2, language=3, homeUrl=4 }
  final source = <int>[
    ...varintField(1, 42),
    ...strField(2, name),
    ...strField(3, 'en'),
    ...strField(4, 'https://e.test'),
  ];
  // Extension { name=1, pkg=2, resources=3, versionCode=5, versionName=6,
  //             sources=8 }
  final ext = <int>[
    ...strField(1, name),
    ...strField(2, pkg),
    ...lenField(3, strField(1, 'https://cdn.example/apk/$pkg-v1.0.0.apk')),
    ...varintField(5, 1),
    ...strField(6, '1.0.0'),
    ...lenField(8, source),
  ];
  // NetworkExtensionStore { name=1, extensionList=101 }
  return gzip.encode(
    <int>[...strField(1, 'TestRepo'), ...lenField(101, lenField(1, ext))],
  );
}

/// Serves [bodies] by exact URL and 404s everything else, recording the order
/// URLs were tried in. A body is a [String] or raw [List<int>] (index.pb).
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.bodies);

  final Map<String, Object> bodies;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    final body = bodies[url];
    if (body == null) return ResponseBody.fromString('Not Found', 404);
    if (body is List<int>) return ResponseBody.fromBytes(body, 200);
    return ResponseBody.fromString(
      body as String,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
