import 'dart:convert';
import 'dart:io';

/// Small app-private journal that lets the HLS service restore jobs after its
/// isolate or the app process is restarted.
class HlsDownloadJournal {
  const HlsDownloadJournal(this.directory);

  final Directory directory;

  Future<void> save(Map<String, dynamic> job) async {
    final id = job['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('HLS download job needs an id');
    }

    await directory.create(recursive: true);
    final file = File('${directory.path}/${_fileName(id)}.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'job': job,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<List<Map<String, dynamic>>> pending() async {
    if (!await directory.exists()) return const [];

    final entries = <({int savedAt, Map<String, dynamic> job})>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final envelope = jsonDecode(await entity.readAsString()) as Map;
        final rawJob = envelope['job'];
        final id = rawJob is Map ? rawJob['id'] : null;
        if (rawJob is! Map || id is! String || id.isEmpty) {
          await entity.delete();
          continue;
        }
        entries.add((
          savedAt: (envelope['savedAt'] as num?)?.toInt() ?? 0,
          job: Map<String, dynamic>.from(rawJob),
        ));
      } catch (_) {
        // A malformed journal entry cannot be resumed. Remove it so it does
        // not poison every future service startup.
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    entries.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    return [for (final entry in entries) entry.job];
  }

  Future<void> remove(String id) async {
    final file = File('${directory.path}/${_fileName(id)}.json');
    final temporary = File('${file.path}.tmp');
    for (final candidate in [file, temporary]) {
      try {
        if (await candidate.exists()) await candidate.delete();
      } catch (_) {}
    }
  }

  static String _fileName(String id) => base64Url.encode(utf8.encode(id));
}
