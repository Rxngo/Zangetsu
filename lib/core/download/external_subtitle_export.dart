/// Private videos must never get a public subtitle sidecar.
bool shouldExportSubtitleSidecars({
  required String videoPath,
  required String privateStorageRoot,
}) {
  final root = privateStorageRoot.endsWith('/')
      ? privateStorageRoot
      : '$privateStorageRoot/';
  return videoPath != privateStorageRoot && !videoPath.startsWith(root);
}

/// Names an exported sidecar so local players can associate it with [videoPath].
String externalSubtitleFileName({
  required String videoPath,
  required String language,
  required String extension,
}) {
  var videoPathPart = Uri.tryParse(videoPath)?.path ?? videoPath;
  try {
    videoPathPart = Uri.decodeComponent(videoPathPart);
  } on FormatException {
    // Keep the original path when a content URI contains a malformed escape.
  }
  final videoName = videoPathPart.split(RegExp(r'[/\\]')).last;
  final dot = videoName.lastIndexOf('.');
  final stem = dot > 0 ? videoName.substring(0, dot) : videoName;
  final safeLanguage = language.trim().replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  final safeExtension = extension.startsWith('.') ? extension : '.$extension';
  return '$stem.${safeLanguage.isEmpty ? 'sub' : safeLanguage}$safeExtension';
}

/// MX Player and many file-browser players reliably scan SRT sidecars.
/// Preserve the original subtitle in app-private storage; only the public
/// copy is converted when its source format is WebVTT.
String publicSubtitleExtension(String sourcePath) {
  final dot = sourcePath.lastIndexOf('.');
  if (dot < 0) return '.srt';
  final extension = sourcePath.substring(dot).toLowerCase();
  return extension == '.vtt' ? '.srt' : extension;
}

/// Converts simple WebVTT cues to SRT for players that do not scan VTT files.
/// Cue text (including inline tags) is preserved; WebVTT cue settings are
/// dropped because SRT has no equivalent.
String webVttToSrt(String webVtt) {
  final normalized = webVtt
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final blocks = normalized.split(RegExp(r'\n\s*\n+'));
  final cues = <String>[];
  final timing = RegExp(
    r'^((?:\d+:)?\d{1,2}:\d{2})[.,](\d{1,3})\s*-->\s*'
    r'((?:\d+:)?\d{1,2}:\d{2})[.,](\d{1,3})(?:\s+.*)?$',
  );

  for (final rawBlock in blocks) {
    final lines = rawBlock.split('\n');
    while (lines.isNotEmpty &&
        (lines.first.trim().startsWith('WEBVTT') ||
            lines.first.trim().startsWith('X-TIMESTAMP-MAP'))) {
      lines.removeAt(0);
    }
    if (lines.isEmpty ||
        lines.first.trim().startsWith('NOTE') ||
        lines.first.trim() == 'STYLE' ||
        lines.first.trim() == 'REGION') {
      continue;
    }

    final timingIndex = lines.indexWhere(
      (line) => timing.hasMatch(line.trim()),
    );
    if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
    final match = timing.firstMatch(lines[timingIndex].trim())!;
    final body = lines.skip(timingIndex + 1).join('\n').trimRight();
    if (body.trim().isEmpty) continue;
    cues.add(
      '${cues.length + 1}\n'
      '${_srtTimestamp(match.group(1)!, match.group(2)!)} --> '
      '${_srtTimestamp(match.group(3)!, match.group(4)!)}\n'
      '$body',
    );
  }

  return cues.isEmpty ? '' : '${cues.join('\n\n')}\n';
}

String _srtTimestamp(String clock, String milliseconds) {
  final parts = clock.split(':').map((part) => part.padLeft(2, '0')).toList();
  if (parts.length == 2) parts.insert(0, '00');
  final ms = milliseconds.padRight(3, '0').substring(0, 3);
  return '${parts.join(':')},$ms';
}
