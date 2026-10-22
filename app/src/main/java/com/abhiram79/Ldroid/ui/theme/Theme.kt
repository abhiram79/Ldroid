/*
 * Ldroid Compose theme.
 *
 * Default identity: fixed dark/light palette derived from LdroidTokens, with
 * a lime-green accent (#4ade80). Material You wallpaper-derived dynamic color
 * is OFF by default — users opt in via Settings → Appearance → Dynamic color,
 * which flows in via the dynamicColor parameter.
 */
package com.abhiram79.Ldroid.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val LdroidDark = darkColorScheme(
    primary             = LdroidAccent,
    onPrimary           = LdroidAccentInk,
    primaryContainer    = LdroidDarkSurface2,
    onPrimaryContainer  = LdroidDarkText,

    secondary           = LdroidAccent,
    onSecondary         = LdroidAccentInk,
    secondaryContainer  = LdroidDarkSurface2,
    onSecondaryContainer= LdroidDarkText,

    tertiary            = LdroidAmber,
    onTertiary          = LdroidAccentInk,

    background          = LdroidDarkBg,
    onBackground        = LdroidDarkText,
    surface             = LdroidDarkSurface,
    onSurface           = LdroidDarkText,
    surfaceVariant      = LdroidDarkSurface2,
    onSurfaceVariant    = LdroidDarkTextMute,
    surfaceContainerHighest = LdroidDarkSurface2,

    outline             = LdroidDarkBorder,
    outlineVariant      = LdroidDarkBorder,

    error               = LdroidRed,
    onError             = LdroidDarkText,
    errorContainer      = LdroidDarkSurface2,
    onErrorContainer    = LdroidRed,
)

private val LdroidLight = lightColorScheme(
    primary             = LdroidAccent,
    onPrimary           = LdroidAccentInk,
    primaryContainer    = LdroidLightSurface2,
    onPrimaryContainer  = LdroidLightText,

    secondary           = LdroidAccent,
    onSecondary         = LdroidAccentInk,
    secondaryContainer  = LdroidLightSurface2,
    onSecondaryContainer= LdroidLightText,

    tertiary            = LdroidAmber,
    onTertiary          = LdroidLightText,

    background          = LdroidLightBg,
    onBackground        = LdroidLightText,
    surface             = LdroidLightSurface,
    onSurface           = LdroidLightText,
    surfaceVariant      = LdroidLightSurface2,
    onSurfaceVariant    = LdroidLightTextMute,
    surfaceContainerHighest = LdroidLightSurface2,

    outline             = LdroidLightBorder,
    outlineVariant      = LdroidLightBorder,

    error               = LdroidRed,
    onError             = LdroidLightText,
    errorContainer      = LdroidLightSurface2,
    onErrorContainer    = LdroidRed,
)

@Composable
fun LdroidTheme(
    darkTheme: Boolean? = null,
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val effectiveDark = darkTheme ?: isSystemInDarkTheme()
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (effectiveDark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        effectiveDark -> LdroidDark
        else          -> LdroidLight
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography  = buildLdroidTypography(),
        content     = content,
    )
}
