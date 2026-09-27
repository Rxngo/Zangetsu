package com.spyou.watch_app.aniyomi

import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SAnimeImpl
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import rx.Observable

/**
 * Guards the v16 -> v17 merge.
 *
 * A lib-17 extension must find the new API, and a lib-16 extension must keep
 * the v16 behaviour it has today. Both are asserted here because the failure
 * mode of getting it wrong is a runtime crash inside a prebuilt APK, which no
 * other test would catch.
 *
 * Implements [AnimeSource] rather than AnimeCatalogueSource: the latter is an
 * interface with four bodyless deprecated Rx members, none of which the merge
 * touches.
 */
class AnimeSourceV17CompatTest {

    /** Stands in for a prebuilt lib-16 extension: implements only the v16 surface. */
    private class V16OnlySource : AnimeSource {
        override val id = 1L
        override val name = "v16"
        override val lang = "en"
        override suspend fun getAnimeDetails(anime: SAnime) = anime
        override suspend fun getEpisodeList(anime: SAnime): List<SEpisode> = emptyList()
        override fun fetchVideoList(episode: SEpisode): Observable<List<Video>> =
            Observable.just(emptyList())
    }

    @Test
    fun `v16 getSeasonList default survives the merge`() = runBlocking {
        val anime = SAnimeImpl()
        // v17 replaced this default with a throw; the merge must keep ours.
        assertEquals(listOf(anime), V16OnlySource().getSeasonList(anime))
    }

    @Test
    fun `v16 getVideoList delegation chain survives the merge`() = runBlocking {
        // Proves the real v16 body (fetchVideoList().awaitSingle()) is still in
        // place. A v17 throwing stub could not produce an empty list at all.
        assertEquals(emptyList<Video>(), V16OnlySource().getVideoList(SEpisode.create()))
    }

    @Test
    fun `new v17 members are not abstract and fail cleanly`() = runBlocking {
        val src = V16OnlySource()
        val anime = SAnimeImpl()
        assertUnsupported("getAnimeEpisodeUpdate") {
            src.getAnimeEpisodeUpdate(anime, emptyList(), true, true)
        }
        assertUnsupported("getAnimeSeasonUpdate") {
            src.getAnimeSeasonUpdate(anime, emptyList(), true, true)
        }
        assertUnsupported("getRelatedAnimeList") {
            src.getRelatedAnimeList(anime)
        }
    }

    @Test
    fun `supportsRelatedAnime defaults to false`() {
        assertFalse(V16OnlySource().supportsRelatedAnime)
    }

    private inline fun assertUnsupported(name: String, block: () -> Unit) {
        val failure = runCatching(block).exceptionOrNull()
        assertTrue(
            "$name should throw UnsupportedOperationException, got $failure",
            failure is UnsupportedOperationException,
        )
    }
}
