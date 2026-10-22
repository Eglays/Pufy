package com.pufy.app.ui

import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.ui.draw.clip
import com.pufy.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Column
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.ui.draw.blur
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.pufy.app.ai.ChatEngine
import com.pufy.app.data.MiniAppStore
import com.pufy.app.ui.chat.ChatScreen
import com.pufy.app.ui.chat.ImageViewerState
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.menu.SideMenu
import com.pufy.app.ui.miniapp.MiniAppScreen
import com.pufy.app.ui.notes.MemoryBookScreen
import com.pufy.app.ui.notes.NoteScreen
import com.pufy.app.ui.settings.SettingsScreen
import com.pufy.app.ui.switcher.TabSwitcher
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.hypot

// iOS ContentView karşılığı: sohbet + kayan menü (kart gibi kayar), uygulama değiştirici, mini uygulamalar, sayfalar

@Composable
fun RootScreen() {
    val c = Pufy.colors
    val activeAppID by AppNav.activeAppID.collectAsState()
    val switcher by AppNav.switcherVisible.collectAsState()
    val settings by AppNav.settingsVisible.collectAsState()
    val noteID by AppNav.openNoteID.collectAsState()
    val memoryBook by AppNav.memoryBookVisible.collectAsState()
    val apps by MiniAppStore.apps.collectAsState()
    val activeApp = apps.firstOrNull { it.id == activeAppID }
    val focus = LocalFocusManager.current
    val view = LocalView.current

    LaunchedEffect(Unit) { if (ChatEngine.currentSessionID.value == null) ChatEngine.newSession() }
    // pufy://share/<kod> → paylaşılan uygulama; pufy://app/<klasör> → uygulamayı aç
    val link by com.pufy.app.DeepLinks.pending.collectAsState()
    LaunchedEffect(link) {
        val uri = link ?: return@LaunchedEffect
        com.pufy.app.DeepLinks.pending.value = null
        val segs = listOfNotNull(uri.host) + uri.pathSegments
        when (segs.firstOrNull()) {
            "app" -> segs.getOrNull(1)?.let { f -> MiniAppStore.apps.value.firstOrNull { it.folderName == f || it.id == f }?.let { AppNav.openApp(it.id) } }
        }
    }
    var pinch by remember { mutableFloatStateOf(1f) }
    LaunchedEffect(switcher) {
        pinch = 1f
        if (switcher) { focus.clearFocus(); Haptics.light(view) }
    }

    var confirmExit by remember { mutableStateOf(false) }

    // Geri tuşu: önce açık sayfa, sonra değiştirici, menü, mini uygulama; en son ana ekranda çıkış onayı
    val sideMenuOpen by AppNav.sideMenuOpen.collectAsState()
    val creatorReq by AppNav.creator.collectAsState()
    val editingRem by AppNav.editingReminder.collectAsState()

    BackHandler(enabled = true) {
        when {
            confirmExit -> confirmExit = false
            ImageViewerState.image.value != null -> ImageViewerState.image.value = null
            creatorReq != null -> AppNav.creator.value = null
            editingRem != null -> AppNav.editingReminder.value = null
            com.pufy.app.ui.chat.DeckViewerState.deck.value != null -> com.pufy.app.ui.chat.DeckViewerState.deck.value = null
            noteID != null -> AppNav.openNoteID.value = null
            settings -> AppNav.settingsVisible.value = false
            memoryBook -> AppNav.memoryBookVisible.value = false
            switcher -> AppNav.switcherVisible.value = false
            sideMenuOpen -> AppNav.sideMenuOpen.value = false
            activeApp != null -> AppNav.openChat()
            else -> confirmExit = true
        }
    }

    if (confirmExit) {
        val context = androidx.compose.ui.platform.LocalContext.current
        AlertDialog(
            onDismissRequest = { confirmExit = false },
            title = { Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.exit_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmExit = false
                    (context as? android.app.Activity)?.finish()
                }) {
                    Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.exit), color = androidx.compose.ui.graphics.Color(0xFFFF3B30))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmExit = false }) {
                    Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.cancel))
                }
            }
        )
    }

    val switcherScale by animateFloatAsState(if (switcher) 0.88f else if (pinch < 1f) pinch.coerceAtLeast(0.7f) else 1f, Springs.standard(), label = "scale")

    Box(Modifier.fillMaxSize().background(c.background)) {
        // Değiştirici açıkken arkadaki ekran buzlu cam gibi bulanıklaşır (iOS ultraThinMaterial); 0dp'de katman oluşturmaz
        val blur by animateDpAsState(if (switcher) 28.dp else 0.dp, Springs.standard(), label = "blur")
        val blurModifier = if (blur > 0.dp) Modifier.blur(blur) else Modifier
        Box(Modifier.fillMaxSize().graphicsLayer { scaleX = switcherScale; scaleY = switcherScale }.then(blurModifier)
            .pinchToSwitcher(enabled = !switcher && activeApp == null, onScale = { pinch = it }) { AppNav.showSwitcher(cards = true) }) {
            AnimatedContent(activeApp?.id, label = "tab", transitionSpec = {
                (fadeIn(Springs.standard()) + scaleIn(Springs.standard(), initialScale = 0.96f)) togetherWith fadeOut(Springs.quick())
            }) { id ->
                val app = apps.firstOrNull { it.id == id }
                if (app == null) ChatWithMenu() else MiniAppScreen(app) { a, fix -> AppNav.creator.value = AppNav.CreatorRequest(a.id, fix) }
            }
        }

        ErrorBanner(Modifier.align(Alignment.TopCenter))

        AnimatedVisibility(switcher, enter = fadeIn(Springs.standard()), exit = fadeOut(Springs.standard())) {
            TabSwitcher(onCreate = { AppNav.creator.value = AppNav.CreatorRequest(null) }, onEdit = { AppNav.creator.value = AppNav.CreatorRequest(it.id) })
        }

        val creator by AppNav.creator.collectAsState()
        Page(creator != null) {
            creator?.let { req ->
                val session = remember(req) { com.pufy.app.apps.Creator.session(req.appID?.let { MiniAppStore.app(it) }) }
                fun close() { com.pufy.app.apps.Creator.release(session); AppNav.creator.value = null }
                com.pufy.app.ui.creator.CreatorScreen(session, req.prompt, req.initialName, req.autoSend, onClose = ::close) { id -> close(); AppNav.openApp(id) }
            }
        }
        val editingReminder by AppNav.editingReminder.collectAsState()
        Page(editingReminder != null) { editingReminder?.let { r -> com.pufy.app.ui.notes.ReminderEditor(r) { AppNav.editingReminder.value = null } } }
        Page(settings) { SettingsScreen { AppNav.settingsVisible.value = false } }
        Page(memoryBook) { MemoryBookScreen { AppNav.memoryBookVisible.value = false } }
        Page(noteID != null) { noteID?.let { NoteScreen(it) { AppNav.openNoteID.value = null } } }
        Page(com.pufy.app.ui.chat.DeckViewerState.deck.value != null) {
            com.pufy.app.ui.chat.DeckViewerState.deck.value?.let { d -> com.pufy.app.ui.chat.SlideDeckViewer(d) { com.pufy.app.ui.chat.DeckViewerState.deck.value = null } }
        }
        ImageViewer()
        val onboarding by AppNav.onboarding.collectAsState()
        val onboardingStep by AppNav.onboardingStep.collectAsState()
        var coachMarksDone by remember { mutableStateOf(com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.COACH_MARKS_COMPLETED)) }
        LaunchedEffect(settings, onboarding) {
            coachMarksDone = com.pufy.app.core.Settings.bool(com.pufy.app.core.Settings.COACH_MARKS_COMPLETED)
        }

        val showCoachMarks = !onboarding && !coachMarksDone && activeApp == null && !switcher &&
                !settings && !memoryBook && creator == null && editingReminder == null && noteID == null && !sideMenuOpen

        if (showCoachMarks) {
            com.pufy.app.ui.coach.CoachMarksOverlay(
                onDismiss = {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.COACH_MARKS_COMPLETED, true)
                    coachMarksDone = true
                }
            )
        }

        androidx.compose.animation.AnimatedVisibility(onboarding, enter = fadeIn(), exit = fadeOut()) {
            com.pufy.app.ui.onboarding.OnboardingScreen(needsSetup = !com.pufy.app.ai.AiClient.isConfigured,
                initialStep = onboardingStep,
                onFinish = {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.ONBOARDING_DONE, true)
                    AppNav.onboarding.value = false
                    AppNav.onboardingStep.value = com.pufy.app.ui.onboarding.OnboardingStep.INTRO
                },
                onOpenSettings = { AppNav.settingsVisible.value = true })
        }
    }

}

/** Alttan kayarak açılan tam ekran sayfa (iOS sheet) */
@Composable
private fun Page(visible: Boolean, content: @Composable () -> Unit) {
    AnimatedVisibility(visible, enter = slideInVertically(Springs.standard()) { it } + fadeIn(), exit = slideOutVertically(Springs.standard()) { it } + fadeOut()) {
        Box(Modifier.fillMaxSize().background(Pufy.colors.background)
            .pointerInput(Unit) { detectTapGestures { } }) { content() }   // alttaki ekrana dokunuş geçmesin
    }
}

// MARK: Sohbet + kart gibi kayan menü (iOS chatWithSideMenu)

@Composable
private fun ChatWithMenu() {
    val c = Pufy.colors
    val open by AppNav.sideMenuOpen.collectAsState()
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val density = LocalDensity.current

    BoxWithConstraints(Modifier.fillMaxSize().background(c.background)) {
        val widthPx = with(density) { maxWidth.toPx() }
        val menuW = minOf(widthPx * 0.84f, with(density) { 380.dp.toPx() })
        val reveal = remember { Animatable(0f) }
        LaunchedEffect(open, menuW) { reveal.animateTo(if (open) menuW else 0f, Springs.standard()) }
        val progress = (reveal.value / menuW).coerceIn(0f, 1f)

        // Menü: kartın altında, biraz geriden gelir
        Box(Modifier.width(with(density) { menuW.toDp() }).fillMaxHeight()
            .offset { IntOffset(((reveal.value - menuW) * 0.25f).toInt(), 0) }) {
            SideMenu(onClose = { AppNav.sideMenuOpen.value = false })
        }

        val corner = (46 * progress).dp
        Box(Modifier.fillMaxSize()
            .offset { IntOffset(reveal.value.toInt(), 0) }
            .graphicsLayer {
                shadowElevation = 26.dp.toPx() * progress
                shape = RoundedCornerShape(corner)
                clip = progress > 0f
            }
            .background(c.background)
            .pointerInput(menuW) {
                var total = 0f
                detectHorizontalDragGestures(
                    onDragStart = { total = 0f },
                    onDragEnd = {
                        scope.launch {
                            val wasOpen = AppNav.sideMenuOpen.value
                            val target = if (!wasOpen) total > menuW * 0.3f || reveal.value > menuW * 0.5f else !(total < -menuW * 0.3f || reveal.value < menuW * 0.5f)
                            if (target && !wasOpen) focus.clearFocus()
                            AppNav.sideMenuOpen.value = target
                            reveal.animateTo(if (target) menuW else 0f, Springs.standard())
                        }
                    },
                    onDragCancel = { scope.launch { reveal.animateTo(if (AppNav.sideMenuOpen.value) menuW else 0f, Springs.standard()) } },
                ) { change, amount ->
                    total += amount
                    // Kapalıyken: sağa çekince açılır; açıkken sola çekince kapanır
                    if (!AppNav.sideMenuOpen.value && total < 0 && reveal.value == 0f) return@detectHorizontalDragGestures
                    change.consume()
                    scope.launch { reveal.snapTo((reveal.value + amount).coerceIn(0f, menuW)) }
                }
            }) {
            ChatScreen(onOpenMenu = { AppNav.sideMenuOpen.value = true }, onOpenApps = { AppNav.showSwitcher() })
            if (progress > 0.001f) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.06f * progress))
                .pointerInput(Unit) { detectTapGestures { AppNav.sideMenuOpen.value = false } })
        }
    }
}

/** İki parmakla sıkıştırınca uygulama değiştirici (iOS MagnificationGesture < 0.82) — dokunuşları tüketmez */
private fun Modifier.pinchToSwitcher(enabled: Boolean, onScale: (Float) -> Unit, onTrigger: () -> Unit): Modifier = if (!enabled) this else pointerInput(Unit) {
    awaitEachGesture {
        try {
            awaitFirstDown(requireUnconsumed = false)
            var startDistance = 0f
            var fired = false
            while (true) {
                val event = awaitPointerEvent(androidx.compose.ui.input.pointer.PointerEventPass.Initial)
                val pressed = event.changes.filter { it.pressed }
                if (pressed.isEmpty()) break
                if (pressed.size >= 2) {
                    val (a, b) = pressed[0].position to pressed[1].position
                    val d = hypot(a.x - b.x, a.y - b.y)
                    if (startDistance == 0f) startDistance = d
                    val scale = d / startDistance
                    onScale(scale)
                    if (scale < 0.82f && !fired) { fired = true; onTrigger() }
                } else if (startDistance != 0f && pressed.none { it.positionChanged() }) Unit
            }
        } finally {
            onScale(1f)
        }
    }
}

@Composable
private fun ErrorBanner(modifier: Modifier) {
    val c = Pufy.colors
    val rawError by ChatEngine.error.collectAsState()
    val view = LocalView.current
    var showDetails by remember { mutableStateOf(false) }

    LaunchedEffect(rawError) {
        showDetails = false
        if (rawError != null) {
            Haptics.success(view)
            delay(8000)
            ChatEngine.clearError()
        }
    }

    val isEn = com.pufy.app.core.AppLocales.isEnglish()
    val parsed = remember(rawError, isEn) {
        val raw = rawError ?: return@remember ("" to "")
        val lower = raw.lowercase()
        val friendly = when {
            lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") || lower.contains("anahtar geçersiz") || lower.contains("invalid api key") || lower.contains("invalid_api_key") ->
                if (isEn) "API key is invalid or unauthorized. Please check your key." else "API anahtarı geçersiz ya da yetkisi yok. Anahtarını kontrol et."
            lower.contains("404") || lower.contains("model bulunamadı") || lower.contains("model_not_found") || lower.contains("not found") ->
                if (isEn) "Selected model was not found. Re-select via 'Fetch models' in Settings." else "Seçili model bulunamadı. Ayarlar'dan 'Modelleri getir' ile yeniden seç."
            lower.contains("429") || lower.contains("rate limit") || lower.contains("rate_limit") || lower.contains("resource_exhausted") || lower.contains("too many requests") ->
                if (isEn) "Provider rate limit reached. Please wait a moment or choose another model." else "Sağlayıcı istek sınırına ulaşıldı. Biraz bekleyip tekrar dene ya da başka bir model seç."
            lower.contains("402") || lower.contains("quota") || lower.contains("bakiye") || lower.contains("insufficient_quota") || lower.contains("billing") ->
                if (isEn) "No quota or balance remaining on provider account." else "Sağlayıcı hesabında kota ya da bakiye kalmamış."
            lower.contains("zaman aşımı") || lower.contains("timed out") || lower.contains("bağlanılamadı") || lower.contains("cannot connect") || lower.contains("ulaşılamıyor") || lower.contains("internet") || lower.contains("offline") ->
                if (isEn) "Could not reach AI. Check your internet (or same Wi-Fi for local models)." else "Yapay zekaya ulaşılamadı. İnternetini (yerel modelde aynı Wi-Fi'yi) kontrol et."
            lower.contains("500") || lower.contains("502") || lower.contains("503") || lower.contains("504") || lower.contains("530") || lower.contains("server error") ->
                if (isEn) "Provider is currently unresponsive. Please try again shortly." else "Sağlayıcı şu an yanıt vermiyor. Biraz sonra tekrar dene."
            else ->
                if (isEn) "Request could not be completed." else "İstek tamamlanamadı."
        }

        var masked = raw
        val savedKey = com.pufy.app.ai.AiClient.apiKey
        if (savedKey.length > 5) {
            masked = masked.replace(savedKey, "••••••••")
        }
        masked = Regex("""sk-[a-zA-Z0-9_\-]{8,}""").replace(masked, "sk-••••••••")
        masked = Regex("""AIza[a-zA-Z0-9_\-]{12,}""").replace(masked, "AIza••••••••")
        friendly to masked
    }

    AnimatedVisibility(
        visible = rawError != null,
        modifier = modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp),
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .pufyGlass(RoundedCornerShape(20.dp), tint = Color(0xFFFF9500).copy(alpha = 0.12f).compositeOver(c.glass))
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Rounded.Warning, null, Modifier.size(18.dp), tint = Color(0xFFFF9500))
                Text(parsed.first, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 3, modifier = Modifier.weight(1f))
                Text(
                    stringResource(R.string.open_settings),
                    style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold),
                    color = c.onPrimary,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(c.primary)
                        .pressable { AppNav.settingsVisible.value = true }
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                )
                Box(Modifier.size(26.dp).pressable { ChatEngine.clearError() }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.close), Modifier.size(14.dp), tint = c.secondaryText)
                }
            }

            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .pressable { showDetails = !showDetails }
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(stringResource(R.string.details), style = PufyType.caption, color = c.secondaryText)
                Icon(
                    if (showDetails) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                    null,
                    modifier = Modifier.size(14.dp),
                    tint = c.secondaryText
                )
            }

            if (showDetails) {
                Text(
                    parsed.second,
                    style = PufyType.caption,
                    color = c.secondaryText,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(c.soft)
                        .padding(8.dp)
                )
            }
        }
    }
}

private fun Color.compositeOver(under: Color): Color {
    val a = alpha
    return Color(red * a + under.red * (1 - a), green * a + under.green * (1 - a), blue * a + under.blue * (1 - a), under.alpha)
}

/** Tam ekran görsel: dokununca kapanır */
@Composable
private fun ImageViewer() {
    val model = ImageViewerState.image.value
    AnimatedVisibility(model != null, enter = fadeIn() + scaleIn(initialScale = 0.96f), exit = fadeOut() + scaleOut(targetScale = 0.96f)) {
        var scale by remember { mutableFloatStateOf(1f) }
        Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures(onTap = { ImageViewerState.image.value = null }, onDoubleTap = { scale = if (scale > 1f) 1f else 2.2f }) },
            contentAlignment = Alignment.Center) {
            val s by animateFloatAsState(scale, Springs.standard(), label = "zoom")
            coil3.compose.AsyncImage(model, null, Modifier.fillMaxWidth().graphicsLayer { scaleX = s; scaleY = s })
        }
    }
}

