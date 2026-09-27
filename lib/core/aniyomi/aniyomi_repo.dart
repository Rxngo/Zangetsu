import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../hive/source_icon_store.dart';
// The manga twin's fetcher already walks index.pb → index.json →
// index.min.json and hands back this same entry type, so reuse its parsers
// rather than keeping a second copy of the wire logic here. Dart allows the
// import cycle; there are no top-level initialisers to order.
import '../mihon/mihon_repo.dart';

/// A single anime source entry within a repo index entry.
class AniyomiRepoSource {
  const AniyomiRepoSource({
    required this.id,
    required this.lang,
    required this.name,
    required this.baseUrl,
  });

  final int id;
  final String lang;
  final String name;
  final String baseUrl;

  factory AniyomiRepoSource.fromJson(Map<String, dynamic> json) {
    return AniyomiRepoSource(
      id: (json['id'] as num).toInt(),
      lang: (json['lang'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? '',
    );
  }
}

/// One extension entry from an Aniyomi repository `index.min.json`.
///
/// [apkUrl] is computed from [repoBaseUrl] and [apk] and is not stored in the
/// JSON itself.
class AniyomiRepoEntry {
  AniyomiRepoEntry({
    required this.name,
    required this.pkg,
    required this.apk,
    required this.lang,
    required this.version,
    required this.code,
    required this.nsfw,
    required this.sources,
    required String repoBaseUrl,
    String absoluteApkUrl = '',
    String absoluteIconUrl = '',
  })  : apkUrl = absoluteApkUrl.startsWith('http')
            ? absoluteApkUrl
            : '${AniyomiRepo.normalizeBase(repoBaseUrl)}/apk/$apk',
        iconUrl = absoluteIconUrl.startsWith('http')
            ? absoluteIconUrl
            : '${AniyomiRepo.normalizeBase(repoBaseUrl)}/icon/$pkg.png';

  final String name;
  final String pkg;
  final String apk;
  final String lang;
  final String version;
  final int code;

  /// [nsfw] is stored as 0/1 int in `index.min.json`; mapped to bool here.
  final bool nsfw;
  final List<AniyomiRepoSource> sources;

  /// Full URL to download the extension APK.
  ///
  /// Normally derived from the repo base + [apk]
  /// (`https://raw.githubusercontent.com/owner/repo/branch/apk/ext-v1.0.apk`),
  /// which is where repos have historically kept their APKs. When the index
  /// carries an absolute link of its own that wins instead: Keiyoushi now
  /// publishes to GitHub Releases under a per-build tag
  /// (`.../releases/download/88e1412-0/ext-v1.6.4.apk`) that cannot be
  /// reconstructed from the base — rebuilding the old path 404s on all ~1400
  /// of its extensions, so nothing installs.
  final String apkUrl;

  /// Full URL to the extension's icon.
  ///
  /// Repos keep these in an `icon/` folder named after the package, which is
  /// how the picker gets a real logo instead of a letter tile. The newer
  /// index carries its own absolute link (same reason as [apkUrl]) and that
  /// wins when present. Not every repo publishes icons — a 404 here is
  /// expected and just falls back to the letter.
  final String iconUrl;
}

/// Utilities for reading Aniyomi extension repository index files.
class AniyomiRepo {
  /// Index file names in preference order, the same list the Mihon fetcher
  /// walks.
  ///
  /// `index.pb` first: it is the same data as `index.json` (~13x smaller on the
  /// wire) and modern AniYomi repos publish it. `index.min.json` is last
  /// because it is the legacy Tachiyomi shape and its maintainers commonly
  /// reduce it to a stub — e.g. `Secozzi/aniyomi-extensions` serves a
  /// one-line "switch to Animiru 0.20+" there while `index.json` still lists 3
  /// real extensions, so reading ONLY this file made that repo look empty.
  static const List<String> _indexFiles = [
    'index.pb',
    'index.json',
    'index.min.json',
  ];

  /// Normalises a repo base URL to the DIRECTORY that holds `index.min.json`
  /// and the `apk/` folder. Users (and older saved repos) sometimes store the
  /// full index URL (`.../main/index.min.json`) instead of the directory
  /// (`.../main`); left as-is that produces a broken `.../index.min.json/apk/…`
  /// download URL that 404s on every mirror. Strips a trailing index filename
  /// — `/index.min.json`, `/index.json` or `/index.pb` — and any trailing
  /// slash. Shared with Mihon, which prefers `index.pb`.
  static String normalizeBase(String base) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    // People paste the link to the index file itself, not the folder holding
    // it, so strip a trailing index filename. Listed longest-first so
    // `index.min.json` isn't half-matched by `index.json`. `index.pb` belongs
    // here too — it's the file the fetcher now prefers, so it's the most
    // likely thing to be pasted; leaving it out meant the app asked for
    // `.../index.pb/index.pb` and the repo just 404'd.
    for (final name in const [
      '/index.min.json',
      '/index.json',
      '/index.pb',
    ]) {
      if (b.endsWith(name)) {
        b = b.substring(0, b.length - name.length);
        break;
      }
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// Parses an `index.min.json` JSON array string into a list of
  /// [AniyomiRepoEntry].
  ///
  /// Malformed individual entries are skipped; a totally invalid [json] string
  /// returns an empty list. Never throws.
  static List<AniyomiRepoEntry> parseIndex(
    String json, {
    required String repoBaseUrl,
  }) {
    final entries = <AniyomiRepoEntry>[];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      for (final raw in list) {
        try {
          final m = raw as Map<String, dynamic>;
          final rawSources = m['sources'];
          final sources = <AniyomiRepoSource>[];
          if (rawSources is List) {
            for (final s in rawSources) {
              try {
                sources.add(
                  AniyomiRepoSource.fromJson(s as Map<String, dynamic>),
                );
              } catch (_) {
                // skip malformed source entry
              }
            }
          }
          entries.add(
            AniyomiRepoEntry(
              name: (m['name'] as String?) ?? '',
              pkg: (m['pkg'] as String?) ?? '',
              apk: (m['apk'] as String?) ?? '',
              lang: (m['lang'] as String?) ?? '',
              version: (m['version'] as String?) ?? '',
              code: (m['code'] as num?)?.toInt() ?? 0,
              nsfw: ((m['nsfw'] as num?)?.toInt() ?? 0) != 0,
              sources: sources,
              repoBaseUrl: repoBaseUrl,
            ),
          );
        } catch (_) {
          // skip malformed entry; continue with the rest
        }
      }
    } catch (_) {
      // totally invalid JSON — return empty
    }
    return entries;
  }

  /// Fetches and parses the index for [repoBaseUrl].
  ///
  /// Tries `index.pb`, then `index.json`, then `index.min.json` — each direct
  /// first and then through the jsDelivr mirror when the host is
  /// `raw.githubusercontent.com` (blocked on some devices; non-githubusercontent
  /// bases skip the fallback).
  ///
  /// Only an *unreachable* file (network error, 404, any non-2xx, empty body)
  /// falls through to the next one, so `index.min.json` is reached exactly when
  /// the repo never published a modern index — the case that fallback exists
  /// for. A reachable but unparseable `index.pb` also falls through (it is just
  /// a mirror of `index.json`), but a reachable, non-empty JSON index that won't
  /// parse THROWS [MihonRepoException] instead: that is a schema change and it
  /// must be seen rather than hidden behind a legacy stub.
  ///
  /// Like the Mihon fetcher, this no longer degrades to an empty list — an
  /// empty repo and a broken one have to look different to the user.
  static Future<List<AniyomiRepoEntry>> fetchIndex(String repoBaseUrl) async {
    final dio = GetIt.instance<Dio>();
    final base = normalizeBase(repoBaseUrl);
    // jsDelivr answers with `application/json`, which Dio would helpfully
    // decode into a Map and then fail to cast to String — force plain text.
    final text = Options(responseType: ResponseType.plain);

    /// jsDelivr mirror of [url], or null when it isn't a github-raw file.
    String? jsDelivrUrl(String url) {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      if (uri.host != 'raw.githubusercontent.com') return null;
      // Path segments: ['', owner, repo, branch, ...rest]
      final segs = uri.pathSegments;
      if (segs.length < 3) return null;
      final owner = segs[0];
      final repo = segs[1];
      final branch = segs[2];
      return 'https://gcore.jsdelivr.net/gh/$owner/$repo@$branch/'
          '${segs.skip(3).join('/')}';
    }

    Object? lastError;
    for (final file in _indexFiles) {
      final isPb = file.endsWith('.pb');
      final direct = '$base/$file';
      final mirror = jsDelivrUrl(direct);
      for (final url in <String>[direct, ?mirror]) {
        if (isPb) {
          List<int>? bytes;
          try {
            final resp = await dio.get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes),
            );
            if ((resp.statusCode ?? 0) < 300) bytes = resp.data;
          } catch (e) {
            lastError = e;
            continue;
          }
          if (bytes == null || bytes.isEmpty) continue;
          // Unlike the JSON below, a pb that won't decode does NOT fail the
          // repo: it's a smaller mirror of the identical index.json, so on any
          // decode error fall through.
          try {
            final entries = MihonRepo.parsePbIndex(bytes, repoBaseUrl: base);
            // A pb that inflates to nothing decodes to zero entries rather than
            // throwing (Dart's gzip is lenient about garbage), and the same
            // data in index.json would have produced a repo. Falling through
            // here is what keeps that from being read as an empty repo.
            if (entries.isEmpty) {
              lastError = 'index.pb held no extensions';
              break;
            }
            // The index is the only place an extension's logo is named, so keep
            // the icon URLs on the way past — the source picker has no other
            // way to get one for an installed extension.
            SourceIconStore.recordAll(entries);
            return entries;
          } catch (e) {
            lastError = e;
            break; // give up on pb mirrors; move on to index.json
          }
        }

        String? body;
        try {
          final resp = await dio.get<String>(url, options: text);
          if ((resp.statusCode ?? 0) < 300) body = resp.data;
        } catch (e) {
          lastError = e;
          continue;
        }
        if (body == null || body.trim().isEmpty) continue;
        // Reachable and non-empty: this IS the repo's index, so a parse failure
        // is the answer and it propagates. Falling through to index.min.json
        // here would hide the next schema change behind whatever legacy stub
        // the repo still serves.
        final entries = MihonRepo.parseIndex(body, repoBaseUrl: base);
        SourceIconStore.recordAll(entries);
        return entries;
      }
    }

    throw MihonRepoException(
      "couldn't read this repo's index — ${lastError ?? 'no response'}",
    );
  }
}
