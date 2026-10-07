import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/download_manager.dart';
import 'package:watch_app/core/models/video_source.dart';

VideoSource _source(
  String url, {
  AudioKind kind = AudioKind.unknown,
  String? audioLang,
}) => VideoSource(url: url, kind: kind, audioLang: audioLang);

void main() {
  test('keeps all links matching the requested cut and their languages', () {
    final sources = [
      _source('sub-1080', kind: AudioKind.sub, audioLang: 'en'),
      VideoSource(
        url: 'dub-hindi-720',
        kind: AudioKind.dub,
        audioLang: 'hi',
        subtitles: const [Subtitle(url: 'dub-hindi.vtt', lang: 'en')],
      ),
      _source('dub-english-1080', kind: AudioKind.dub, audioLang: 'en'),
    ];

    final selected = DownloadManager.sourcesForDownloadCategory(sources, 'dub');

    expect(selected.map((source) => source.url), [
      'dub-hindi-720',
      'dub-english-1080',
    ]);
    expect(selected.map((source) => source.audioLang), ['hi', 'en']);
    expect(selected.first.subtitles.single.url, 'dub-hindi.vtt');
  });

  test('preserves unlabelled language links when no cut metadata is given', () {
    final sources = [
      _source('hindi', audioLang: 'hi'),
      _source('english', audioLang: 'en'),
    ];

    expect(
      DownloadManager.sourcesForDownloadCategory(sources, 'dub'),
      same(sources),
    );
  });

  test('leaves a single-cut source list unchanged', () {
    final sources = [_source('sub', kind: AudioKind.sub)];

    expect(
      DownloadManager.sourcesForDownloadCategory(sources, 'dub'),
      same(sources),
    );
  });
}
