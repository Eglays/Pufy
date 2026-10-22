package com.pufy.app.ui.chat

import android.content.Context
import android.content.Intent
import android.graphics.pdf.PdfDocument
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import coil3.compose.AsyncImage
import com.pufy.app.R
import com.pufy.app.core.TR
import com.pufy.app.core.turkeyFormat
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import java.io.File
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.sin

// iOS SlideView / SlideTheme / SlidePattern / SlideDeckViewer karşılığı. Slayt 360x450 mantıksal boyutta çizilip ölçeklenir.

private const val SLIDE_W = 360f
private const val SLIDE_H = 450f

class SlideTheme(val bg: Color, val surface: Color, val ink: Color, val muted: Color, val accent: Color, val onAccent: Color,
                 val hero: Color, val heroInk: Color, val heroAccent: Color) {
    companion object {
        private val palettes = mapOf(
            "mono" to longArrayOf(0xF2F2F4, 0xFFFFFF, 0x111111, 0x111111, 0x111111, 0xFFFFFF),
            "ocean" to longArrayOf(0xEDF3FA, 0xFFFFFF, 0x0F2238, 0x1F6FD1, 0x0E2A47, 0xFFFFFF),
            "forest" to longArrayOf(0xEEF5EE, 0xFFFFFF, 0x15291A, 0x2E7D4F, 0x173B26, 0xF3F8F1),
            "sunset" to longArrayOf(0xFBF0E7, 0xFFFFFF, 0x2B1A10, 0xE0622A, 0x6E2A12, 0xFFF4EC),
            "sand" to longArrayOf(0xF6EFE2, 0xFFFDF8, 0x2E2618, 0xA87A2C, 0x3A2F1D, 0xF8F1E2),
            "slate" to longArrayOf(0xEDF0F3, 0xFFFFFF, 0x1B2430, 0x3E6385, 0x1B2430, 0xF1F4F7),
            "crimson" to longArrayOf(0xF8EDED, 0xFFFFFF, 0x2A1214, 0xC2272D, 0x5E1216, 0xFFF1F1),
            "teal" to longArrayOf(0xEBF5F4, 0xFFFFFF, 0x0F2A2A, 0x128A82, 0x0D3B39, 0xEFFAF9),
            "gold" to longArrayOf(0xFFF8E3, 0xFFFFFF, 0x1F2A44, 0xD49A00, 0x1F2A44, 0xFFE27A),
            "midnight" to longArrayOf(0x111624, 0x1B2233, 0xEEF1F7, 0xF2B53C, 0x070A12, 0xFFFFFF),
        )
        private fun rgb(v: Long) = Color(0xFF000000 or v)
        private fun comps(v: Long) = Triple(((v shr 16) and 0xFF) / 255.0, ((v shr 8) and 0xFF) / 255.0, (v and 0xFF) / 255.0)
        fun luminance(v: Long) = comps(v).let { (r, g, b) -> 0.299 * r + 0.587 * g + 0.114 * b }
        private fun usable(v: Long, onDark: Boolean): Boolean {
            val (r, g, b) = comps(v); val mx = maxOf(r, g, b); val mn = minOf(r, g, b)
            if (mx - mn > 0.15) {
                var hue = when (mx) { r -> (g - b) / (mx - mn); g -> 2 + (b - r) / (mx - mn); else -> 4 + (r - g) / (mx - mn) } * 60
                if (hue < 0) hue += 360
                if (hue in 255.0..345.0) return false        // mor/pembe kullanılmaz
            }
            val lum = luminance(v)
            return if (onDark) lum > 0.35 else lum < 0.72
        }

        fun resolve(deck: JsonObject): SlideTheme {
            val key = deck.s("theme")?.lowercase() ?: ""
            val p = palettes[key] ?: palettes.getValue("mono")
            var accentHex = p[3]
            deck.s("accent")?.trim('#', ' ')?.takeIf { it.length == 6 }?.toLongOrNull(16)?.let { if (usable(it, key == "midnight")) accentHex = it }
            val contrast = abs(luminance(accentHex) - luminance(p[4]))
            val heroAccent = if (key != "mono" && contrast > 0.28) rgb(accentHex) else rgb(p[5]).copy(alpha = 0.75f)
            return SlideTheme(rgb(p[0]), rgb(p[1]), rgb(p[2]), rgb(p[2]).copy(alpha = 0.6f), rgb(accentHex),
                if (luminance(accentHex) > 0.55) Color(0xFF111111) else Color.White, rgb(p[4]), rgb(p[5]), heroAccent)
        }
    }
}

@Composable
private fun SlidePattern(kind: String, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.width; val h = size.height; val u = density
        when (kind) {
            "dots" -> {
                val step = 16 * u; var y = 10 * u
                while (y < h) { var x = 10 * u
                    while (x < w) { val fade = maxOf(0f, 1 - hypot(w - x, y) / (w * 0.95f))
                        if (fade > 0.02f) drawCircle(color.copy(alpha = 0.10f + 0.35f * fade), (1.2f + 1.6f * fade) * u, Offset(x, y)); x += step }
                    y += step }
            }
            "grid" -> {
                var x = 0f; while (x <= w) { drawLine(color.copy(alpha = 0.09f), Offset(x, 0f), Offset(x, h), u); x += 30 * u }
                var y = 0f; while (y <= h) { drawLine(color.copy(alpha = 0.09f), Offset(0f, y), Offset(w, y), u); y += 30 * u }
                drawOval(color.copy(alpha = 0.06f), Offset(w * 0.55f, -h * 0.12f), Size(w * 0.7f, w * 0.7f))
            }
            "waves" -> for (i in 0 until 7) {
                val path = Path(); val base = h * 0.18f + i * 15 * u
                path.moveTo(0f, base); var x = 0f
                while (x <= w) { path.lineTo(x, base + sin(x / (42 * u) + i * 0.6f) * 12 * u); x += 6 * u }
                drawPath(path, color.copy(alpha = 0.07f + i * 0.015f), style = Stroke(1.5f * u))
            }
            "diagonal" -> { var off = -h; while (off <= w) { drawLine(color.copy(alpha = 0.08f), Offset(off, 0f), Offset(off + h * 0.45f, h * 0.45f), 7 * u); off += 22 * u } }
            "blobs" -> {
                drawOval(Brush.radialGradient(listOf(color.copy(alpha = 0.22f), Color.Transparent), Offset(w * 0.85f, w * 0.25f), w * 0.45f), Offset(w * 0.45f, -h * 0.15f), Size(w * 0.8f, w * 0.8f))
                drawOval(Brush.radialGradient(listOf(color.copy(alpha = 0.14f), Color.Transparent), Offset(0f, h * 0.25f + w * 0.3f), w * 0.35f), Offset(-w * 0.3f, h * 0.25f), Size(w * 0.6f, w * 0.6f))
            }
            "arcs" -> for (i in 1..6) { val r = i * 46 * u; drawCircle(color.copy(alpha = 0.13f - i * 0.012f), r, Offset(w, 0f), style = Stroke(1.5f * u)) }
            "none" -> Unit
            else -> {
                drawCircle(color.copy(alpha = 0.08f), w * 0.42f, Offset(w * 0.92f, h * 0.17f), style = Stroke(46 * u))
                drawCircle(color.copy(alpha = 0.05f), w * 0.25f, Offset(w * 0.08f, h * 0.88f), style = Stroke(30 * u))
            }
        }
    }
}

/** Slaydı verilen kutuya sığdırarak çizer */
@Composable
fun SlideCanvas(deck: JsonObject, index: Int, modifier: Modifier, scaleTo: Float? = null, rounded: Boolean = true, shadow: Boolean = false) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val scale = minOf(maxWidth.value / SLIDE_W, maxHeight.value / SLIDE_H).let { if (scaleTo != null) scaleTo / SLIDE_W else it }
        // Gölge slaydın kendi şeklinde (kutunun tamamında değil — eskiden arkasında büyük beyaz bir gölge dikdörtgeni kalıyordu)
        Box(Modifier.requiredSize(SLIDE_W.dp, SLIDE_H.dp).graphicsLayer {
            scaleX = scale; scaleY = scale
            if (shadow) { shadowElevation = 18.dp.toPx(); this.shape = RoundedCornerShape(30.dp); clip = true }
        }) {
            SlideContent(deck, index, rounded)
        }
    }
}

@Composable
private fun SlideContent(deck: JsonObject, index: Int, rounded: Boolean) {
    val slides = deck.objs("slides")
    val slide = slides.getOrNull(index) ?: return
    val theme = remember(deck) { SlideTheme.resolve(deck) }
    val pattern = deck.s("pattern") ?: "rings"
    val kind = slide.s("kind")?.lowercase() ?: "bullets"
    val isHero = kind in setOf("cover", "verdict", "section")
    val ink = if (isHero) theme.heroInk else theme.ink
    val imageTopic = slide.s("image")
    val imageUrl by produceState<String?>(null, imageTopic) { value = imageTopic?.let { WikiImages.url(it) } }
    val fullBleed = (kind == "cover" || kind == "image") && imageUrl != null
    val deckTitle = deck.s("title") ?: ""

    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(if (rounded) 30.dp else 0.dp))) {
        // Arka plan
        when {
            fullBleed -> {
                AsyncImage(imageUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.15f), Color.Black.copy(alpha = 0.3f), Color.Black.copy(alpha = 0.85f)))))
            }
            isHero -> { Box(Modifier.fillMaxSize().background(theme.hero)); SlidePattern(pattern, theme.heroInk, Modifier.fillMaxSize()) }
            else -> {
                Box(Modifier.fillMaxSize().background(theme.bg))
                SlidePattern(if (pattern == "none") "none" else "dots", theme.accent, Modifier.align(Alignment.TopEnd).size(150.dp).graphicsLayer { alpha = 0.55f })
            }
        }
        Column(Modifier.fillMaxSize().padding(26.dp)) {
            val headColor = if (fullBleed) Color.White else ink
            Row(Modifier.padding(bottom = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("%02d".format(index + 1), fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace,
                    color = if (fullBleed) Color.White else if (isHero) theme.heroAccent else theme.accent)
                Box(Modifier.size(18.dp, 1.5.dp).background(headColor.copy(alpha = 0.5f)))
                Text("${slides.size}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace, color = headColor.copy(alpha = 0.5f))
                Spacer(Modifier.weight(1f))
                if (index > 0) Text(deckTitle, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = headColor.copy(alpha = 0.5f), maxLines = 1)
            }
            Column(Modifier.fillMaxWidth().weight(1f)) {
                when (kind) {
                    "cover" -> Cover(slide, deckTitle, theme, if (fullBleed) Color.White else ink, fullBleed)
                    "section" -> Section(slide, index, theme, ink)
                    "quote" -> Quote(slide, theme)
                    "verdict" -> Verdict(slide, theme, ink)
                    "image" -> ImageSlide(slide, theme, fullBleed, imageUrl)
                    "compare" -> CompareSlide(slide, theme)
                    "stats" -> Stats(slide, theme)
                    "timeline" -> Timeline(slide, theme)
                    "proscons" -> ProsCons(slide, theme)
                    else -> Bullets(slide, theme, imageUrl)
                }
            }
        }
    }
}

@Composable
private fun SlideTitle(text: String?, theme: SlideTheme, size: Int = 25) {
    Column(Modifier.padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(text ?: "", fontSize = size.sp, fontWeight = FontWeight.Bold, color = theme.ink, maxLines = 3, letterSpacing = (-0.3).sp, lineHeight = (size + 4).sp)
        Box(Modifier.size(34.dp, 4.dp).clip(CircleShape).background(theme.accent))
    }
}

@Composable
private fun ColumnScope.Cover(slide: JsonObject, deckTitle: String, theme: SlideTheme, color: Color, fullBleed: Boolean) {
    Spacer(Modifier.weight(1f))
    Text(stringResource(R.string.presentation_tag), fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 2.5.sp, color = if (fullBleed) Color.White.copy(alpha = 0.75f) else theme.heroAccent)
    Text(slide.s("title") ?: deckTitle, fontSize = 34.sp, fontWeight = FontWeight.Black, color = color, maxLines = 4, lineHeight = 38.sp, letterSpacing = (-0.6).sp,
        modifier = Modifier.padding(top = 10.dp))
    slide.s("subtitle")?.let { Text(it, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = color.copy(alpha = 0.8f), maxLines = 3, modifier = Modifier.padding(top = 10.dp)) }
    Row(Modifier.padding(top = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Image(painterResource(R.drawable.chat_pp), null, Modifier.size(18.dp).clip(CircleShape), contentScale = ContentScale.Crop)
        Text("Pufy · ${turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy")}", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color.copy(alpha = 0.7f))
    }
}

@Composable
private fun ColumnScope.Section(slide: JsonObject, index: Int, theme: SlideTheme, ink: Color) {
    Spacer(Modifier.weight(1f))
    Text("%02d".format(index + 1), fontSize = 64.sp, fontWeight = FontWeight.Black, color = theme.heroAccent)
    Text(slide.s("title") ?: "", fontSize = 32.sp, fontWeight = FontWeight.Black, color = ink, maxLines = 3, lineHeight = 36.sp)
    (slide.s("subtitle") ?: slide.s("text"))?.let { Text(it, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = ink.copy(alpha = 0.8f), maxLines = 3, modifier = Modifier.padding(top = 12.dp)) }
    Spacer(Modifier.weight(1f))
}

@Composable
private fun ColumnScope.Quote(slide: JsonObject, theme: SlideTheme) {
    Spacer(Modifier.weight(1f))
    Icon(Icons.Rounded.FormatQuote, null, Modifier.size(40.dp), tint = theme.accent)
    Text(slide.s("text") ?: slide.s("title") ?: "", fontSize = 24.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = theme.ink, maxLines = 7,
        lineHeight = 30.sp, modifier = Modifier.padding(top = 16.dp))
    slide.s("subtitle")?.let { Text("— $it", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = theme.muted, modifier = Modifier.padding(top = 16.dp)) }
    Spacer(Modifier.weight(1f))
}

@Composable
private fun ColumnScope.Verdict(slide: JsonObject, theme: SlideTheme, ink: Color) {
    val defaultTitle = stringResource(R.string.slide_verdict_default)
    Text((slide.s("title") ?: defaultTitle).uppercase(TR), fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 2.5.sp, color = theme.heroAccent)
    Icon(Icons.Rounded.FormatQuote, null, Modifier.padding(top = 14.dp).size(30.dp), tint = theme.heroAccent.copy(alpha = 0.7f))
    slide.s("text")?.let { Text(it, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ink, maxLines = 6, lineHeight = 28.sp, modifier = Modifier.padding(top = 14.dp)) }
    slide.list("bullets").take(4).forEach { b ->
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.padding(top = 2.dp).size(13.dp), tint = theme.heroAccent)
            Text(b, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = ink.copy(alpha = 0.9f), maxLines = 2)
        }
    }
}

@Composable
private fun ColumnScope.ImageSlide(slide: JsonObject, theme: SlideTheme, fullBleed: Boolean, url: String?) {
    if (fullBleed) {
        Spacer(Modifier.weight(1f))
        Text(slide.s("title") ?: "", fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 3)
        (slide.s("text") ?: slide.s("subtitle"))?.let { Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.85f), maxLines = 4, modifier = Modifier.padding(top = 8.dp)) }
    } else {
        SlideTitle(slide.s("title"), theme)
        if (url != null) AsyncImage(url, null, Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(18.dp)).background(theme.surface), contentScale = ContentScale.Crop)
        (slide.s("text") ?: slide.s("subtitle"))?.let { Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = theme.ink, maxLines = 5, modifier = Modifier.padding(top = 12.dp)) }
    }
}

@Composable
private fun Bullets(slide: JsonObject, theme: SlideTheme, url: String?) {
    SlideTitle(slide.s("title"), theme)
    if (url != null) AsyncImage(url, null, Modifier.fillMaxWidth().height(110.dp).clip(RoundedCornerShape(18.dp)).padding(bottom = 0.dp), contentScale = ContentScale.Crop)
    if (url != null) Spacer(Modifier.height(14.dp))
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        slide.list("bullets").take(5).forEachIndexed { i, text ->
            Row(horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                Box(Modifier.size(21.dp).clip(CircleShape).background(theme.accent), contentAlignment = Alignment.Center) {
                    Text("${i + 1}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = theme.onAccent)
                }
                Text(text, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = theme.ink, maxLines = 3, lineHeight = 20.sp)
            }
        }
    }
}

@Composable
private fun ProsCons(slide: JsonObject, theme: SlideTheme) {
    SlideTitle(slide.s("title"), theme, 23)
    val prosLabel = stringResource(R.string.slide_pros)
    val consLabel = stringResource(R.string.slide_cons)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for ((label, items, strong) in listOf(Triple(prosLabel, slide.list("pros").ifEmpty { slide.list("bullets") }, true), Triple(consLabel, slide.list("cons"), false))) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(theme.surface).padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(label, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.6.sp, color = if (strong) theme.accent else theme.muted)
                items.take(4).forEach { item ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.size(18.dp).clip(CircleShape).background(if (strong) theme.accent else theme.ink.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                            Icon(if (strong) Icons.Rounded.Add else Icons.Rounded.Remove, null, Modifier.size(11.dp), tint = if (strong) theme.onAccent else theme.ink)
                        }
                        Text(item, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = theme.ink, maxLines = 2)
                    }
                }
            }
        }
    }
}

@Composable
private fun CompareSlide(slide: JsonObject, theme: SlideTheme) {
    val columns = slide.list("columns").take(3)
    val rows = slide.objs("rows").take(7)
    SlideTitle(slide.s("title"), theme, 23)
    Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Spacer(Modifier.width(78.dp))
        columns.forEach { Text(it, Modifier.weight(1f), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = theme.ink, textAlign = TextAlign.Center, maxLines = 2) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        rows.forEachIndexed { i, row ->
            val values = row.list("values"); val better = row.i("better")
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (i % 2 == 0) theme.surface.copy(alpha = 0.85f) else Color.Transparent)
                .padding(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(row.s("label") ?: "", Modifier.width(78.dp), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = theme.muted, maxLines = 2)
                columns.indices.forEach { col ->
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        Text(values.getOrElse(col) { "—" }, fontSize = 12.sp, fontWeight = if (better == col) FontWeight.Bold else FontWeight.Normal, color = theme.ink, maxLines = 2, textAlign = TextAlign.Center)
                        if (better == col) Icon(Icons.Rounded.Verified, null, Modifier.padding(start = 3.dp).size(10.dp), tint = theme.accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.Stats(slide: JsonObject, theme: SlideTheme) {
    val items = slide.objs("items").take(4)
    SlideTitle(slide.s("title"), theme)
    if (items.size == 1) {
        val item = items[0]
        Spacer(Modifier.weight(1f))
        Text(item.s("value") ?: item.s("label") ?: "", fontSize = 64.sp, fontWeight = FontWeight.Black, color = theme.accent, maxLines = 1)
        Text(if (item.s("value") == null) item.s("text") ?: "" else item.s("label") ?: "", fontSize = 16.sp, fontWeight = FontWeight.Medium, color = theme.muted)
        Spacer(Modifier.weight(1f))
    } else items.chunked(2).forEachIndexed { r, pair ->
        Row(Modifier.padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            pair.forEachIndexed { c, item ->
                val first = r == 0 && c == 0
                Column(Modifier.weight(1f).heightIn(min = 104.dp).clip(RoundedCornerShape(18.dp)).background(if (first) theme.accent else theme.surface).padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(item.s("value") ?: "—", fontSize = 26.sp, fontWeight = FontWeight.Black, color = if (first) theme.onAccent else theme.accent, maxLines = 1)
                    Text(item.s("label") ?: "", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = if (first) theme.onAccent.copy(alpha = 0.8f) else theme.muted, maxLines = 3)
                }
            }
            if (pair.size == 1) Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun Timeline(slide: JsonObject, theme: SlideTheme) {
    val items = slide.objs("items").take(5)
    SlideTitle(slide.s("title"), theme)
    items.forEachIndexed { i, item ->
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.padding(top = 3.dp).size(11.dp).clip(CircleShape).background(theme.accent))
                if (i < items.size - 1) Box(Modifier.width(2.dp).height(44.dp).background(theme.accent.copy(alpha = 0.25f)))
            }
            Column(Modifier.padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(item.s("label") ?: "", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = theme.ink)
                Text(item.s("text") ?: item.s("value") ?: "", fontSize = 13.sp, color = theme.muted, maxLines = 3)
            }
        }
    }
}

// MARK: Tam ekran sunum

@Composable
fun SlideDeckViewer(deck: JsonObject, onClose: () -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val count = deck.objs("slides").size
    val pager = rememberPagerState { count }
    var exporting by remember { mutableStateOf(false) }
    LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.drop(1).collect { Haptics.light(view) } }

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GlassIconButton(Icons.Rounded.Close, stringResource(R.string.close), size = 40.dp, iconSize = 18.dp, onClick = onClose)
            Column(Modifier.weight(1f)) {
                Text(deck.s("title") ?: stringResource(R.string.presentation_default_title), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, maxLines = 1)
                Text(stringResource(R.string.slides_count, count), style = PufyType.caption, color = c.secondaryText)
            }
            if (exporting) Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = c.text) }
            else GlassIconButton(Icons.Outlined.Share, stringResource(R.string.share_as_pdf), size = 40.dp, iconSize = 17.dp) {
                exporting = true
                scope.launch { runCatching { sharePdf(context, deck) }; exporting = false }
            }
        }
        HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 18.dp, vertical = 16.dp), pageSpacing = 12.dp) { page ->
            Box(Modifier.fillMaxSize().graphicsLayer {
                val off = abs((pager.currentPage - page) + pager.currentPageOffsetFraction).coerceIn(0f, 1f)
                scaleX = 1 - off * 0.06f; scaleY = 1 - off * 0.06f
            }, contentAlignment = Alignment.Center) {
                SlideCanvas(deck, page, Modifier.fillMaxSize(), shadow = true)
            }
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(count) { i ->
                val w by animateDpAsState(if (i == pager.currentPage) 22.dp else 7.dp, Springs.quick(), label = "dot")
                Box(Modifier.width(w).height(7.dp).clip(CircleShape).background(c.primary.copy(alpha = if (i == pager.currentPage) 1f else 0.2f)))
            }
        }
    }
}

/** Slaytları PDF'e çevirip paylaşır (iOS renderPDF karşılığı; her slayt bir sayfa) */
private suspend fun sharePdf(context: Context, deck: JsonObject) {
    val activity = context as? android.app.Activity ?: return
    val slides = deck.objs("slides").size
    val bitmaps = mutableListOf<android.graphics.Bitmap>()
    for (i in 0 until slides) bitmaps.add(SlideRenderer.render(activity, deck, i))
    val file = withContext(Dispatchers.IO) {
        val doc = PdfDocument()
        bitmaps.forEachIndexed { i, bmp ->
            val page = doc.startPage(PdfDocument.PageInfo.Builder(bmp.width, bmp.height, i + 1).create())
            page.canvas.drawBitmap(bmp, 0f, 0f, null); doc.finishPage(page)
        }
        val defaultTitle = context.getString(R.string.presentation_default_title)
        val safe = (deck.s("title") ?: defaultTitle).replace(Regex("[/\\\\:?%*|\"<>]"), "-").take(60)
        File(context.cacheDir, "$safe.pdf").also { f -> f.outputStream().use { doc.writeTo(it) }; doc.close() }
    }
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null))
}

/** Bir slaydı ekran dışında çizip resme çevirir */
object SlideRenderer {
    suspend fun render(activity: android.app.Activity, deck: JsonObject, index: Int): android.graphics.Bitmap = withContext(Dispatchers.Main) {
        val density = activity.resources.displayMetrics.density
        val w = (SLIDE_W * density).toInt(); val h = (SLIDE_H * density).toInt()
        val root = activity.window.decorView as android.view.ViewGroup
        val compose = androidx.compose.ui.platform.ComposeView(activity).apply {
            setContent { com.pufy.app.ui.theme.PufyTheme(dark = false) { Box(Modifier.size(SLIDE_W.dp, SLIDE_H.dp)) { SlideContent(deck, index, rounded = false) } } }
            alpha = 0f
        }
        root.addView(compose, android.view.ViewGroup.LayoutParams(w, h))
        kotlinx.coroutines.delay(900)      // görseller yüklensin
        compose.measure(android.view.View.MeasureSpec.makeMeasureSpec(w, android.view.View.MeasureSpec.EXACTLY), android.view.View.MeasureSpec.makeMeasureSpec(h, android.view.View.MeasureSpec.EXACTLY))
        compose.layout(0, 0, w, h)
        val bmp = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
        compose.alpha = 1f
        compose.draw(android.graphics.Canvas(bmp).apply { drawColor(Color.White.toArgb()) })
        root.removeView(compose)
        bmp
    }
}

