package com.pufy.app.ui.theme

import android.os.Build
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// iOS PufyTheme.swift'in karşılığı — sade siyah-beyaz (monokrom) tasarım. Açık temada ana renk siyah, koyuda beyaz.

@Immutable
data class PufyColors(
    val primary: Color,          // butonlar, seçili durumlar
    val onPrimary: Color,        // ana rengin üstündeki ikon/yazı
    val primaryDeep: Color,
    val indigo: Color,           // ikincil vurgu (nötr gri)
    val soft: Color,             // çip / rozet / seçili satır zemini
    val onSoft: Color,
    val reminder: Color,
    val userBubble: Color,
    val disabled: Color,
    val background: Color,       // systemBackground
    val secondaryBackground: Color,  // secondarySystemBackground
    val groupedBackground: Color,
    val text: Color,
    val secondaryText: Color,
    val tertiaryText: Color,
    val separator: Color,
    val glass: Color,            // cam zemini (bulanıklığın üstüne)
    val glassStroke: Color,
    val isDark: Boolean,
)

val LightPufy = PufyColors(
    primary = Color(0xFF111111), onPrimary = Color.White, primaryDeep = Color.Black, indigo = Color(0xFF48484A),
    soft = Color(0xFFF2F2F4), onSoft = Color(0xFF1C1C1E), reminder = Color(0xFF3A3A3C), userBubble = Color(0xFFF2F2F4),
    disabled = Color(0xFFD8D8DC), background = Color.White, secondaryBackground = Color(0xFFF2F2F7),
    groupedBackground = Color(0xFFF2F2F7), text = Color(0xFF111111), secondaryText = Color(0x993C3C43),
    tertiaryText = Color(0x4D3C3C43), separator = Color(0x243C3C43), glass = Color(0xBFFFFFFF),
    glassStroke = Color(0x14000000), isDark = false,
)

val DarkPufy = PufyColors(
    primary = Color(0xFFF2F2F2), onPrimary = Color(0xFF111111), primaryDeep = Color.White, indigo = Color(0xFFC7C7CC),
    soft = Color(0xFF2A2A2C), onSoft = Color(0xFFF2F2F7), reminder = Color(0xFFD1D1D6), userBubble = Color(0xFF2A2A2C),
    disabled = Color(0xFF3A3A3C), background = Color.Black, secondaryBackground = Color(0xFF1C1C1E),
    groupedBackground = Color.Black, text = Color(0xFFF2F2F2), secondaryText = Color(0x99EBEBF5),
    tertiaryText = Color(0x4DEBEBF5), separator = Color(0x99545458), glass = Color(0xB31C1C1E),
    glassStroke = Color(0x1FFFFFFF), isDark = true,
)

val LocalPufy = staticCompositionLocalOf { LightPufy }

object Pufy {
    val colors: PufyColors @Composable get() = LocalPufy.current
}

/** iOS SmoothSpring karşılıkları (response → stiffness, damping aynı) */
object Springs {
    private fun stiffness(response: Float) = (2 * Math.PI / response).let { (it * it).toFloat() }
    fun <T> quick() = spring<T>(dampingRatio = 0.78f, stiffness = stiffness(0.26f))
    fun <T> standard() = spring<T>(dampingRatio = 0.84f, stiffness = stiffness(0.36f))
    fun <T> gentle() = spring<T>(dampingRatio = 0.86f, stiffness = stiffness(0.46f))
    fun <T> snappy() = spring<T>(dampingRatio = 0.74f, stiffness = stiffness(0.26f))
    fun <T> press() = spring<T>(dampingRatio = 0.72f, stiffness = stiffness(0.22f))
    fun <T> interactive() = spring<T>(dampingRatio = 0.80f, stiffness = Spring.StiffnessHigh)
}

/** Yazı tipi: sistem yazı tipi (Android'de Roboto / Google Sans), iOS ölçeğine yakın boyutlar */
object PufyType {
    val font = FontFamily.Default
    val largeTitle = TextStyle(fontFamily = font, fontSize = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp)
    val title = TextStyle(fontFamily = font, fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp)
    val headline = TextStyle(fontFamily = font, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontFamily = font, fontSize = 17.sp, lineHeight = 24.sp)
    val callout = TextStyle(fontFamily = font, fontSize = 16.sp, lineHeight = 22.sp)
    val subheadline = TextStyle(fontFamily = font, fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontFamily = font, fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontFamily = font, fontSize = 12.sp, lineHeight = 16.sp)
}

@Composable
fun PufyTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) DarkPufy else LightPufy
    val scheme = if (dark) darkColorScheme(primary = colors.primary, onPrimary = colors.onPrimary, background = colors.background,
        surface = colors.background, onSurface = colors.text, onBackground = colors.text)
    else lightColorScheme(primary = colors.primary, onPrimary = colors.onPrimary, background = colors.background,
        surface = colors.background, onSurface = colors.text, onBackground = colors.text)
    CompositionLocalProvider(LocalPufy provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

val supportsBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
