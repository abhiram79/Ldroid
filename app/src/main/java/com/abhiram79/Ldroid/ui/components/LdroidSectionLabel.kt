package com.abhiram79.Ldroid.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.abhiram79.Ldroid.ui.theme.LdroidTokens

/**
 * Tiny uppercase tracked label used as a section heading throughout the app.
 * Pairs naturally with LdroidListRow groups.
 */
@Composable
fun LdroidSectionLabel(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontFamily = LdroidTokens.ui(),
        fontWeight = FontWeight.Medium,
        modifier = modifier
            .padding(top = LdroidTokens.Spacing.LG, bottom = LdroidTokens.Spacing.XS),
    )
}
