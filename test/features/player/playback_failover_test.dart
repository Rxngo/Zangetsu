import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/features/player/playback_failover.dart';

VideoSource _source(String id, String quality, AudioKind kind) => VideoSource(
  url: 'https://example.test/$id',
  quality: quality,
  container: SourceContainer.hls,
  kind: kind,
);

void main() {
  test('late mirrors are collected without dropping the first link', () async {
    var pollCount = 0;
    final initial = [_source('first', '720p', AudioKind.sub)];

    final result = await collectLatePlaybackMirrors(
      initial: initial,
      poll: () async {
        pollCount++;
        return (
          sources: [
            _source('first', '720p', AudioKind.sub),
            if (pollCount > 1) _source('preferred', '1080p', AudioKind.sub),
          ],
          done: pollCount > 1,
        );
      },
      maxWait: const Duration(seconds: 1),
      pollInterval: Duration.zero,
    );

    expect(result.map((source) => source.url), [
      'https://example.test/first',
      'https://example.test/preferred',
    ]);
  });

  test('startup fallback preserves audio cut and saved quality preference', () {
    final failed = _source('failed', '720p', AudioKind.sub);
    final fallback = pickPlaybackFallback(
      failed: failed,
      sources: [
        _source('dub-1080', '1080p', AudioKind.dub),
        _source('sub-480', '480p', AudioKind.sub),
        _source('sub-720', '720p', AudioKind.sub),
      ],
      triedUrls: {failed.url},
      preferredQuality: '720p',
    );

    expect(fallback?.url, 'https://example.test/sub-720');
    expect(fallback?.kind, AudioKind.sub);
  });

  test('unknown-audio mirrors may be used but known opposite cuts may not', () {
    final failed = _source('failed', '720p', AudioKind.sub);
    final fallback = pickPlaybackFallback(
      failed: failed,
      sources: [
        _source('dub', '1080p', AudioKind.dub),
        _source('unknown', '480p', AudioKind.unknown),
      ],
      triedUrls: {failed.url},
      preferredQuality: 'highest',
    );

    expect(fallback?.url, 'https://example.test/unknown');
    expect(fallback?.kind, AudioKind.unknown);
  });
}
