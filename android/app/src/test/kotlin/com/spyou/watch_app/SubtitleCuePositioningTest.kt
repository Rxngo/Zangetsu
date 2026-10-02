package com.spyou.watch_app

import androidx.media3.common.text.Cue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [SubtitleCuePositioning].
 *
 * The bug (#119): every cue was forced onto the same line fraction, so two
 * subtitles presented in one cue group printed over each other. A lone cue must
 * still land on exactly the fraction it always did.
 */
class SubtitleCuePositioningTest {

    /** Any positive value works — the helper only uses it as a line height. */
    private val textSize = 0.05f

    private fun cue(text: String) = Cue.Builder().setText(text).build()

    private fun position(cues: List<Cue>, percent: Int = 95) =
        SubtitleCuePositioning.position(cues, percent, textSize)

    @Test
    fun singleCue_landsOnTheChosenPosition() {
        assertEquals(0.95f, position(listOf(cue("only"))).single().line, TOLERANCE)
    }

    @Test
    fun emptyList_isReturnedUntouched() {
        assertEquals(emptyList<Cue>(), position(emptyList()))
    }

    @Test
    fun cuesInOneGroup_areStackedInsteadOfOverprinted() {
        val result = position(listOf(cue("English"), cue("How did this happen?")))
        assertEquals(0.95f, result[0].line, TOLERANCE)
        assertNotEquals(result[0].line, result[1].line)
        // The second line sits ABOVE the first: an end-anchored cue moves up as
        // its fraction shrinks.
        assertTrue(result[1].line < result[0].line)
    }

    @Test
    fun threeCues_eachGetTheirOwnRow() {
        val lines = position(List(3) { cue("line $it") }).map { it.line }
        assertEquals(3, lines.toSet().size)
    }

    @Test
    fun stackHeightTracksTheAppliedTextSize() {
        val small = position(listOf(cue("a"), cue("b")), 95).let { it[0].line - it[1].line }
        val large = SubtitleCuePositioning
            .position(listOf(cue("a"), cue("b")), 95, 0.10f)
            .let { it[0].line - it[1].line }
        assertTrue("bigger text must stack further apart", large > small)
    }

    @Test
    fun stacksNeverClimbAboveTheTopMargin() {
        val result = position(List(12) { cue("line $it") }, percent = 40)
        result.forEach { assertTrue(it.line >= TOP_MARGIN - TOLERANCE) }
    }

    @Test
    fun positionIsClampedToTheScreenRange() {
        assertEquals(0f, position(listOf(cue("x")), percent = -50).single().line, TOLERANCE)
        assertEquals(1f, position(listOf(cue("x")), percent = 150).single().line, TOLERANCE)
    }

    private companion object {
        const val TOLERANCE = 0.0001f
        const val TOP_MARGIN = 0.02f
    }
}
