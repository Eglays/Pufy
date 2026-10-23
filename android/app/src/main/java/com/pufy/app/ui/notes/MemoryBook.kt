package com.pufy.app.ui.notes

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.MedicalServices
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CenterFocusStrong
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.core.TR
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.core.str
import com.pufy.app.data.MemoryStore
import com.pufy.app.data.Profile
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

// iOS MemoryBookView karşılığı: Kişisel Ağ — merkezde sen, etrafında alanlar, dışta bilgiler (Ağ / Liste görünümü)

private val categoryIcons: Map<String, ImageVector> = mapOf(
    "identity" to Icons.Outlined.Badge, "people" to Icons.Outlined.Group, "work" to Icons.Outlined.Work, "skills" to Icons.Outlined.Build,
    "interests" to Icons.Rounded.AutoAwesome, "preferences" to Icons.Outlined.FavoriteBorder, "traits" to Icons.Outlined.Psychology,
    "places" to Icons.Outlined.LocationOn, "goals" to Icons.Outlined.Flag, "health" to Icons.Outlined.MedicalServices, "other" to Icons.Outlined.GridView,
)

private class Hub(val category: String, val pos: Offset, val count: Int)
private class Leaf(val item: JsonObject, val pos: Offset, val hub: Offset)

/** iOS GraphLayout: alanlar merkezden 135, bilgiler 245+72·halka uzaklıkta, alanın açı diliminde */
private fun layout(items: List<JsonObject>): Triple<List<Hub>, List<Leaf>, Float> {
    val grouped = items.groupBy { MemoryStore.category(it) }
    val cats = grouped.keys.sortedBy { MemoryStore.categoryOrder.indexOf(it) }
    if (cats.isEmpty()) return Triple(emptyList(), emptyList(), 0f)
    val total = cats.sumOf { max(grouped.getValue(it).size, 2).toDouble() }
    val hubs = mutableListOf<Hub>(); val leaves = mutableListOf<Leaf>()
    var angle = -Math.PI / 2; var extent = 0f
    for (cat in cats) {
        val group = grouped.getValue(cat).sortedByDescending { MemoryStore.importance(it) }
        val span = 2 * Math.PI * max(group.size, 2) / total
        val mid = angle + span / 2
        val hub = Offset((cos(mid) * 135).toFloat(), (sin(mid) * 135).toFloat())
        hubs.add(Hub(cat, hub, group.size))
        var index = 0; var ring = 0
        while (index < group.size) {
            val radius = 245.0 + ring * 72
            val usable = max(span - 0.18, 0.25)
            val perRing = max(1, (usable * radius / 108).toInt())
            val count = minOf(perRing, group.size - index)
            val step = if (count > 1) minOf(usable / (count - 1), 108 / radius) else 0.0
            for (k in 0 until count) {
                val a = mid + (k - (count - 1) / 2.0) * step
                leaves.add(Leaf(group[index + k], Offset((cos(a) * radius).toFloat(), (sin(a) * radius).toFloat()), hub))
                extent = max(extent, radius.toFloat())
            }
            index += count; ring++
        }
        angle += span
    }
    return Triple(hubs, leaves, extent)
}

private fun drift(id: String, t: Double, amp: Float): Offset {
    val seed = id.fold(0) { a, ch -> (a * 31 + ch.code) and 0xFFFF }.toDouble()
    val phase = (seed % 628) / 100; val speed = 0.55 + (seed % 40) / 100
    return Offset((sin(t * speed + phase) * amp).toFloat(), (cos(t * speed * 0.8 + phase * 1.3) * amp).toFloat())
}

@Composable
fun MemoryBookScreen(onClose: () -> Unit) {
    val c = Pufy.colors
    val items by MemoryStore.items.collectAsState()
    var graph by remember { mutableStateOf(true) }
    var selected by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<JsonObject?>(null) }
    var adding by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClose) { Text(stringResource(R.string.close), color = c.text) }
            Text(stringResource(R.string.personal_network), style = PufyType.headline, color = c.text, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            Box {
                Box(Modifier.size(44.dp).pressable { menu = true }, contentAlignment = Alignment.Center) { Icon(Icons.Rounded.MoreHoriz, stringResource(R.string.options), tint = c.text) }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text(stringResource(R.string.add_info)) }, onClick = { menu = false; adding = true }, leadingIcon = { Icon(Icons.Rounded.Add, null) })
                    DropdownMenuItem({ Text(stringResource(R.string.delete_all), color = androidx.compose.ui.graphics.Color(0xFFFF3B30)) }, onClick = { menu = false; confirmReset = true },
                        leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = androidx.compose.ui.graphics.Color(0xFFFF3B30)) })
                }
            }
        }
        var hintMemoryShown by remember { mutableStateOf(com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.HINT_MEMORY_SHOWN)) }
        if (!hintMemoryShown) {
            com.pufy.app.ui.coach.HintBubble(
                text = stringResource(R.string.hint_memory),
                onDismiss = {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_MEMORY_SHOWN, true)
                    hintMemoryShown = true
                },
                modifier = Modifier
                    .padding(horizontal = 20.dp, vertical = 6.dp)
                    .align(Alignment.CenterHorizontally)
            )
        }
        if (items.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
                Icon(Icons.Outlined.Hub, null, Modifier.size(48.dp), tint = c.secondaryText)
                Text(stringResource(R.string.i_dont_know_you_yet), style = PufyType.headline, color = c.text)
                Text(stringResource(R.string.memory_empty_subtitle), style = PufyType.subheadline, color = c.secondaryText, textAlign = TextAlign.Center)
            }
            return@Column
        }
        // Ağ / Liste seçici
        Row(Modifier.padding(horizontal = 20.dp).padding(bottom = 8.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.soft).padding(3.dp)) {
            listOf(true to stringResource(R.string.network_view), false to stringResource(R.string.list_view)).forEach { (isGraph, label) ->
                Box(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if (graph == isGraph) c.background else androidx.compose.ui.graphics.Color.Transparent)
                    .pressable(scale = 0.98f) { graph = isGraph }.padding(vertical = 7.dp), contentAlignment = Alignment.Center) {
                    Text(label, style = PufyType.subheadline.copy(fontWeight = if (graph == isGraph) FontWeight.SemiBold else FontWeight.Normal), color = c.text)
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (graph) Graph(items, selected) { selected = it } else MemoryList(items) { editing = it }
            val item = items.firstOrNull { it.str("id") == selected }
            androidx.compose.animation.AnimatedVisibility(graph && item != null, Modifier.align(Alignment.BottomCenter).padding(16.dp),
                enter = fadeIn() + slideInVertically { it }, exit = fadeOut() + slideOutVertically { it }) {
                item?.let { DetailCard(it, onEdit = { editing = it }, onDelete = { it.str("id")?.let(MemoryStore::delete); selected = null }, onClose = { selected = null }) }
            }
        }
    }

    if (editing != null || adding) MemoryEditor(editing) { editing = null; adding = false }
    if (confirmReset) AlertDialog({ confirmReset = false }, title = { Text(stringResource(R.string.memory_reset_title)) },
        confirmButton = { TextButton({ MemoryStore.items.value.mapNotNull { it.str("id") }.forEach(MemoryStore::delete); confirmReset = false }) { Text(stringResource(R.string.delete_all), color = androidx.compose.ui.graphics.Color(0xFFFF3B30)) } },
        dismissButton = { TextButton({ confirmReset = false }) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun Graph(items: List<JsonObject>, selected: String?, onSelect: (String?) -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    val density = LocalDensity.current
    val (hubs, leaves, extent) = remember(items) { layout(items) }
    var focus by remember { mutableStateOf<String?>(null) }
    var scale by remember { mutableFloatStateOf(1f) }
    var pan by remember { mutableStateOf(Offset.Zero) }
    var time by remember { mutableStateOf(0.0) }
    var initialFitDone by remember { mutableStateOf(false) }
    val emerge = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { emerge.animateTo(1f, tween(900, easing = FastOutSlowInEasing)) }
    LaunchedEffect(Unit) { val start = withFrameMillis { it }; while (true) { withFrameMillis { time = (it - start) / 1000.0 } } }

    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds()
        .pointerInput(Unit) { detectTransformGestures { _, p, z, _ -> pan += p; scale = (scale * z).coerceIn(0.35f, 2.5f) } }
        .pointerInput(Unit) { detectTapGestures(onDoubleTap = { scope.launch { scale = 1f; pan = Offset.Zero } }, onTap = { onSelect(null) }) }) {
        val cx = constraints.maxWidth / 2f; val cy = constraints.maxHeight / 2f
        val px = with(density) { 1.dp.toPx() }
        val out = emerge.value

        // Açılışta tüm ağ ekrana sığsın
        LaunchedEffect(extent, constraints.maxWidth, constraints.maxHeight) {
            if (!initialFitDone && constraints.maxWidth > 0 && extent > 0f) {
                val fit = (minOf(constraints.maxWidth, constraints.maxHeight) / 2f) / ((extent + 70) * px)
                scale = fit.coerceIn(0.35f, 1f)
                pan = Offset.Zero
                initialFitDone = true
            }
        }
        fun hubPoint(h: Offset, cat: String): Offset {
            val ph = MemoryStore.categoryOrder.indexOf(cat) * 1.7
            return h * out + Offset((sin(time * 0.45 + ph) * 1.6).toFloat(), (cos(time * 0.38 + ph) * 1.6).toFloat())
        }
        Box(Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = pan.x; translationY = pan.y }) {
            // Bağlantı çizgileri
            Canvas(Modifier.fillMaxSize()) {
                val center = Offset(cx, cy)
                hubs.forEach { h ->
                    val dim = focus != null && focus != h.category
                    drawLine(c.text.copy(alpha = if (dim) 0.05f else 0.18f), center, center + hubPoint(h.pos, h.category) * px, 1.4f * px)
                }
                leaves.forEach { l ->
                    val cat = MemoryStore.category(l.item)
                    val id = l.item.str("id") ?: ""
                    val hp = center + hubPoint(l.hub, cat) * px
                    val end = center + (l.hub * out + (l.pos - l.hub) * out + drift(id, time, 2.6f)) * px
                    val mid = Offset((hp.x + end.x) / 2, (hp.y + end.y) / 2)
                    val ctrl = Offset(mid.x + (center.x - mid.x) * 0.15f, mid.y + (center.y - mid.y) * 0.15f)
                    val path = Path().apply { moveTo(hp.x, hp.y); quadraticTo(ctrl.x, ctrl.y, end.x, end.y) }
                    val sel = id == selected
                    drawPath(path, c.text.copy(alpha = if (sel) 0.6f else if (focus != null && focus != cat) 0.03f else 0.10f), style = Stroke((if (sel) 1.6f else 1f) * px))
                }
            }
            // Bilgiler
            leaves.forEach { l ->
                val id = l.item.str("id") ?: return@forEach
                val cat = MemoryStore.category(l.item)
                val p = l.hub * out + (l.pos - l.hub) * out + drift(id, time, 2.6f)
                Box(Modifier.offset { IntOffset((cx + p.x * px).toInt(), (cy + p.y * px).toInt()) }.wrapContentSize()
                    .graphicsLayer { translationX = -size.width / 2; translationY = -size.height / 2; alpha = if (focus != null && focus != cat) 0.2f else out; val s = 0.5f + 0.5f * out; scaleX = s; scaleY = s }) {
                    LeafNode(l.item, id == selected) { Haptics.light(view); onSelect(if (selected == id) null else id) }
                }
            }
            // Alanlar
            hubs.forEach { h ->
                val p = hubPoint(h.pos, h.category)
                Column(Modifier.offset { IntOffset((cx + p.x * px).toInt(), (cy + p.y * px).toInt()) }.wrapContentSize()
                    .graphicsLayer { translationX = -size.width / 2; translationY = -size.height / 2; alpha = if (focus != null && focus != h.category) 0.35f else out }
                    .pressable { Haptics.light(view); focus = if (focus == h.category) null else h.category; onSelect(null) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val focused = focus == h.category
                    Box(Modifier.size(50.dp).pufyGlass(CircleShape, tint = if (focused) c.primary else null), contentAlignment = Alignment.Center) {
                        Icon(categoryIcons[h.category] ?: Icons.Outlined.GridView, null, Modifier.size(20.dp), tint = if (focused) c.onPrimary else c.text)
                    }
                    Text(MemoryStore.categoryTitle(h.category), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                    Text("${h.count}", fontSize = 11.sp, color = c.secondaryText)
                }
            }
            // Merkez: sen
            CenterNode(Modifier.offset { IntOffset(cx.toInt(), cy.toInt()) }.wrapContentSize().graphicsLayer { translationX = -size.width / 2; translationY = -size.height / 2 }
                .pressable { focus = null; onSelect(null) })
        }
        if (selected == null) GlassIconButton(Icons.Rounded.CenterFocusStrong, if (scale < 0.95f) stringResource(R.string.focus_on_me) else stringResource(R.string.show_full_network), modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)) {
            if (scale < 0.95f) { scale = 1f; pan = Offset.Zero } else {
                val fit = (minOf(constraints.maxWidth, constraints.maxHeight) / 2f) / ((extent + 70) * px)
                scale = fit.coerceIn(0.35f, 1f); pan = Offset.Zero
            }
        }
        if (focus != null) Row(Modifier.align(Alignment.TopEnd).padding(12.dp).pufyGlass(CircleShape).pressable { focus = null }.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(Icons.Rounded.Close, null, Modifier.size(12.dp), tint = c.text); Text(stringResource(R.string.all), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.text)
        }
    }
}

@Composable
private fun CenterNode(modifier: Modifier) {
    val c = Pufy.colors
    val name by Profile.nameFlow.collectAsState()
    val v by Profile.avatarVersion.collectAsState()
    val avatar = remember(v) { Profile.avatarBytes()?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(78.dp).graphicsLayer { shadowElevation = 12.dp.toPx(); shape = CircleShape; clip = true }.background(c.primary)
            .border(3.dp, c.background, CircleShape), contentAlignment = Alignment.Center) {
            if (avatar != null) Image(avatar, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else Text(name.take(1).uppercase(TR).ifEmpty { if (com.pufy.app.core.AppLocales.isEnglish()) "Y" else "S" }, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = c.onPrimary)
        }
        Text(name.ifEmpty { if (com.pufy.app.core.AppLocales.isEnglish()) "You" else "Sen" }, style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold), color = c.text)
    }
}

@Composable
private fun LeafNode(item: JsonObject, selected: Boolean, onTap: () -> Unit) {
    val c = Pufy.colors
    val imp = MemoryStore.importance(item)
    val size = when (imp) { 5 -> 14; 4 -> 13; else -> 12 }.sp
    if (MemoryStore.category(item) == "people") {
        Column(Modifier.widthIn(max = 100.dp).pressable(onClick = onTap), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(Modifier.size(36.dp).pufyGlass(CircleShape, tint = if (selected) c.primary else null), contentAlignment = Alignment.Center) {
                Text((item.str("entity") ?: item.str("text") ?: "").split(" ").take(2).mapNotNull { it.firstOrNull()?.toString() }.joinToString("").uppercase(TR),
                    fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (selected) c.onPrimary else c.text)
            }
            Text(item.str("text") ?: "", fontSize = size, fontWeight = FontWeight.SemiBold, color = c.text, textAlign = TextAlign.Center)
            item.str("relation")?.let { Text(it, fontSize = 10.sp, color = c.secondaryText) }
        }
    } else {
        Text(item.str("text") ?: "", fontSize = size, fontWeight = if (imp >= 4) FontWeight.SemiBold else FontWeight.Medium, maxLines = 2, textAlign = TextAlign.Center,
            color = if (selected) c.onPrimary else c.text,
            modifier = Modifier.widthIn(max = 104.dp).pufyGlass(CircleShape, tint = if (selected) c.primary else null)
                .let { if (imp >= 4 && !selected) it.border(0.8.dp, c.text.copy(alpha = 0.18f), CircleShape) else it }
                .pressable(onClick = onTap).padding(horizontal = 10.dp, vertical = 6.dp))
    }
}

@Composable
private fun Dots(value: Int) {
    val c = Pufy.colors
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) { repeat(5) { i -> Box(Modifier.size(6.dp).clip(CircleShape).background(c.text.copy(alpha = if (i < value) 0.8f else 0.15f))) } }
}

@Composable
private fun DetailCard(item: JsonObject, onEdit: () -> Unit, onDelete: () -> Unit, onClose: () -> Unit) {
    val c = Pufy.colors
    val cat = MemoryStore.category(item)
    Column(Modifier.fillMaxWidth().pufyGlass(RoundedCornerShape(26.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(categoryIcons[cat] ?: Icons.Outlined.GridView, null, Modifier.size(14.dp), tint = c.secondaryText)
            Text(MemoryStore.categoryTitle(cat), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, modifier = Modifier.weight(1f))
            Dots(MemoryStore.importance(item))
            Box(Modifier.size(28.dp).pressable(onClick = onClose), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Close, stringResource(R.string.close), Modifier.size(14.dp), tint = c.secondaryText) }
        }
        Text(item.str("text") ?: "", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.text)
        item.str("relation")?.let { Text(it.replaceFirstChar { ch -> ch.titlecase(TR) }, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text) }
        Text(item.str("detail") ?: "", style = PufyType.body, color = c.secondaryText)
        Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).clip(CircleShape).background(c.soft).pressable(onClick = onEdit).padding(vertical = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Edit, null, Modifier.size(15.dp), tint = c.text); Text(" ${stringResource(R.string.edit)}", style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
            }
            Row(Modifier.weight(1f).clip(CircleShape).background(androidx.compose.ui.graphics.Color(0xFFFF3B30).copy(alpha = 0.1f)).pressable(onClick = onDelete).padding(vertical = 10.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Delete, null, Modifier.size(15.dp), tint = androidx.compose.ui.graphics.Color(0xFFFF3B30))
                Text(" ${stringResource(R.string.forget)}", style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = androidx.compose.ui.graphics.Color(0xFFFF3B30))
            }
        }
    }
}

@Composable
private fun MemoryList(items: List<JsonObject>, onEdit: (JsonObject) -> Unit) {
    val c = Pufy.colors
    val groups = remember(items) { items.groupBy { MemoryStore.category(it) }.toList().sortedBy { MemoryStore.categoryOrder.indexOf(it.first) } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        groups.forEach { (key, list) ->
            com.pufy.app.ui.settings.Group(MemoryStore.categoryTitle(key)) {
                list.sortedByDescending { MemoryStore.importance(it) }.forEachIndexed { i, item ->
                    Row(Modifier.fillMaxWidth().pressable(scale = 0.99f) { onEdit(item) }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(item.str("text") ?: "", style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                            item.str("detail")?.takeIf { it != item.str("text") }?.let { Text(it, style = PufyType.footnote, color = c.secondaryText) }
                        }
                        Dots(MemoryStore.importance(item))
                    }
                    if (i < list.size - 1) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator.copy(alpha = 0.5f))
                }
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}

/** Bilgi ekle / düzenle (iOS MemoryEditorView) */
@Composable
private fun MemoryEditor(item: JsonObject?, onDone: () -> Unit) {
    val c = Pufy.colors
    var text by remember { mutableStateOf(item?.str("text") ?: "") }
    var detail by remember { mutableStateOf(item?.str("detail") ?: "") }
    var category by remember { mutableStateOf(item?.let { MemoryStore.category(it) } ?: "identity") }
    var importance by remember { mutableStateOf(item?.let { MemoryStore.importance(it) } ?: 3) }
    AlertDialog(onDismissRequest = onDone, title = { Text(if (item == null) stringResource(R.string.add_info) else stringResource(R.string.edit)) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            listOf(stringResource(R.string.short_title) to text, stringResource(R.string.description) to detail).forEachIndexed { i, (label, value) ->
                Column {
                    Text(label, style = PufyType.caption, color = c.secondaryText)
                    BasicTextField(value, { if (i == 0) text = it else detail = it }, textStyle = PufyType.body.copy(color = c.text), cursorBrush = androidx.compose.ui.graphics.SolidColor(c.text),
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.soft).padding(10.dp))
                }
            }
            Text(stringResource(R.string.category), style = PufyType.caption, color = c.secondaryText)
            androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                MemoryStore.categoryOrder.forEach { k ->
                    Text(MemoryStore.categoryTitle(k), fontSize = 13.sp, color = if (k == category) c.onPrimary else c.text,
                        modifier = Modifier.clip(CircleShape).background(if (k == category) c.primary else c.soft).pressable { category = k }.padding(horizontal = 10.dp, vertical = 6.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.importance), style = PufyType.caption, color = c.secondaryText, modifier = Modifier.weight(1f))
                (1..5).forEach { v -> Box(Modifier.size(30.dp).pressable { importance = v }, contentAlignment = Alignment.Center) {
                    Box(Modifier.size(12.dp).clip(CircleShape).background(c.text.copy(alpha = if (v <= importance) 0.85f else 0.15f))) } }
            }
        }
    }, confirmButton = {
        TextButton({
            val t = text.trim(); val d = detail.trim().ifEmpty { t }
            if (t.isNotEmpty()) {
                val now = nowSwift()
                val base: Map<String, JsonElement> = item ?: mapOf("id" to JsonPrimitive(newID()), "isManual" to JsonPrimitive(true), "createdAt" to JsonPrimitive(now),
                    "keywords" to JsonArray(emptyList()), "weight" to JsonPrimitive(0.5), "angle" to JsonPrimitive(0), "icon" to JsonPrimitive("sparkle"))
                MemoryStore.upsert(JsonObject(LinkedHashMap(base).apply {
                    put("text", JsonPrimitive(t)); put("detail", JsonPrimitive(d)); put("category", JsonPrimitive(category))
                    put("importance", JsonPrimitive(importance)); put("updatedAt", JsonPrimitive(now))
                }))
            }
            onDone()
        }) { Text(stringResource(R.string.save)) }
    }, dismissButton = { TextButton(onDone) { Text(stringResource(R.string.cancel)) } })
}

