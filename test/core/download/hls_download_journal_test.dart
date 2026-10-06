import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/hls_download_journal.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hls-download-journal');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('pending HLS jobs survive a journal restart until removed', () async {
    final job = <String, dynamic>{
      'id': 'source_show_episode',
      'url': 'https://cdn.example/video.m3u8?token=private',
      'headers': {'Referer': 'https://source.example/'},
      'outputPath': '/private/video.ts',
    };

    await HlsDownloadJournal(directory).save(job);

    final restored = await HlsDownloadJournal(directory).pending();
    expect(restored, [job]);

    await HlsDownloadJournal(directory).remove(job['id'] as String);
    expect(await HlsDownloadJournal(directory).pending(), isEmpty);
  });
}
