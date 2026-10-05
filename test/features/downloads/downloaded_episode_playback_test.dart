import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/features/downloads/downloaded_episode_playback.dart';

void main() {
  const record = DownloadRecord(
    id: 'show-e2',
    sourceId: 'source',
    showId: 'show',
    showTitle: 'Show',
    showUrl: '/show',
    episodeId: 'e2',
    episodeUrl: '/e2',
    episodeTitle: 'Episode 2',
    category: 'sub',
    quality: '1080p',
    status: DownloadStatus.done,
    filePath: '/downloads/e2.mp4',
    createdAt: 0,
  );

  test('downloaded detail playback preserves the full episode queue', () {
    const episodes = [
      Episode(id: 'e1', title: 'Episode 1', url: '/e1', number: 1),
      Episode(id: 'e2', title: 'Episode 2', url: '/e2', number: 2),
      Episode(id: 'e3', title: 'Episode 3', url: '/e3', number: 3),
    ];

    final queue = downloadedEpisodePlaybackQueue(
      record: record,
      episodes: episodes,
      startIndex: 1,
    );

    expect(queue.episodes, episodes);
    expect(queue.startIndex, 1);
  });

  test('Downloads playback defaults to the selected episode only', () {
    final queue = downloadedEpisodePlaybackQueue(record: record);

    expect(queue.episodes, hasLength(1));
    expect(queue.episodes.single.id, 'e2');
    expect(queue.startIndex, 0);
  });

  test('a downloaded source points directly at the saved file', () {
    final source = downloadedVideoSource(record);

    expect(source.url, '/downloads/e2.mp4');
    expect(source.container, SourceContainer.mp4);
  });
}
