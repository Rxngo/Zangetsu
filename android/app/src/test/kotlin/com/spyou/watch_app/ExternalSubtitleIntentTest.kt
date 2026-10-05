package com.spyou.watch_app

import android.content.Intent
import android.net.Uri
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ExternalSubtitleIntentTest {
    @Test
    fun localSubtitlePathsAreSharedWhileRemoteTracksRemainRemote() {
        val sharedPaths = mutableListOf<String>()
        val tracks = resolveExternalSubtitleTracks(
            listOf(
                mapOf(
                    "url" to "/data/user/0/com.spyou.watch_app/app_flutter/subs/en.vtt",
                    "name" to "English",
                    "default" to "true",
                ),
                mapOf(
                    "url" to "https://cdn.example.test/subs/ja.vtt",
                    "name" to "Japanese",
                    "default" to "false",
                ),
            ),
        ) { path ->
            sharedPaths += path
            Uri.parse("content://com.spyou.watch_app.videoprovider/cache/${path.substringAfterLast('/')}")
        }

        assertEquals(
            listOf("/data/user/0/com.spyou.watch_app/app_flutter/subs/en.vtt"),
            sharedPaths,
        )
        assertEquals("content", tracks[0].uri.scheme)
        assertEquals("English", tracks[0].name)
        assertTrue(tracks[0].fromLocalFile)
        assertTrue(tracks[0].isDefault)
        assertEquals("https://cdn.example.test/subs/ja.vtt", tracks[1].uri.toString())
        assertFalse(tracks[1].fromLocalFile)
    }

    @Test
    fun sidecarIsCopiedIntoShareCacheAndKeepsItsFormatExtension() {
        val root = Files.createTempDirectory("subtitle-share-test").toFile()
        try {
            val source = File(root, "downloaded/en.vtt")
            source.parentFile!!.mkdirs()
            source.writeText("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello")
            val cache = File(root, "cache")

            val sharedUri = stageSubtitleFile(source.path, cache) { stagedPath ->
                val staged = File(stagedPath)
                assertTrue(staged.isFile)
                assertEquals("external_subtitle_shares", staged.parentFile!!.name)
                assertEquals("vtt", staged.extension)
                assertEquals(source.readText(), staged.readText())
                Uri.parse("content://com.spyou.watch_app.videoprovider/cache/${staged.name}")
            }

            assertEquals("content", sharedUri!!.scheme)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun intentCarriesAllSubtitleUrisAndGrantsLocalFileReadAccess() {
        val english = ExternalSubtitleTrack(
            uri = Uri.parse("content://com.spyou.watch_app.videoprovider/cache/en.vtt"),
            name = "English",
            isDefault = false,
            fromLocalFile = true,
        )
        val japanese = ExternalSubtitleTrack(
            uri = Uri.parse("content://com.spyou.watch_app.videoprovider/cache/ja.vtt"),
            name = "Japanese",
            isDefault = true,
            fromLocalFile = true,
        )
        val intent = Intent()

        attachExternalSubtitles(intent, listOf(english, japanese))

        val subtitleUris = intent.getParcelableArrayExtra("subs")!!.map { it as Uri }
        assertEquals(listOf(english.uri, japanese.uri), subtitleUris)
        assertArrayEquals(arrayOf("English", "Japanese"), intent.getStringArrayExtra("subs.name"))
        assertEquals(
            listOf(japanese.uri),
            intent.getParcelableArrayExtra("subs.enable")!!.map { it as Uri },
        )
        assertEquals(japanese.uri.toString(), intent.getStringExtra("subtitles_location"))
        assertNotNull(intent.clipData)
        assertEquals(2, intent.clipData!!.itemCount)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
    }

    @Test
    fun streamedSubtitlesKeepExistingExtrasAndReadGrant() {
        val remote = ExternalSubtitleTrack(
            uri = Uri.parse("https://cdn.example.test/subs/en.vtt"),
            name = "English",
            isDefault = true,
            fromLocalFile = false,
        )
        val intent = Intent()
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        attachExternalSubtitles(intent, listOf(remote))

        assertEquals(listOf(remote.uri), intent.getParcelableArrayExtra("subs")!!.map { it as Uri })
        assertEquals("https://cdn.example.test/subs/en.vtt", intent.getStringExtra("subtitles_location"))
        assertEquals(null, intent.getParcelableArrayExtra("subs.enable"))
        assertEquals(null, intent.clipData)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
    }
}
