package com.pufy.app.ui.components

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import com.pufy.app.R
import com.pufy.app.ui.theme.Pufy

/** iOS ShimmerText: soluk yazının üstünden soldan sağa ışık geçer */
@Composable
fun ShimmerText(text: String, style: TextStyle, modifier: Modifier = Modifier) {
    val c = Pufy.colors
    val phase by rememberInfiniteTransition(label = "shimmer").animateFloat(
        -0.6f, 1.1f, infiniteRepeatable(tween(1200, easing = LinearEasing)), label = "phase")
    Box(modifier) {
        Text(text, style = style, color = c.tertiaryText)
        Text(text, style = style, color = c.text, modifier = Modifier
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val w = size.width
                val band = maxOf(w * 0.55f, 40f)
                val start = phase * w
                drawRect(
                    Brush.horizontalGradient(listOf(Color.Transparent, Color.Black, Color.Transparent), startX = start, endX = start + band),
                    blendMode = BlendMode.DstIn,
                )
            })
    }
}

/** Yükleniyor iskeleti: üzerinden ışık geçen yumuşak kutu */
@Composable
fun ShimmerBox(modifier: Modifier = Modifier) {
    val c = Pufy.colors
    val phase by rememberInfiniteTransition(label = "skeleton").animateFloat(
        -1f, 2f, infiniteRepeatable(tween(1400, easing = LinearEasing)), label = "p")
    Box(modifier.background(c.secondaryBackground).drawWithContent {
        drawContent()
        val w = size.width
        drawRect(Brush.linearGradient(
            listOf(Color.Transparent, c.text.copy(alpha = if (c.isDark) 0.07f else 0.05f), Color.Transparent),
            start = Offset(phase * w, 0f), end = Offset(phase * w + w * 0.6f, size.height)))
    })
}

/** iOS SpinningPufyIconView: nefes alan Pufy simgesi */
@Composable
fun PulsingPufy(modifier: Modifier = Modifier) {
    val t = rememberInfiniteTransition(label = "pulse")
    val s by t.animateFloat(0.92f, 1.08f, infiniteRepeatable(tween(1000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "s")
    val a by t.animateFloat(0.7f, 1f, infiniteRepeatable(tween(1000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "a")
    Image(painterResource(R.drawable.chat_pp), null, contentScale = ContentScale.Crop,
        modifier = modifier.graphicsLayer { scaleX = s; scaleY = s; alpha = a }.clip(CircleShape))
}
