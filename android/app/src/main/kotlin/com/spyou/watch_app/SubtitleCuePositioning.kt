package com.spyou.watch_app

import androidx.media3.common.text.Cue

/**
 * Places cues at the viewer's vertical preference WITHOUT collapsing the cues of
 * one cue group onto the same line.
 *
 * The viewer's Position setting has to force a line, because Media3's
 * `SubtitleView.setBottomPaddingFraction` only shifts cues that leave their line
 * unset and most VTT/SRT cues set their own. But Media3 also only stacks cues
 * vertically for cues with NO line — forcing the same line onto every cue is what
 * made two subtitles presented together print over each other (#119), so a
 * two-speaker line looked like one cluttered row.
 *
 * `CueGroup` only carries a presentation time, never per-cue timings, so there is
 * nothing to overlap-test: a group's cues are by construction on screen at the
 * same instant. They therefore stack by position in the group, which is what
 * Media3's own renderer does once a line is set. The first cue keeps the chosen
 * position, so a lone subtitle lands on exactly the fraction it always did.
 */
internal object SubtitleCuePositioning {

    /** Gap left above the view before a stacked cue is clamped against the top. */
    private const val TOP_MARGIN = 0.02f

    /** A stacked neighbour needs a full text height plus a little air. */
    private const val LINE_SPACING = 1.2f

    /**
     * @param positionPercent the viewer's 0..100 vertical preference; 95 is the
     *   existing "Low" default.
     * @param textSizeFraction the fractional text size actually applied to the
     *   subtitle view, used as the height of one line.
     */
    fun position(cues: List<Cue>, positionPercent: Int, textSizeFraction: Float): List<Cue> {
        if (cues.isEmpty()) return cues
        val base = positionPercent.coerceIn(0, 100) / 100f
        // Clamped so a large Font Size setting cannot step a cue off-screen or
        // collapse every stack onto the top margin.
        val step = (textSizeFraction * LINE_SPACING).coerceIn(0.01f, 0.2f)
        return cues.mapIndexed { index, cue ->
            // Only STACKED cues are clamped. Clamping the first one too would
            // move a lone subtitle off the fraction it has always landed on.
            val line = if (index == 0) base else (base - index * step).coerceAtLeast(TOP_MARGIN)
            cue.buildUpon()
                .setLine(line, Cue.LINE_TYPE_FRACTION)
                .setLineAnchor(Cue.ANCHOR_TYPE_END)
                .build()
        }
    }
}
