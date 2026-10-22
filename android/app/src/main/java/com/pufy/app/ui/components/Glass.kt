package com.pufy.app.ui.components

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.Springs
import com.pufy.app.ui.theme.supportsBlur
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

// iOS "Liquid Glass" karşılığı: içeriğin üstünde yüzen kontroller (üst bar, mesaj kutusu, yüzen butonlar) arkadaki içeriği
// bulanık gösteren cam yüzeydir. Android 12+ gerçek bulanıklık (Haze), öncesinde yarı saydam dolgu.
// Kural (Apple HIG ile aynı): içeriğin kendisi (mesajlar, kartlar) cam olmaz; cam üstüne cam konmaz.

val LocalHaze = compositionLocalOf<HazeState?> { null }

fun Modifier.pufyGlass(shape: Shape, tint: Color? = null, shadow: Boolean = true): Modifier = composed {
    val c = Pufy.colors
    val haze = LocalHaze.current
    var m = this
    if (shadow) m = m.shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.10f))
    m = m.clip(shape)
    m = if (haze != null && supportsBlur) {
        m.hazeEffect(state = haze, style = HazeStyle(
            backgroundColor = c.background,
            tints = listOf(HazeTint(tint?.copy(alpha = 0.85f) ?: c.glass.copy(alpha = if (c.isDark) 0.55f else 0.62f))),
            blurRadius = 22.dp,
            noiseFactor = 0f,
        ))
    } else {
        m.background(tint ?: c.glass.copy(alpha = 0.94f))
    }
    m.border(0.5.dp, c.glassStroke, shape)
}

/** iOS PremiumScaleButtonStyle: basınca hafif küçülür ve solar (yaylı) */
fun Modifier.pressable(
    enabled: Boolean = true,
    scale: Float = 0.97f,
    haptic: Boolean = true,
    onClick: () -> Unit,
): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) scale else 1f, Springs.press(), label = "press")
    val a by animateFloatAsState(if (pressed) 0.85f else 1f, Springs.press(), label = "pressAlpha")
    val view = LocalView.current
    this
        .graphicsLayer { scaleX = s; scaleY = s; alpha = a }
        .clickable(interaction, indication = null, enabled = enabled) {
            if (haptic) view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
            onClick()
        }
}

@Composable
fun GlassIconButton(icon: ImageVector, contentDescription: String, size: Dp = 44.dp, iconSize: Dp = 18.dp,
                    tint: Color = Pufy.colors.text, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier.size(size).pufyGlass(CircleShape).pressable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, contentDescription, Modifier.size(iconSize), tint = tint) }
}

object Haptics {
    fun light(view: android.view.View) = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun medium(view: android.view.View) = view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
    fun success(view: android.view.View) = view.performHapticFeedback(
        if (android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK)
}
