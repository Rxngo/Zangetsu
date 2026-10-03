package com.spyou.watch_app

import android.graphics.Typeface
import android.os.Build
import java.io.File

/**
 * Typeface for subtitles that never turns a script the chosen font doesn't
 * cover into boxes (Arabic #128): the custom font first, the system font
 * behind it, so a missing glyph falls through instead of rendering as tofu.
 * Plain system default when no custom font is set — that already covers
 * every script, which is why the default never had this bug.
 *
 * The fallback chain needs API 29; older devices keep today's bare custom
 * font (same behaviour as now, no regression).
 */
internal fun subtitleTypeface(fontPath: String?): Typeface {
    if (fontPath.isNullOrBlank()) return Typeface.DEFAULT
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        return runCatching { Typeface.createFromFile(fontPath) }
            .getOrNull() ?: Typeface.DEFAULT
    }
    return runCatching {
        val family = android.graphics.fonts.FontFamily.Builder(
            android.graphics.fonts.Font.Builder(File(fontPath)).build(),
        ).build()
        Typeface.CustomFallbackBuilder(family)
            .setSystemFallback("sans-serif")
            .build()
    }.getOrNull()
        ?: runCatching { Typeface.createFromFile(fontPath) }.getOrNull()
        ?: Typeface.DEFAULT
}
