package com.pufy.app.ui.switcher

import androidx.compose.foundation.layout.widthIn
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.GridOn
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.ViewCarousel
import androidx.compose.material.icons.rounded.Add
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.testTag
import com.pufy.app.R
import com.pufy.app.data.MiniApp
import com.pufy.app.data.MiniAppStore
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.chat.ChatScreen
import com.pufy.app.ui.components.AppIconTile
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.Symbols
import com.pufy.app.ui.components.colorFromHex
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import com.pufy.app.ui.theme.supportsBlur
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlin.math.abs

// iOS TabSwitcherView karşılığı: ızgara (ana ekran gibi) ya da kart görünümü; açık uygulamalar ve sohbet

private sealed interface Tab { val key: String
    data object Chat : Tab { override val key = "chat" }
    data class App(val app: MiniApp) : Tab { override val key = app.id }
}

@Composable
fun TabSwitcher(onCreate: () -> Unit, onEdit: (MiniApp) -> Unit) {
    val c = Pufy.colors
    val apps by MiniAppStore.apps.collectAsState()
    val activeID by AppNav.activeAppID.collectAsState()
    var listMode by remember { mutableStateOf(!AppNav.switcherOpensInCards) }
    var pendingDelete by remember { mutableStateOf<MiniApp?>(null) }
    val tabs = remember(apps, pendingDelete) { listOf<Tab>(Tab.Chat) + apps.filter { it.id != pendingDelete?.id }.map { Tab.App(it) } }

    LaunchedEffect(pendingDelete) {
        val app = pendingDelete ?: return@LaunchedEffect
        delay(4000)
        if (AppNav.activeAppID.value == app.id) AppNav.activeAppID.value = null
        MiniAppStore.delete(app.id); pendingDelete = null
    }

    // Buzlu cam zemin: arkadaki ekran bulanık ve büyük ölçüde örtülü (iOS ultraThinMaterial + karartma); kenarda şerit kalmaz
    Box(Modifier.fillMaxSize().background(if (c.isDark) Color(0xFF0B0B0C).copy(alpha = if (supportsBlur) 0.9f else 0.97f) else Color(0xFFF2F2F7).copy(alpha = if (supportsBlur) 0.93f else 0.97f))) {
        // Alttaki ekrana dokunuşun geçmesini engelleyen zemin katmanı (alt butonları engellememesi için Column'un altında)
        Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { } })
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 22.dp, top = 8.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.apps), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.text)
                Spacer(Modifier.weight(1f))
                GlassIconButton(if (listMode) Icons.Outlined.ViewCarousel else Icons.Outlined.GridOn, if (listMode) stringResource(R.string.card_view) else stringResource(R.string.grid_view),
                    size = 40.dp, iconSize = 18.dp) { listMode = !listMode }
            }
            AnimatedContent(listMode, Modifier.weight(1f), label = "mode", transitionSpec = { fadeIn() togetherWith fadeOut() }) { grid ->
                if (grid) Grid(tabs, activeID, onCreate, onEdit, onDelete = { pendingDelete = it })
                else Cards(tabs, activeID, onCreate, onDelete = { pendingDelete = it })
            }
            // Alt bar
            Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 10.dp, bottom = 20.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.weight(1f).height(52.dp).pufyGlass(CircleShape).pressable { AppNav.switcherVisible.value = false }, contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.close), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.text)
                }
                Box(Modifier.size(52.dp).clip(CircleShape).background(c.primary).pressable(onClick = onCreate), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Add, stringResource(R.string.new_app), Modifier.size(24.dp), tint = c.onPrimary)
                }
            }
        }
        var hintNewAppShown by remember { mutableStateOf(com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN)) }
        if (!hintNewAppShown && listMode) {
            com.pufy.app.ui.coach.HintBubble(
                text = stringResource(R.string.hint_new_app),
                onDismiss = {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN, true)
                    hintNewAppShown = true
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(start = 24.dp, end = 24.dp, bottom = 86.dp)
                    .navigationBarsPadding()
            )
            LaunchedEffect(Unit) {
                kotlinx.coroutines.delay(8000)
                com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN, true)
                hintNewAppShown = true
            }
        }
        AnimatedVisibility(pendingDelete != null, Modifier.align(Alignment.BottomCenter).padding(bottom = 110.dp).navigationBarsPadding(),
            enter = fadeIn() + slideInVertically { it }, exit = fadeOut() + slideOutVertically { it }) {
            Row(Modifier.pufyGlass(CircleShape).padding(start = 18.dp, end = 6.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Outlined.Delete, null, Modifier.size(16.dp), tint = c.secondaryText)
                Text(stringResource(R.string.app_deleted, pendingDelete?.name ?: ""), style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
                Text(stringResource(R.string.undo), style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold), color = c.onPrimary,
                    modifier = Modifier.clip(CircleShape).background(c.primary).pressable { pendingDelete = null }.padding(horizontal = 14.dp, vertical = 7.dp))
            }
        }
    }
}

private fun open(tab: Tab) = when (tab) { Tab.Chat -> AppNav.openChat(); is Tab.App -> AppNav.openApp(tab.app.id) }

// MARK: Izgara

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Grid(tabs: List<Tab>, activeID: String?, onCreate: () -> Unit, onEdit: (MiniApp) -> Unit, onDelete: (MiniApp) -> Unit) {
    val c = Pufy.colors
    val width = LocalConfiguration.current.screenWidthDp
    val columns = if (width > 950) 6 else if (width > 650) 5 else 4
    var confirm by remember { mutableStateOf<MiniApp?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current
    LazyVerticalGrid(GridCells.Fixed(columns), Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 34.dp, bottom = 28.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        items(tabs, key = { it.key }) { tab ->
            var menu by remember { mutableStateOf(false) }
            val active = (tab is Tab.Chat && activeID == null) || (tab is Tab.App && tab.app.id == activeID)
            Box(Modifier.animateItem()) {
                Column(Modifier.fillMaxWidth().pressable(scale = 0.92f) { open(tab) }
                    .let { m -> if (tab is Tab.App) m.combinedClickable(onLongClick = { menu = true }) { open(tab) } else m },
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(contentAlignment = Alignment.BottomCenter) {
                        when (tab) {
                            Tab.Chat -> Box(Modifier.size(68.dp).clip(RoundedCornerShape(18.dp)).background(Color.White).border(0.5.dp, Color.Black.copy(alpha = 0.08f), RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                                Image(painterResource(R.drawable.pufy_logo), null, Modifier.size(58.dp), contentScale = ContentScale.Fit)
                            }
                            is Tab.App -> AppIconTile(tab.app.icon, tab.app.colorHex, 68.dp)
                        }
                    }
                    Box(Modifier.padding(top = 4.dp).size(5.dp).clip(CircleShape).background(if (active) c.text else Color.Transparent))
                    Text(if (tab is Tab.App) tab.app.name else "Pufy", style = PufyType.caption, color = c.text, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
                }
                if (tab is Tab.App) DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text(stringResource(R.string.edit)) }, onClick = { menu = false; onEdit(tab.app) }, leadingIcon = { Icon(Icons.Outlined.Edit, null) })
                    DropdownMenuItem({ Text(stringResource(R.string.delete), color = Color(0xFFFF3B30)) }, onClick = { menu = false; confirm = tab.app },
                        leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = Color(0xFFFF3B30)) })
                }
            }
        }
        item(key = "new") {
            Column(Modifier.pressable(scale = 0.92f, onClick = onCreate), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(68.dp).drawBehind {
                    drawRoundRect(c.secondaryText, cornerRadius = CornerRadius(18.dp.toPx()),
                        style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 6.dp.toPx()))))
                }, contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Add, null, Modifier.size(28.dp), tint = c.secondaryText) }
                Text(stringResource(R.string.new_item), style = PufyType.caption, color = c.secondaryText, modifier = Modifier.padding(top = 11.dp))
            }
        }
    }
    confirm?.let { app ->
        AlertDialog({ confirm = null }, title = { Text(stringResource(R.string.delete_app_confirm_title, app.name)) }, text = { Text(stringResource(R.string.delete_app_confirm_message)) },
            confirmButton = { TextButton({ confirm = null; onDelete(app) }) { Text(stringResource(R.string.delete), color = Color(0xFFFF3B30)) } },
            dismissButton = { TextButton({ confirm = null }) { Text(stringResource(R.string.cancel)) } })
    }
}

// MARK: Kartlar

@Composable
private fun Cards(tabs: List<Tab>, activeID: String?, onCreate: () -> Unit, onDelete: (MiniApp) -> Unit) {
    val view = LocalView.current
    val startIndex = remember { tabs.indexOfFirst { (it is Tab.Chat && activeID == null) || (it is Tab.App && it.app.id == activeID) }.coerceAtLeast(0) }
    val pager = rememberPagerState(startIndex) { tabs.size + 1 }
    LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.drop(1).collect { Haptics.light(view) } }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val screen = LocalConfiguration.current
        val aspect = screen.screenHeightDp.toFloat() / screen.screenWidthDp.coerceAtLeast(1)
        var cardW = if (screen.screenWidthDp > 700) minOf(maxWidth.value * 0.62f, 760f) else minOf(maxWidth.value * 0.70f, 360f)
        var cardH = cardW * aspect
        val maxH = maxOf(maxHeight.value - 72 - 54 - 20, 160f)
        if (cardH > maxH) { cardH = maxH; cardW = cardH / aspect }
        val side = ((maxWidth.value - cardW) / 2).dp

        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            HorizontalPager(
                state = pager,
                modifier = Modifier.fillMaxWidth().height((cardH + 72).dp),
                contentPadding = PaddingValues(horizontal = side),
                pageSpacing = 18.dp,
                beyondViewportPageCount = 1,
                key = { if (it < tabs.size) tabs[it].key else "new" }
            ) { page ->
                val offset = abs((pager.currentPage - page) + pager.currentPageOffsetFraction).coerceIn(0f, 1f)
                Box(Modifier.fillMaxHeight().graphicsLayer { val s = 1 - offset * 0.10f; scaleX = s; scaleY = s; alpha = 1 - offset * 0.45f }, contentAlignment = Alignment.Center) {
                    if (page < tabs.size) {
                        val tab = tabs[page]
                        val active = (tab is Tab.Chat && activeID == null) || (tab is Tab.App && tab.app.id == activeID)
                        SwitcherCard(tab, active, cardW, cardH, aspect, onOpen = { Haptics.medium(view); open(tab) },
                            onDelete = if (tab is Tab.App) ({ onDelete(tab.app) }) else null)
                    } else NewAppCard(cardW, cardH, onCreate)
                }
            }
            Spacer(Modifier.height(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(tabs.size + 1) { i ->
                    val w by animateDpAsState(if (i == pager.currentPage) 18.dp else 6.dp, Springs.quick(), label = "dot")
                    Box(Modifier.width(w).height(6.dp).clip(CircleShape).background(Pufy.colors.text.copy(alpha = if (i == pager.currentPage) 1f else 0.2f)))
                }
            }
        }
    }
}

@Composable
private fun SwitcherCard(tab: Tab, active: Boolean, w: Float, h: Float, aspect: Float, onOpen: () -> Unit, onDelete: (() -> Unit)?) {
    val c = Pufy.colors
    val scope = rememberCoroutineScope()
    val drag = remember { Animatable(0f) }
    val density = LocalDensity.current
    val hPx = with(density) { h.dp.toPx() }
    val progress = (-drag.value / (hPx * 0.6f)).coerceIn(0f, 1f)
    Column(Modifier.offset { IntOffset(0, drag.value.toInt()) }
        .graphicsLayer { val s = 1 - progress * 0.08f; scaleX = s; scaleY = s; alpha = 1 - progress * 0.35f }
        .pointerInput(onDelete) {
            var velocityTracker = 0f
            detectVerticalDragGestures(onDragEnd = {
                val dy = drag.value
                scope.launch {
                    if (onDelete != null && (dy < -hPx * 0.28f || dy + velocityTracker * 6 < -hPx * 0.8f)) {
                        drag.animateTo(-hPx * 1.5f, tween(200)); onDelete(); drag.snapTo(0f)
                    } else drag.animateTo(0f, Springs.standard())
                }
            }) { change, amount ->
                change.consume(); velocityTracker = amount
                scope.launch { drag.snapTo(drag.value + if (amount < 0 && onDelete != null) amount else amount * 0.22f) }
            }
        }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.width(w.dp).height(26.dp).graphicsLayer { alpha = 1 - progress }, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            when (tab) {
                Tab.Chat -> Image(painterResource(R.drawable.chat_pp), null, Modifier.size(26.dp).clip(RoundedCornerShape(7.dp)), contentScale = ContentScale.Crop)
                is Tab.App -> AppIconTile(tab.app.icon, tab.app.colorHex, 26.dp)
            }
            Text(if (tab is Tab.App) tab.app.name else "Pufy", style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, maxLines = 1)
            if (active) Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFF34C759)))
        }
        val shape = RoundedCornerShape(30.dp)
        val shadowAlpha = (1 - progress).coerceIn(0f, 1f)
        Box(Modifier.size(w.dp, h.dp).graphicsLayer {
            shadowElevation = (20.dp.toPx() * shadowAlpha).coerceAtLeast(0f)
            this.shape = shape
            clip = true
        }.border(BorderStroke(0.5.dp, c.text.copy(alpha = 0.06f)), shape).background(c.background)) {
            when (tab) {
                // Sohbetin canlı küçük önizlemesi (ekran boyutunda çizilip küçültülür)
                Tab.Chat -> {
                    val screenW = LocalConfiguration.current.screenWidthDp.toFloat()
                    val scale = w / screenW
                    Box(Modifier.requiredSize(screenW.dp, (h / scale).dp).graphicsLayer { scaleX = scale; scaleY = scale }) {
                        ChatScreen(onOpenMenu = {}, onOpenApps = {}, preview = true)
                    }
                }
                is Tab.App -> AppCover(tab.app, w, h)
            }
            // En üst katmanda şeffaf dokunma kutusu: tüm dokunuşları alıp onOpen'ı tetikler; önizlemenin içi dokunuş almaz
            Box(
                Modifier
                    .matchParentSize()
                    .pressable(scale = 0.98f, onClick = onOpen)
                    .let { if (tab is Tab.Chat) it.testTag("switcher-card-chat") else it }
            )
        }
    }
}

@Composable
private fun AppCover(app: MiniApp, w: Float, h: Float) {
    val tint = colorFromHex(app.colorHex) ?: Pufy.colors.primary
    val s = minOf(w, h * 0.9f)
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(tint.copy(alpha = 0.95f), tint.copy(alpha = 0.55f))))) {
        Icon(Symbols.icon(app.icon), null, Modifier.align(Alignment.TopEnd).offset((s * 0.25f).dp, (-s * 0.05f).dp).size((s * 0.9f).dp)
            .graphicsLayer { rotationZ = -14f }, tint = Color.White.copy(alpha = 0.10f))
        Column(Modifier.align(Alignment.BottomStart).padding(maxOf(16f, s * 0.07f).dp), verticalArrangement = Arrangement.spacedBy(maxOf(8f, s * 0.03f).dp)) {
            AppIconTile(app.icon, app.colorHex, (s * 0.19f).coerceIn(44f, 96f).dp,
                Modifier.border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(((s * 0.19f).coerceIn(44f, 96f) * 0.26f).dp)))
            Text(app.name, fontSize = (s * 0.085f).coerceIn(20f, 40f).sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 2)
            if (app.description.isNotBlank()) Text(app.description, fontSize = (s * 0.048f).coerceIn(13f, 20f).sp, color = Color.White.copy(alpha = 0.85f), maxLines = 3)
        }
    }
}

@Composable
private fun NewAppCard(w: Float, h: Float, onCreate: () -> Unit) {
    val c = Pufy.colors
    var hintNewAppShown by remember { mutableStateOf(com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN)) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        if (!hintNewAppShown) {
            com.pufy.app.ui.coach.HintBubble(
                text = stringResource(R.string.hint_new_app),
                onDismiss = {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN, true)
                    hintNewAppShown = true
                },
                modifier = Modifier.widthIn(max = w.dp)
            )
            LaunchedEffect(Unit) {
                kotlinx.coroutines.delay(8000)
                com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN, true)
                hintNewAppShown = true
            }
        } else {
            Spacer(Modifier.height(26.dp))
        }
        Box(Modifier.size(w.dp, h.dp).clip(RoundedCornerShape(30.dp)).background(c.text.copy(alpha = 0.03f)).drawBehind {
            drawRoundRect(c.text.copy(alpha = 0.25f), cornerRadius = CornerRadius(30.dp.toPx()),
                style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8.dp.toPx(), 6.dp.toPx()))))
        }.pressable(scale = 0.98f, onClick = onCreate), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(64.dp).clip(CircleShape).background(c.soft), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(30.dp), tint = c.text)
                }
                Text(stringResource(R.string.new_app), style = PufyType.headline, color = c.text)
                Text(stringResource(R.string.apps_tagline), style = PufyType.subheadline, color = c.secondaryText)
            }
        }
    }
}
