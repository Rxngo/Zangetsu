import '../../core/download/download_record.dart';
import '../../core/models/episode.dart';
import '../../core/models/video_source.dart';

({List<Episode> episodes, int startIndex}) downloadedEpisodePlaybackQueue({
  required DownloadRecord record,
  List<Episode>? episodes,
  int startIndex = 0,
}) {
  if (episodes == null || episodes.isEmpty) {
    return (
      episodes: [
        Episode(
          id: record.episodeId,
          title: record.episodeTitle,
          number: record.episodeNumber,
          url: record.episodeUrl,
        ),
      ],
      startIndex: 0,
    );
  }
  return (
    episodes: episodes,
    startIndex: startIndex.clamp(0, episodes.length - 1),
  );
}

VideoSource downloadedVideoSource(DownloadRecord record) {
  final path = record.filePath;
  if (path == null || path.isEmpty) {
    throw ArgumentError.value(record.filePath, 'record.filePath');
  }
  return VideoSource(
    url: path,
    container: SourceContainer.mp4,
    subtitles: [
      for (final subtitle in record.subtitles)
        Subtitle(
          url: subtitle.path,
          lang: subtitle.lang,
          label: subtitle.label,
          isDefault: subtitle.isDefault,
        ),
    ],
  );
}
