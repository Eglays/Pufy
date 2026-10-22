package com.pufy.app.ui.chat

import android.content.ClipData
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.pufy.app.ai.AiClient
import com.pufy.app.ui.components.ShimmerBox
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.net.URLEncoder

// iOS MarkdownView karşılığı: paragraf, başlık, liste kartı, bilgi kutusu, kod, tablo, ayraç, konu görselleri

@Composable
fun MarkdownView(text: String, modifier: Modifier = Modifier) {
    val blocks = remember(text) { MarkdownParser.blocks(text) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        blocks.forEach { Block(it) }
    }
}

@Composable
private fun inline(text: String) = Pufy.colors.let { c -> remember(text, c.isDark) { MarkdownParser.inline(text, c.soft, c.text) } }

@Composable
private fun Block(block: MdBlock) {
    val c = Pufy.colors
    when (block) {
        is MdBlock.Paragraph -> Text(inline(block.text), style = PufyType.body, color = c.text)
        is MdBlock.Heading -> Text(
            inline(block.text), color = c.text, modifier = Modifier.padding(top = 4.dp),
            style = when (block.level) {
                1 -> PufyType.title.copy(fontSize = 20.sp)
                2 -> PufyType.headline
                else -> PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold)
            })
        is MdBlock.ListBlock -> if (block.items.size >= 2) ListCard(block.items) else block.items.forEach { item ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(item.marker, style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                Text(inline(item.text), style = PufyType.body, color = c.text)
            }
        }
        is MdBlock.Quote -> Callout(block.text)
        is MdBlock.Code -> CodeBlock(block.language, block.code)
        is MdBlock.Table -> TableView(block.header, block.rows)
        MdBlock.Rule -> HorizontalDivider(Modifier.padding(vertical = 4.dp), color = c.separator)
        is MdBlock.Image -> TopicImage(block.topic, block.caption)
        is MdBlock.Gallery -> Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            block.items.forEach { (topic, caption) -> Box(Modifier.width(220.dp)) { TopicImage(topic, caption, aspect = 4f / 3f) } }
        }
    }
}

@Composable
private fun ListCard(items: List<MdListItem>) {
    val c = Pufy.colors
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(c.secondaryBackground)
            .padding(horizontal = 14.dp, vertical = 4.dp)
    ) {
        items.forEachIndexed { i, item ->
            Row(Modifier.padding(start = (item.indent * 22).dp).padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(22.dp).padding(top = 1.dp), contentAlignment = Alignment.TopCenter) {
                    if (item.marker.endsWith(".")) {
                        Box(Modifier.size(22.dp).clip(CircleShape).background(c.primary), contentAlignment = Alignment.Center) {
                            Text(item.marker.dropLast(1), color = c.onPrimary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    } else {
                        Box(Modifier.padding(top = 9.dp).size(6.dp).clip(CircleShape)
                            .background(if (item.indent == 0) c.text.copy(alpha = 0.75f) else c.secondaryText))
                    }
                }
                Text(inline(item.text), style = PufyType.body.copy(lineHeight = 25.sp), color = c.text, modifier = Modifier.weight(1f))
            }
            if (i < items.size - 1 && items[i + 1].indent == 0) HorizontalDivider(Modifier.padding(start = 34.dp), color = c.separator.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun Callout(text: String) {
    val c = Pufy.colors
    val plain = text.lowercase()
    val warn = plain.startsWith("dikkat") || plain.startsWith("uyarı") || plain.startsWith("önemli")
    val tip = plain.startsWith("ipucu") || plain.startsWith("öneri")
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.soft)
            .border(1.dp, c.text.copy(alpha = 0.06f), RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(if (warn) Icons.Rounded.Warning else if (tip) Icons.Outlined.Lightbulb else Icons.Outlined.Info, null,
            Modifier.size(18.dp).padding(top = 2.dp), tint = if (warn) Color(0xFFFF9500) else c.text)
        Text(inline(text), style = PufyType.callout, color = c.text)
    }
}

@Composable
fun CodeBlock(language: String, code: String) {
    val c = Pufy.colors
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var copied by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.secondaryBackground)
            .border(1.dp, c.text.copy(alpha = 0.06f), RoundedCornerShape(14.dp))
    ) {
        val defaultCodeTag = androidx.compose.ui.res.stringResource(com.pufy.app.R.string.code_tag)
        val copyText = androidx.compose.ui.res.stringResource(com.pufy.app.R.string.copy_action)
        val copiedText = androidx.compose.ui.res.stringResource(com.pufy.app.R.string.copied_action)
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(language.ifEmpty { defaultCodeTag }.lowercase(), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
            Spacer(Modifier.weight(1f))
            Row(Modifier.pressable {
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("kod", code))) }
                copied = true
            }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(if (copied) Icons.Rounded.Check else Icons.Outlined.ContentCopy, null, Modifier.size(13.dp),
                    tint = if (copied) c.primary else c.secondaryText)
                Text(if (copied) copiedText else copyText, style = PufyType.caption.copy(fontWeight = FontWeight.Medium),
                    color = if (copied) c.primary else c.secondaryText)
            }
        }
        HorizontalDivider(color = c.separator.copy(alpha = 0.6f))
        Text(code, Modifier.horizontalScroll(rememberScrollState()).padding(14.dp),
            style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 14.sp, lineHeight = 20.sp), color = c.text, softWrap = false)
    }
    LaunchedEffect(copied) { if (copied) { delay(1600); copied = false } }
}

@Composable
private fun TableView(header: List<String>, rows: List<List<String>>) {
    val c = Pufy.colors
    // Sütun sütun çizilir: her sütun en geniş hücresi kadar olur, satırlar hizalı kalır
    Box(Modifier.horizontalScroll(rememberScrollState())) {
        Row(Modifier.clip(RoundedCornerShape(12.dp)).border(1.dp, c.text.copy(alpha = 0.08f), RoundedCornerShape(12.dp))) {
            header.indices.forEach { col ->
                Column(Modifier.width(IntrinsicSize.Max)) {
                    Text(inline(header[col]), Modifier.fillMaxWidth().background(c.soft).widthIn(min = 70.dp).padding(horizontal = 12.dp, vertical = 8.dp),
                        style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, maxLines = 1, softWrap = false)
                    rows.forEachIndexed { i, row ->
                        Text(inline(row.getOrElse(col) { "" }), Modifier.fillMaxWidth()
                            .background(if (i % 2 == 1) c.text.copy(alpha = 0.03f) else Color.Transparent)
                            .widthIn(min = 70.dp).padding(horizontal = 12.dp, vertical = 8.dp),
                            style = PufyType.subheadline, color = c.text, maxLines = 1, softWrap = false)
                    }
                }
            }
        }
    }
}

// MARK: Konu görselleri ([IMG: konu | açıklama]) — Wikipedia'dan (iOS WikiImageLoader)

object WikiImages {
    private val cache = HashMap<String, String?>()

    suspend fun url(topic: String): String? {
        synchronized(cache) { if (cache.containsKey(topic)) return cache[topic] }
        val found = withContext(Dispatchers.IO) { runCatching { lookup(topic) }.getOrNull() }
        synchronized(cache) { cache[topic] = found }
        return found
    }

    private fun get(url: String): JsonObject? {
        val request = Request.Builder().url(url.toHttpUrl()).header("User-Agent", "PufyAgent/2.0 (Android)").build()
        AiClient.http.newCall(request).execute().use { r ->
            if (!r.isSuccessful) return null
            return runCatching { com.pufy.app.core.PufyJson.parseToJsonElement(r.body.string()).jsonObject }.getOrNull()
        }
    }

    private fun lookup(topic: String): String? {
        for (lang in listOf("en", "tr")) {
            val title = URLEncoder.encode(topic.replace(" ", "_"), "UTF-8").replace("+", "%20")
            val json = get("https://$lang.wikipedia.org/api/rest_v1/page/summary/$title?redirect=true") ?: continue
            val thumb = json["thumbnail"]?.jsonObject?.get("source")?.jsonPrimitive?.content
            val source = thumb?.replace(Regex("/\\d+px-"), "/960px-") ?: json["originalimage"]?.jsonObject?.get("source")?.jsonPrimitive?.content
            if (source != null && !source.lowercase().endsWith(".svg") && !source.lowercase().contains(".svg/")) return source
        }
        val q = URLEncoder.encode(topic, "UTF-8")
        val json = get("https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=6&gsrsearch=$q&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=960")
        val pages = json?.get("query")?.jsonObject?.get("pages")?.jsonObject ?: return null
        return pages.values.map { it.jsonObject }.sortedBy { it["index"]?.jsonPrimitive?.content?.toIntOrNull() ?: 99 }.firstNotNullOfOrNull { page ->
            val info = page["imageinfo"]?.jsonArray?.firstOrNull()?.jsonObject ?: return@firstNotNullOfOrNull null
            val mime = info["mime"]?.jsonPrimitive?.content
            if (mime !in setOf("image/jpeg", "image/png", "image/webp")) null
            else (info["thumburl"] ?: info["url"])?.jsonPrimitive?.content
        }
    }
}

@Composable
fun TopicImage(topic: String, caption: String?, aspect: Float = 16f / 10f) {
    val c = Pufy.colors
    val url by produceState<String?>(null, topic) { value = WikiImages.url(topic) }
    var failed by remember(topic) { mutableStateOf(false) }
    if (failed) return
    Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // Panorama gibi çok geniş görseller taşmasın: kutu sabit oranlı, görsel içine kırpılarak yerleşir (iOS düzeltmesiyle aynı)
        Box(Modifier.fillMaxWidth().aspectRatio(aspect).clip(RoundedCornerShape(18.dp)).background(c.secondaryBackground)) {
            if (url != null) SubcomposeAsyncImage(
                model = url, contentDescription = caption ?: topic, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().aspectRatio(aspect),
                loading = { ShimmerBox(Modifier.fillMaxWidth().aspectRatio(aspect)) },
                error = { failed = true },
            ) else ShimmerBox(Modifier.fillMaxWidth().aspectRatio(aspect))
        }
        if (!caption.isNullOrBlank()) Text(caption, style = PufyType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 4.dp))
    }
    LaunchedEffect(topic) { delay(10_000); if (url == null) failed = true }
}

