package com.pufy.app.ui.chat

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.TrendingDown
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Slideshow
import androidx.compose.material.icons.rounded.ArrowOutward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.pufy.app.R
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.ChatEngine
import com.pufy.app.ai.Slides
import com.pufy.app.core.PufyJson
import com.pufy.app.core.TR
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.ChatStore
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.ShimmerText
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// iOS ChatWidgets.swift + InteractiveCards.swift karşılığı: maç / kurum kartı, karşılaştırma, test, sunum

// MARK: JSON yardımcıları (model sayıyı da yazı da yazabilir — iOS LooseString)

internal fun JsonElement?.loose(): String? = when (this) {
    null, is JsonNull -> null
    is JsonPrimitive -> if (isString) content else booleanOrNull?.let { if (it) "Var" else "Yok" } ?: doubleOrNull?.let { d -> if (d % 1.0 == 0.0) d.toLong().toString() else d.toString() } ?: content
    else -> null
}
internal fun JsonObject.s(k: String) = this[k].loose()?.takeIf { it.isNotBlank() }
internal fun JsonObject.list(k: String): List<String> = (this[k] as? JsonArray)?.mapNotNull { it.loose()?.takeIf { s -> s.isNotBlank() } } ?: emptyList()
internal fun JsonObject.objs(k: String): List<JsonObject> = (this[k] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
internal fun JsonObject.i(k: String): Int? = this[k].loose()?.trim()?.toDoubleOrNull()?.toInt()

private val cardShape = RoundedCornerShape(24.dp)

@Composable
private fun cardModifier() = Modifier.fillMaxWidth().clip(cardShape).background(Pufy.colors.secondaryBackground)
    .border(0.5.dp, Pufy.colors.text.copy(alpha = 0.06f), cardShape).padding(16.dp)

// MARK: Logo (Wikipedia, yoksa site simgesi, yoksa baş harfler)

object Logos {
    private val cache = HashMap<String, String?>()
    suspend fun url(name: String, wiki: String?, domain: String?): String? {
        val key = "$wiki|$domain|$name"
        synchronized(cache) { if (cache.containsKey(key)) return cache[key] }
        var found: String? = null
        for (title in listOfNotNull(wiki, name).filter { it.isNotBlank() }) {
            found = WikiImages.url(title)?.takeIf { u -> val l = u.lowercase(); l.contains("logo") || l.contains("crest") || l.contains("emblem") || l.contains(".png") || l.contains(".svg") }
            if (found != null) break
        }
        if (found == null && !domain.isNullOrBlank()) {
            val host = domain.removePrefix("https://").removePrefix("http://").substringBefore("/")
            found = "https://www.google.com/s2/favicons?domain=$host&sz=128"
        }
        synchronized(cache) { cache[key] = found }
        return found
    }
}

@Composable
fun LogoTile(name: String, wiki: String?, domain: String?, size: Int) {
    val url by produceState<String?>(null, name, wiki, domain) { value = Logos.url(name, wiki, domain) }
    var failed by remember(url) { mutableStateOf(false) }
    val shape = RoundedCornerShape((size * 0.28f).dp)
    Box(Modifier.size(size.dp).clip(shape).background(Color.White).border(0.5.dp, Color.Black.copy(alpha = 0.08f), shape), contentAlignment = Alignment.Center) {
        if (url != null && !failed) AsyncImage(url, null, Modifier.fillMaxSize().padding((size * 0.12f).dp), contentScale = ContentScale.Fit, onError = { failed = true })
        else Text(name.split(" ").take(2).mapNotNull { it.firstOrNull()?.toString() }.joinToString("").uppercase(TR),
            fontSize = (size * 0.32f).sp, fontWeight = FontWeight.Bold, color = Color.Black.copy(alpha = 0.75f))
    }
}

// MARK: Maç / kurum kartı ([WIDGET])

@Composable
fun WidgetCard(widget: JsonObject, messageID: String, index: Int, isStatic: Boolean) {
    var shown by remember(widget) { mutableStateOf(widget) }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val isMatch = shown.s("type")?.lowercase() == "match" && shown["home"] is JsonObject && shown["away"] is JsonObject
    val status = shown.s("status")?.lowercase()
    val live = status == "live" || status == "halftime"
    val canRefresh = !isStatic && (if (isMatch) status != "finished" else shown.objs("facts").isNotEmpty())

    fun refresh() {
        if (refreshing) return
        refreshing = true
        scope.launch {
            val updated = runCatching { WidgetRefresher.refresh(shown, isMatch) }.getOrNull()
            refreshing = false
            if (updated != null) {
                shown = updated
                val sid = ChatEngine.currentSessionID.value ?: return@launch
                ChatStore.mutateMessage(sid, messageID, notify = true) { m ->
                    val list = m.widgets?.toMutableList() ?: return@mutateMessage m
                    if (index in list.indices) list[index] = updated
                    m.copy(widgets = JsonArray(list))
                }
            }
        }
    }
    // Canlı maç: 90 sn'de bir kendiliğinden güncellenir (iOS ile aynı, en fazla 20 kez)
    LaunchedEffect(live, isStatic) {
        if (!live || isStatic || !isMatch) return@LaunchedEffect
        repeat(20) { delay(90_000); refresh() }
    }

    Box(cardModifier().animateContentSize(Springs.standard())) {
        if (isMatch) MatchCard(shown, status, refreshing, canRefresh, ::refresh) else EntityCard(shown, refreshing, canRefresh, ::refresh)
    }
}

@Composable
private fun RefreshButton(refreshing: Boolean, onClick: () -> Unit) {
    val c = Pufy.colors
    val angle by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "a")
    Box(Modifier.size(28.dp).pressable(enabled = !refreshing, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(Icons.Rounded.Refresh, stringResource(R.string.refresh_action), Modifier.size(15.dp).graphicsLayer { rotationZ = if (refreshing) angle else 0f }, tint = c.secondaryText)
    }
}

private val kickoffFormats = listOf("yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm").map { DateTimeFormatter.ofPattern(it) }
private fun kickoff(s: String?): LocalDateTime? = s?.let { k -> kickoffFormats.firstNotNullOfOrNull { f -> runCatching { LocalDateTime.parse(k.take(19), f) }.getOrNull() } }

@Composable
private fun MatchCard(w: JsonObject, status: String?, refreshing: Boolean, canRefresh: Boolean, onRefresh: () -> Unit) {
    val c = Pufy.colors
    val home = w["home"]!!.jsonObject; val away = w["away"]!!.jsonObject
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            w.s("league")?.let { Text(it, style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, maxLines = 1, modifier = Modifier.weight(1f, fill = false)) }
            Spacer(Modifier.weight(1f))
            when (status) {
                "live", "halftime" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    val a by rememberInfiniteTransition(label = "live").animateFloat(1f, 0.35f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "d")
                    Box(Modifier.size(7.dp).graphicsLayer { alpha = a }.clip(CircleShape).background(Color(0xFFFF3B30)))
                    Text(if (status == "halftime") stringResource(R.string.match_halftime_upper) else stringResource(R.string.match_live_upper), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = c.text, letterSpacing = 0.5.sp)
                }
                "finished" -> Text(stringResource(R.string.match_finished_upper), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = c.secondaryText, letterSpacing = 0.5.sp)
                "postponed" -> Text(stringResource(R.string.match_postponed_upper), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = c.secondaryText, letterSpacing = 0.5.sp)
            }
            if (canRefresh) RefreshButton(refreshing, onRefresh)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Team(home, Modifier.weight(1f))
            Box(Modifier.widthIn(min = 96.dp), contentAlignment = Alignment.Center) {
                val hs = w.i("homeScore"); val aw = w.i("awayScore")
                val date = kickoff(w.s("kickoff"))
                when {
                    (status == "live" || status == "halftime" || status == "finished") && hs != null && aw != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        AnimatedContent("$hs - $aw", label = "score", transitionSpec = { (fadeIn() + androidx.compose.animation.slideInVertically { -it }) togetherWith fadeOut() }) {
                            Text(it, fontSize = 34.sp, fontWeight = FontWeight.Bold, color = c.text)
                        }
                        Text(when (status) { "halftime" -> stringResource(R.string.match_halftime); "finished" -> stringResource(R.string.match_finished); else -> w.s("minute")?.let { m -> if (m.endsWith("'")) m else "$m'" } ?: stringResource(R.string.match_live) },
                            style = PufyType.caption.copy(fontWeight = FontWeight.Medium), color = c.secondaryText)
                    }
                    date != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(date.format(DateTimeFormatter.ofPattern("HH:mm")), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = c.text)
                        val today = LocalDate.now(ZoneId.of("Europe/Istanbul"))
                        Text(when (date.toLocalDate()) { today -> stringResource(R.string.today); today.plusDays(1) -> stringResource(R.string.tomorrow); today.minusDays(1) -> stringResource(R.string.yesterday)
                            else -> date.format(DateTimeFormatter.ofPattern("d MMMM EEE", TR)) }, style = PufyType.caption.copy(fontWeight = FontWeight.Medium), color = c.secondaryText)
                    }
                    else -> Text("vs", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = c.secondaryText)
                }
            }
            Team(away, Modifier.weight(1f))
        }
        w.s("venue")?.let { v ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Outlined.LocationOn, null, Modifier.size(13.dp), tint = c.secondaryText)
                Text(v, style = PufyType.caption, color = c.secondaryText, maxLines = 1)
            }
        }
    }
}

@Composable
private fun Team(side: JsonObject, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val name = side.s("name") ?: ""
        LogoTile(name, side.s("wiki"), side.s("domain"), 56)
        Text(side.s("short") ?: name, style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Pufy.colors.text,
            textAlign = TextAlign.Center, maxLines = 2)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EntityCard(w: JsonObject, refreshing: Boolean, canRefresh: Boolean, onRefresh: () -> Unit) {
    val c = Pufy.colors
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LogoTile(w.s("name") ?: "", w.s("wiki"), w.s("domain"), 52)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(w.s("name") ?: "", style = PufyType.headline, color = c.text, maxLines = 1)
                w.s("subtitle")?.let { Text(it, style = PufyType.caption, color = c.secondaryText, maxLines = 2) }
            }
            if (canRefresh) RefreshButton(refreshing, onRefresh)
        }
        val facts = w.objs("facts").take(6)
        if (facts.isNotEmpty()) {
            val columns = if (facts.size % 3 == 0) 3 else 2
            facts.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { f ->
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(f.s("label") ?: "", style = PufyType.caption, color = c.secondaryText, maxLines = 1)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(f.s("value") ?: "—", style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, maxLines = 1)
                                when (f.s("trend")) {
                                    "up" -> Icon(Icons.AutoMirrored.Rounded.TrendingUp, null, Modifier.size(13.dp), tint = Color(0xFF34C759))
                                    "down" -> Icon(Icons.AutoMirrored.Rounded.TrendingDown, null, Modifier.size(13.dp), tint = Color(0xFFFF3B30))
                                }
                            }
                        }
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** iOS ChatWidgetRefresher: kartın şu anki değerlerini web araması ile tazeler */
object WidgetRefresher {
    suspend fun refresh(w: JsonObject, isMatch: Boolean): JsonObject? {
        val system = "Şu an: ${turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy EEEE HH:mm")} (Türkiye saati). Web'de ara ve SADECE istenen JSON'u yaz; açıklama, kod bloğu ya da başka metin yazma."
        val prompt = if (isMatch) {
            val home = w["home"]!!.jsonObject.s("name"); val away = w["away"]!!.jsonObject.s("name")
            "$home - $away maçının (${w.s("league") ?: ""}, başlama: ${w.s("kickoff") ?: "bilinmiyor"}) ŞU ANKİ durumunu bul.\n" +
                "JSON: {\"status\":\"upcoming|live|halftime|finished|postponed\",\"minute\":\"67\",\"homeScore\":0,\"awayScore\":0,\"kickoff\":\"YYYY-MM-DDTHH:mm:ss\"}\nMaç başlamadıysa skorları yazma."
        } else {
            val labels = w.objs("facts").mapNotNull { it.s("label") }
            if (labels.isEmpty()) return null
            "${w.s("name")} (${w.s("subtitle") ?: ""}) için şu bilgilerin ŞU ANKİ değerlerini bul: ${labels.joinToString(", ")}.\n" +
                "JSON: {\"facts\":[{\"label\":\"…\",\"value\":\"…\",\"trend\":\"up|down|flat\"}]} — etiketler aynı kalsın."
        }
        val raw = AiClient.generate(prompt, system = system, maxOutputTokens = 1024, timeoutSeconds = 60, useSearch = AiClient.canUseGoogleSearch, thinking = "low")
        val s = raw.indexOf('{'); val e = raw.lastIndexOf('}')
        if (s < 0 || e <= s) return null
        val patch = runCatching { PufyJson.parseToJsonElement(raw.substring(s, e + 1)).jsonObject }.getOrNull() ?: return null
        val map = LinkedHashMap<String, JsonElement>(w)
        if (isMatch) {
            patch.s("status")?.let { map["status"] = JsonPrimitive(it.lowercase()) }
            patch.s("minute")?.let { map["minute"] = JsonPrimitive(it) } ?: if (patch.s("status") != "live") map.remove("minute") else Unit
            patch.i("homeScore")?.let { map["homeScore"] = JsonPrimitive(it) }
            patch.i("awayScore")?.let { map["awayScore"] = JsonPrimitive(it) }
            patch.s("kickoff")?.let { map["kickoff"] = JsonPrimitive(it) }
        } else patch["facts"]?.let { if (it is JsonArray && it.isNotEmpty()) map["facts"] = it }
        return JsonObject(map)
    }
}

// MARK: Karşılaştırma ([COMPARE])

@Composable
fun CompareCard(data: JsonObject) {
    val c = Pufy.colors
    val items = data.objs("items").take(3)
    val rows = data.objs("rows").take(10)
    if (items.size < 2 || rows.isEmpty()) return
    Column(cardModifier(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        data.s("title")?.let { Text(it, style = PufyType.headline, color = c.text) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items.forEachIndexed { index, item ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val wiki = item.s("wiki")
                    val url by produceState<String?>(null, wiki) { value = wiki?.let { WikiImages.url(it) } }
                    Box(Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)).background(if (index == 0) c.primary else c.background), contentAlignment = Alignment.Center) {
                        Text((item.s("name") ?: "?").take(1).uppercase(TR), fontSize = 26.sp, fontWeight = FontWeight.Black, color = if (index == 0) c.onPrimary else c.primary)
                        if (url != null) AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    }
                    Text(item.s("name") ?: "", style = PufyType.footnote.copy(fontWeight = FontWeight.Bold), color = c.text, textAlign = TextAlign.Center, maxLines = 2)
                    item.s("subtitle")?.let { Text(it, fontSize = 11.sp, color = c.secondaryText, maxLines = 1) }
                }
            }
        }
        Column {
            rows.forEachIndexed { i, row ->
                val values = row.list("values")
                val better = row.i("better")
                Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(row.s("label") ?: "", style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items.indices.forEach { col ->
                            val best = better == col
                            Row(Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (best) c.primary.copy(alpha = 0.08f) else Color.Transparent)
                                .padding(vertical = 7.dp, horizontal = 4.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                Text(values.getOrElse(col) { "—" }, style = PufyType.subheadline.copy(fontWeight = if (best) FontWeight.Bold else FontWeight.Normal),
                                    color = c.text, textAlign = TextAlign.Center)
                                if (best) Icon(Icons.Rounded.Verified, null, Modifier.padding(start = 4.dp).size(13.dp), tint = c.text)
                            }
                        }
                    }
                }
                if (i < rows.size - 1) androidx.compose.material3.HorizontalDivider(color = c.separator.copy(alpha = 0.6f))
            }
        }
        data.s("verdict")?.let { v ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.primary).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(15.dp).padding(top = 2.dp), tint = c.onPrimary)
                Text(v, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.onPrimary)
            }
        }
    }
}

// MARK: Test ([QUIZ])

private object QuizProgress {
    val picks = mutableStateMapOf<String, Map<Int, Int>>()
    val current = mutableStateMapOf<String, Int>()
}

private fun answerIndex(q: JsonObject, options: List<String>): Int {
    val raw = q["answer"].loose()?.trim() ?: return 0
    raw.toIntOrNull()?.let { return it }
    if (raw.length == 1 && raw.uppercase()[0] in 'A'..'F') return raw.uppercase()[0] - 'A'
    return options.indexOfFirst { it.equals(raw, ignoreCase = true) }.coerceAtLeast(0)
}

@Composable
fun QuizCard(quiz: JsonObject, messageID: String, onAction: (String) -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    val questions = quiz.objs("questions").map { q -> val opts = q.list("options"); Triple(q, opts, answerIndex(q, opts)) }
        .filter { (q, o, a) -> o.size >= 2 && a in o.indices && !q.s("q").isNullOrBlank() }
    if (questions.isEmpty()) return
    val picks = QuizProgress.picks[messageID] ?: emptyMap()
    val index = QuizProgress.current[messageID] ?: 0
    val finished = index >= questions.size
    val progress by animateFloatAsState(minOf(index, questions.size).toFloat() / questions.size, Springs.standard(), label = "p")

    Column(cardModifier().animateContentSize(Springs.standard()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Checklist, null, Modifier.size(14.dp), tint = c.secondaryText)
            Text(quiz.s("title") ?: "Test", style = PufyType.caption.copy(fontWeight = FontWeight.Bold), color = c.secondaryText, maxLines = 1,
                modifier = Modifier.padding(start = 5.dp).weight(1f))
            Text(if (finished) stringResource(R.string.done_action) else "${index + 1}/${questions.size}", style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
        }
        Box(Modifier.fillMaxWidth().height(5.dp).clip(CircleShape).background(c.text.copy(alpha = 0.08f))) {
            Box(Modifier.fillMaxWidth(progress).height(5.dp).clip(CircleShape).background(c.primary))
        }
        AnimatedContent(index, label = "q", transitionSpec = {
            (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut())
        }) { idx ->
            if (idx >= questions.size) {
                val score = questions.indices.count { picks[it] == questions[it].third }
                val ratio = score.toFloat() / questions.size
                val wrongs = questions.indices.filter { picks[it] != questions[it].third }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("$score", fontSize = 48.sp, fontWeight = FontWeight.Black, color = c.text)
                        Text("/ ${questions.size}", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = c.secondaryText, modifier = Modifier.padding(bottom = 8.dp))
                        Spacer(Modifier.weight(1f))
                        Text(when { ratio == 1f -> stringResource(R.string.quiz_result_perfect); ratio >= 0.7f -> stringResource(R.string.quiz_result_great); ratio >= 0.4f -> stringResource(R.string.quiz_result_good); else -> stringResource(R.string.quiz_result_practice) },
                            style = PufyType.headline, color = c.text, modifier = Modifier.padding(bottom = 10.dp))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(Modifier.weight(1f).clip(CircleShape).background(c.background).pressable { QuizProgress.picks[messageID] = emptyMap(); QuizProgress.current[messageID] = 0 }
                            .padding(vertical = 11.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Replay, null, Modifier.size(15.dp), tint = c.text)
                            Text(" " + stringResource(R.string.quiz_retry), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                        }
                        if (wrongs.isNotEmpty()) Row(Modifier.weight(1f).clip(CircleShape).background(c.primary).pressable {
                            val prompt = if (com.pufy.app.core.AppLocales.isEnglish()) {
                                "I answered these questions incorrectly in the test: ${wrongs.joinToString(", ") { "\"${questions[it].first.s("q")}\"" }}. Can you briefly explain the correct answers?"
                            } else {
                                "Testte şu soruları yanlış yaptım: ${wrongs.joinToString(", ") { "\"${questions[it].first.s("q")}\"" }}. Doğrularını kısaca anlatır mısın?"
                            }
                            onAction(prompt)
                        }.padding(vertical = 11.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.Lightbulb, null, Modifier.size(15.dp), tint = c.onPrimary)
                            Text(" " + stringResource(R.string.quiz_explain_wrongs), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.onPrimary)
                        }
                    }
                }
            } else {
                val (q, options, answer) = questions[idx]
                val picked = picks[idx]
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(q.s("q") ?: "", style = PufyType.headline, color = c.text, modifier = Modifier.padding(bottom = 2.dp))
                    options.forEachIndexed { i, option ->
                        val answered = picked != null
                        val highlight = answered && i == answer
                        val wrong = answered && picked == i && i != answer
                        Row(Modifier.fillMaxWidth().graphicsLayer { alpha = if (answered && !highlight && picked != i) 0.5f else 1f }
                            .clip(RoundedCornerShape(14.dp)).background(if (highlight) c.primary else c.background)
                            .pressable(enabled = !answered) {
                                QuizProgress.picks[messageID] = picks + (idx to i)
                                if (i == answer) Haptics.success(view) else Haptics.medium(view)
                            }.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(Modifier.size(26.dp).clip(CircleShape).background(if (highlight) c.onPrimary.copy(alpha = 0.18f) else c.soft), contentAlignment = Alignment.Center) {
                                Text(('A' + i).toString(), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (highlight) c.onPrimary else c.text)
                            }
                            Text(option, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium, textDecoration = if (wrong) TextDecoration.LineThrough else null),
                                color = if (highlight) c.onPrimary else if (wrong) c.secondaryText else c.text, modifier = Modifier.weight(1f))
                            if (highlight) Icon(Icons.Rounded.CheckCircle, null, Modifier.size(18.dp), tint = c.onPrimary)
                            else if (wrong) Icon(Icons.Rounded.Cancel, null, Modifier.size(18.dp), tint = c.secondaryText)
                        }
                    }
                    AnimatedVisibility(picked != null, enter = fadeIn() + expandVertically()) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(if (picked == answer) stringResource(R.string.quiz_correct) else stringResource(R.string.quiz_correct_answer_is, options[answer]), style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold), color = c.text)
                            q.s("explain")?.let { Text(it, style = PufyType.subheadline, color = c.secondaryText) }
                            Text(if (idx + 1 < questions.size) stringResource(R.string.quiz_next_question) else stringResource(R.string.quiz_see_result), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold),
                                color = c.onPrimary, textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().padding(top = 2.dp).clip(CircleShape).background(c.primary)
                                    .pressable { QuizProgress.current[messageID] = idx + 1 }.padding(vertical = 12.dp))
                        }
                    }
                }
            }
        }
    }
}

// MARK: Öneri butonları ([ACTIONS])

private fun actionIcon(action: String): ImageVector {
    val a = action.lowercase(TR)
    return when {
        a.contains("sunum") || a.contains("slayt") -> Icons.Outlined.Slideshow
        a.contains("test") || a.contains("quiz") || a.contains("sına") -> Icons.Outlined.Checklist
        else -> Icons.Rounded.ArrowOutward
    }
}

@Composable
fun ActionChipsRow(actions: List<String>, onAction: (String) -> Unit) {
    val c = Pufy.colors
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.take(4).forEach { a ->
            Row(Modifier.clip(CircleShape).background(c.secondaryBackground).border(0.5.dp, c.text.copy(alpha = 0.08f), CircleShape)
                .pressable { onAction(a) }.padding(horizontal = 14.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(actionIcon(a), null, Modifier.size(13.dp), tint = c.text)
                Text(a, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
            }
        }
    }
}

// MARK: Sunum kartı ([SLIDES])

object DeckViewerState { val deck = mutableStateOf<JsonObject?>(null) }

@Composable
fun SlideDeckCard(deck: JsonObject, messageID: String, createdAt: Double) {
    val c = Pufy.colors
    val status = deck.s("status")
    val slides = deck.objs("slides")
    val started = (deck["startedAt"] as? JsonPrimitive)?.doubleOrNull ?: createdAt
    val stale = status == "generating" && com.pufy.app.core.nowSwift() - started > 180
    val shape = RoundedCornerShape(22.dp)
    val base = Modifier.fillMaxWidth().clip(shape).background(c.secondaryBackground).border(0.5.dp, c.text.copy(alpha = 0.06f), shape)
    AnimatedContent(if (status == "ready" && slides.isNotEmpty()) 2 else if (status == "failed" || stale) 1 else 0, label = "deck",
        transitionSpec = { fadeIn() togetherWith fadeOut() }) { state ->
        when (state) {
            2 -> Row(base.pressable(scale = 0.98f) { DeckViewerState.deck.value = deck }.padding(12.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(86.dp, 108.dp).clip(RoundedCornerShape(8.dp))) {
                    SlideCanvas(deck, 0, Modifier.fillMaxSize(), scaleTo = 86f)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.presentation_tag), fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.8.sp, color = c.secondaryText)
                    Text(deck.s("title") ?: stringResource(R.string.presentation_default_title), style = PufyType.headline, color = c.text, maxLines = 2)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.presentation_slides_count, slides.size), style = PufyType.caption, color = c.secondaryText)
                        Text(stringResource(R.string.open_action), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                        Icon(Icons.Rounded.ArrowOutward, null, Modifier.size(11.dp), tint = c.text)
                    }
                }
            }
            1 -> Row(base.pressable(scale = 0.98f) { val sid = ChatEngine.currentSessionID.value; if (sid != null) Slides.retry(sid, messageID) }.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(c.soft), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Refresh, null, Modifier.size(17.dp), tint = c.text) }
                Column {
                    Text(stringResource(R.string.presentation_failed), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                    Text(stringResource(R.string.presentation_retry_hint), style = PufyType.caption, color = c.secondaryText)
                }
            }
            else -> Row(base.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                val a by rememberInfiniteTransition(label = "pulse").animateFloat(0.4f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "a")
                Box(Modifier.size(64.dp, 80.dp).clip(RoundedCornerShape(12.dp)).background(c.soft), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Slideshow, null, Modifier.size(24.dp).graphicsLayer { alpha = a }, tint = c.secondaryText)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ShimmerText(stringResource(R.string.presentation_preparing), PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                    Text(deck.s("title") ?: "", style = PufyType.caption, color = c.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

