package com.spyou.watch_app

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import java.io.File

internal data class ExternalSubtitleTrack(
    val uri: Uri,
    val name: String,
    val isDefault: Boolean,
    val fromLocalFile: Boolean,
)

internal fun stageSubtitleFile(
    path: String,
    cacheDirectory: File,
    createContentUri: (String) -> Uri?,
): Uri? {
    val source = File(path)
    if (!source.isFile) return null

    val shareDirectory = File(cacheDirectory, "external_subtitle_shares")
    if (!shareDirectory.exists() && !shareDirectory.mkdirs()) return null
    val staleBefore = System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000
    shareDirectory.listFiles()
        ?.filter { it.isFile && it.lastModified() < staleBefore }
        ?.forEach(File::delete)

    val extension = source.extension
        .takeIf { it.isNotBlank() && it.length <= 8 && it.all(Char::isLetterOrDigit) }
        ?.let { ".${it.lowercase()}" }
        ?: ".sub"
    val staged = File(shareDirectory, "${java.util.UUID.randomUUID()}$extension")
    return try {
        source.copyTo(staged)
        createContentUri(staged.path) ?: run {
            staged.delete()
            null
        }
    } catch (_: Exception) {
        staged.delete()
        null
    }
}

internal fun resolveExternalSubtitleTracks(
    subtitles: List<Map<String, String>>?,
    shareLocalFile: (String) -> Uri?,
): List<ExternalSubtitleTrack> = subtitles.orEmpty().mapNotNull { subtitle ->
    val rawUrl = subtitle["url"]?.takeIf(String::isNotBlank) ?: return@mapNotNull null
    val parsed = Uri.parse(rawUrl)
    val isLocalFile = parsed.scheme.isNullOrBlank() || parsed.scheme.equals("file", ignoreCase = true)
    val uri = if (isLocalFile) {
        val path = if (parsed.scheme.equals("file", ignoreCase = true)) {
            parsed.path ?: return@mapNotNull null
        } else {
            rawUrl
        }
        shareLocalFile(path) ?: return@mapNotNull null
    } else {
        parsed
    }

    ExternalSubtitleTrack(
        uri = uri,
        name = subtitle["name"]?.takeIf(String::isNotBlank) ?: "Subtitle",
        isDefault = subtitle["default"] == "true",
        fromLocalFile = isLocalFile,
    )
}

/** Adds player-compatible subtitle extras and grants access to local sidecars. */
internal fun attachExternalSubtitles(
    intent: Intent,
    tracks: List<ExternalSubtitleTrack>,
) {
    if (tracks.isEmpty()) return

    intent.putExtra("subs", tracks.map { it.uri }.toTypedArray())
    intent.putExtra("subs.name", tracks.map { it.name }.toTypedArray())
    // VLC accepts one subtitle location; preserve first-track behavior for
    // streams and prefer the selected default for downloaded sidecars.
    intent.putExtra("subtitles_location", tracks.first().uri.toString())

    val localTracks = tracks.filter(ExternalSubtitleTrack::fromLocalFile)
    if (localTracks.isEmpty()) return

    val selected = localTracks.firstOrNull(ExternalSubtitleTrack::isDefault)
        ?: localTracks.first()
    intent.putExtra("subs.enable", arrayOf(selected.uri))
    intent.putExtra("subtitles_location", selected.uri.toString())

    val clipData = ClipData.newRawUri(localTracks.first().name, localTracks.first().uri)
    localTracks.drop(1).forEach { track ->
        clipData.addItem(ClipData.Item(track.uri))
    }
    intent.clipData = clipData
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
}
