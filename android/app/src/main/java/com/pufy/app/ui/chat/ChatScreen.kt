package com.pufy.app.ui.chat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.border
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.FormatAlignLeft
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.rounded.Add
import androidx.compose.ui.res.stringResource
import com.pufy.app.R
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.outlined.ListAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil3.compose.AsyncImage
import com.pufy.app.ai.ChatEngine
import com.pufy.app.data.ChatStore
import com.pufy.app.data.Profile
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.LocalHaze
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Calendar

// iOS ChatView karşılığı: üst cam bar, karşılama, mesaj listesi, cam yazma çubuğu

/** iOS ChatView.greeting: sadece sabah / akşam / gece selamı (öğlen boş) */
fun greeting(name: String, hour: Int = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)): String? {
    val isEn = com.pufy.app.core.AppLocales.isEnglish()
    val base = when (hour) {
        in 5..10 -> if (isEn) "Good morning" else "Günaydın"
        in 18..21 -> if (isEn) "Good evening" else "İyi akşamlar"
        in 22..23, in 0..4 -> if (isEn) "Good night" else "İyi geceler"
        else -> return null
    }
    val first = name.trim().split(" ").firstOrNull().orEmpty()
    return if (first.isEmpty()) base else "$base, $first"
}

@Composable
fun ChatScreen(onOpenMenu: () -> Unit, onOpenApps: () -> Unit, preview: Boolean = false) {
    val c = Pufy.colors
    val sessions by ChatStore.sessions.collectAsState()
    val currentID by ChatEngine.currentSessionID.collectAsState()
    val generatingID by ChatEngine.generatingMessageID.collectAsState()
    val session = sessions.firstOrNull { it.id == currentID }
    val messages = session?.messages.orEmpty()
    val haze = remember { HazeState() }
    val density = LocalDensity.current
    var headerHeight by remember { mutableStateOf(0.dp) }
    var composerHeight by remember { mutableStateOf(0.dp) }
    val composer = remember { ComposerState() }
    val focus = LocalFocusManager.current

    Box(Modifier.fillMaxSize().background(c.background)) {
        // Küçük önizlemede (uygulama kartı) bulanıklık kapalı: ölçeklenen katmanda cam efekti ışık şeritleri bırakıyordu
        CompositionLocalProvider(LocalHaze provides if (preview) null else haze) {
            Box(Modifier.fillMaxSize().let { if (preview) it else it.hazeSource(haze) }) {
                if (session?.isSpaceChat == true) {
                    TaskSessionScreen(
                        session = session,
                        headerHeight = headerHeight,
                        onOpenMenu = { focus.clearFocus(); onOpenMenu() }
                    )
                } else if (messages.isEmpty()) {
                    Welcome(headerHeight, composerHeight, composer.focused) { q -> composer.text = q; composer.send() }
                } else {
                    MessageList(session!!.id, messages, generatingID, headerHeight, composerHeight,
                        onTapEmpty = { focus.clearFocus(); composer.attachOpen = false },
                        onAction = { t -> if (generatingID == null) { composer.text = t; composer.send() } })
                }
            }
            // iOS "soft scroll edge": kayan içerik üst ve alt çubuğun arkasında yumuşakça solar
            if (messages.isNotEmpty() && session?.isSpaceChat != true) {
                Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(headerHeight + 18.dp)
                    .background(androidx.compose.ui.graphics.Brush.verticalGradient(0f to c.background, 0.55f to c.background.copy(alpha = 0.9f), 1f to c.background.copy(alpha = 0f))))
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(composerHeight + 14.dp)
                    .background(androidx.compose.ui.graphics.Brush.verticalGradient(0f to c.background.copy(alpha = 0f), 0.35f to c.background.copy(alpha = 0.92f), 0.5f to c.background, 1f to c.background)))
            }
            Header(Modifier.align(Alignment.TopCenter).onSizeChanged { headerHeight = with(density) { it.height.toDp() } },
                onOpenMenu = { focus.clearFocus(); onOpenMenu() }, onOpenApps = { focus.clearFocus(); onOpenApps() })
            if (session?.isSpaceChat != true && !preview) {
                Composer(composer, messages, generatingID != null, onOpenApps,
                    Modifier.align(Alignment.BottomCenter).onSizeChanged { composerHeight = with(density) { it.height.toDp() } })
            }
        }
    }
}

@Composable
private fun Header(modifier: Modifier, onOpenMenu: () -> Unit, onOpenApps: () -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    Row(modifier.fillMaxWidth().statusBarsPadding().padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        GlassIconButton(Icons.AutoMirrored.Rounded.FormatAlignLeft, stringResource(R.string.menu_action), iconSize = 19.dp, onClick = onOpenMenu)
        Spacer(Modifier.weight(1f))
        Row(Modifier.pufyGlass(CircleShape)) {
            Box(Modifier.size(46.dp, 44.dp).pressable { Haptics.light(view); onOpenApps() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.GridView, stringResource(R.string.apps), Modifier.size(19.dp), tint = c.text)
            }
            Box(Modifier.size(46.dp, 44.dp).pressable { Haptics.light(view); ChatEngine.newSession() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.EditNote, stringResource(R.string.new_chat), Modifier.size(22.dp), tint = c.text)
            }
        }
    }
}

@Composable
private fun Welcome(top: androidx.compose.ui.unit.Dp, bottom: androidx.compose.ui.unit.Dp, focused: Boolean, onPick: (String) -> Unit) {
    val c = Pufy.colors
    val name by Profile.nameFlow.collectAsState()
    val sessions by ChatStore.sessions.collectAsState()
    val followUps = remember(sessions) { ChatEngine.recentFollowUps() }
    val alpha by animateFloatAsState(if (focused) 0.45f else 1f, Springs.gentle(), label = "a")
    val scale by animateFloatAsState(if (focused) 0.94f else 1f, Springs.gentle(), label = "s")
    val focus = LocalFocusManager.current
    Column(Modifier.fillMaxSize().padding(top = top, bottom = bottom + 8.dp).padding(horizontal = 20.dp)
        .graphicsLayer { this.alpha = alpha; scaleX = scale; scaleY = scale }
        .pointerInput(Unit) { detectTapGestures { focus.clearFocus() } },
        horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        greeting(name)?.let { Text(it, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = c.text, textAlign = TextAlign.Center, letterSpacing = (-0.4).sp) }
        Spacer(Modifier.weight(1f))
        AnimatedVisibility(followUps.isNotEmpty() && !focused, enter = fadeIn() + slideInVertically { it / 3 }, exit = fadeOut() + slideOutVertically { it / 3 }) {
            FollowUpSuggestions(followUps, onPick)
        }
    }
}

@Composable
private fun MessageList(
    sessionID: String, messages: List<com.pufy.app.data.Message>, generatingID: String?,
    top: androidx.compose.ui.unit.Dp, bottom: androidx.compose.ui.unit.Dp, onTapEmpty: () -> Unit, onAction: (String) -> Unit,
) {
    val state = remember(sessionID) { androidx.compose.foundation.lazy.LazyListState() }
    val scope = rememberCoroutineScope()
    val lastModelID = messages.lastOrNull { !it.isUser }?.id
    val nearBottom by remember(state) {
        derivedStateOf {
            val info = state.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull() ?: return@derivedStateOf true
            last.index >= info.totalItemsCount - 1 && last.offset + last.size <= info.viewportEndOffset + 160
        }
    }
    // Açılışta en alta; yeni mesajda yumuşakça; yazılırken sadece kullanıcı alttaysa takip
    LaunchedEffect(sessionID) { if (messages.isNotEmpty()) state.scrollToItem(messages.size) }
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) state.animateScrollToItem(messages.size) }
    val streamKey = messages.lastOrNull()?.content?.length ?: 0
    LaunchedEffect(streamKey) { if (generatingID != null && nearBottom && messages.isNotEmpty()) state.scrollToItem(messages.size) }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(state = state, modifier = Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { onTapEmpty() } },
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = top + 8.dp, bottom = bottom + 16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)) {
            items(messages, key = { it.id }) { m ->
                Box(Modifier.animateItem(fadeInSpec = androidx.compose.animation.core.spring(stiffness = 400f), placementSpec = Springs.standard())) {
                    MessageRow(m, isLastResponse = m.id == lastModelID, isGenerating = m.id == generatingID,
                        onImageTap = { ImageViewerState.show(it) }, onRegenerate = { ChatEngine.regenerate() }, onAction = onAction)
                }
            }
            item(key = "bottom") { Spacer(Modifier.height(1.dp)) }
        }
        AnimatedVisibility(!nearBottom, Modifier.align(Alignment.BottomCenter).padding(bottom = bottom + 10.dp),
            enter = fadeIn() + scaleIn(initialScale = 0.6f), exit = fadeOut() + scaleOut(targetScale = 0.6f)) {
            GlassIconButton(Icons.Rounded.ArrowDownward, "En alta git", size = 38.dp, iconSize = 16.dp) {
                scope.launch { state.animateScrollToItem(messages.size) }
            }
        }
    }
}

/** Tam ekran görsel (basit) */
object ImageViewerState { val image = mutableStateOf<Any?>(null); fun show(model: Any) { image.value = model } }

// MARK: Yazma çubuğu

class ComposerState {
    var text by mutableStateOf("")
    val images = mutableStateListOf<ByteArray>()
    val files = mutableStateListOf<com.pufy.app.data.FileAttachment>()
    var isExtractingFiles by mutableStateOf(false)
    var attachOpen by mutableStateOf(false)
    var searchMode by mutableStateOf(false)
    var reminderMode by mutableStateOf(false)
    var deepMode by mutableStateOf(false)
    var focused by mutableStateOf(false)
    val dismissedChoices = mutableStateListOf<String>()
    val collapsedChoices = mutableStateListOf<String>()
    var onSent: (() -> Unit)? = null

    val canSend get() = com.pufy.app.ai.AiClient.isConfigured && !ChatEngine.isGenerating && (text.isNotBlank() || images.isNotEmpty() || files.isNotEmpty())

    fun send() {
        if (!com.pufy.app.ai.AiClient.isConfigured) {
            com.pufy.app.ui.AppNav.openAIConnect()
            return
        }
        if (!canSend) return
        ChatEngine.send(text, images.toList(), files = files.toList(), forceSearch = searchMode, reminderMode = reminderMode, forceDeep = deepMode)
        text = ""; images.clear(); files.clear(); attachOpen = false; searchMode = false; reminderMode = false; deepMode = false
        onSent?.invoke()
    }
}

@Composable
private fun Composer(state: ComposerState, messages: List<com.pufy.app.data.Message>, loading: Boolean, onOpenApps: () -> Unit, modifier: Modifier) {
    val c = Pufy.colors
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val dictation = remember { Dictation(context) }
    val dictPhase by dictation.phase.collectAsState()
    val dictError by dictation.error.collectAsState()
    LaunchedEffect(dictError) { dictError?.let { ChatEngine.reportError(it); dictation.error.value = null } }

    val last = messages.lastOrNull()
    val pendingQuestions = if (!loading && !state.attachOpen && last != null && !last.isUser && last.id !in state.dismissedChoices)
        last.choiceQuestions.takeIf { it.isNotEmpty() } else null

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(6)) { uris ->
        scope.launch { uris.forEach { u -> prepareImage(context, u)?.let { if (state.images.none { x -> x.contentEquals(it) }) state.images.add(it) } } }
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            state.isExtractingFiles = true
            try {
                for (uri in uris) {
                    if (state.files.size >= 3) {
                        ChatEngine.reportError(if (com.pufy.app.core.AppLocales.isEnglish()) "You can attach at most 3 files." else "Bir mesajda en fazla 3 dosya ekleyebilirsiniz.")
                        break
                    }
                    val attachment = withContext(Dispatchers.IO) {
                        com.pufy.app.core.FileTextExtractor.extract(context, uri).getOrThrow()
                    }
                    if (state.files.none { it.name == attachment.name && it.size == attachment.size }) {
                        state.files.add(attachment)
                    }
                }
            } catch (e: Exception) {
                ChatEngine.reportError(e.message ?: context.getString(R.string.file_read_failed))
            } finally {
                state.isExtractingFiles = false
            }
        }
    }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val u = cameraUri
        if (ok && u != null) scope.launch { prepareImage(context, u)?.let { state.images.add(it) } }
    }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) dictation.start() else ChatEngine.reportError(context.getString(R.string.mic_permission_needed))
    }
    fun startDictation() {
        keyboard?.hide(); state.attachOpen = false
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) dictation.start()
        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    Column(modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 8.dp)
        .animateContentSize(Springs.standard()), verticalArrangement = Arrangement.spacedBy(10.dp)) {

        AnimatedVisibility(state.attachOpen, enter = fadeIn() + scaleIn(initialScale = 0.9f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 1f)),
            exit = fadeOut() + scaleOut(targetScale = 0.9f, transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 1f))) {
            Column(Modifier.fillMaxWidth().pufyGlass(RoundedCornerShape(28.dp)).padding(bottom = 8.dp)) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AttachTile(Icons.Outlined.CameraAlt, stringResource(R.string.camera_action)) {
                        val file = File(context.cacheDir, "kamera-${System.currentTimeMillis()}.jpg")
                        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
                        cameraUri = uri; state.attachOpen = false; camera.launch(uri)
                    }
                    AttachTile(Icons.Outlined.PhotoLibrary, stringResource(R.string.gallery_action)) {
                        state.attachOpen = false
                        pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                    state.images.forEachIndexed { i, data -> Thumb(data, 76.dp) { state.images.removeAt(i) } }
                }
                AttachRow(Icons.Outlined.Collections, if (com.pufy.app.core.AppLocales.isEnglish()) "Photos" else "Fotoğraflar") {
                    state.attachOpen = false; pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                AttachRow(Icons.Outlined.Description, if (com.pufy.app.core.AppLocales.isEnglish()) "File" else "Dosya") {
                    state.attachOpen = false
                    filePicker.launch(arrayOf(
                        "application/pdf",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "text/*",
                        "application/json",
                        "application/xml",
                        "*/*"
                    ))
                }
                AttachRow(Icons.Outlined.Language, stringResource(R.string.search_web_action), isOn = state.searchMode) {
                    state.searchMode = !state.searchMode
                    if (state.searchMode) { state.reminderMode = false; state.deepMode = false }
                    state.attachOpen = false; focusRequester.requestFocus()
                }
                AttachRow(Icons.Outlined.Notifications, stringResource(R.string.set_reminder_action), isOn = state.reminderMode) {
                    state.reminderMode = !state.reminderMode
                    if (state.reminderMode) { state.searchMode = false; state.deepMode = false }
                    state.attachOpen = false; focusRequester.requestFocus()
                }
                AttachRow(Icons.Outlined.Psychology, stringResource(R.string.deep_think_action), isOn = state.deepMode) {
                    state.deepMode = !state.deepMode
                    if (state.deepMode) { state.searchMode = false; state.reminderMode = false }
                    state.attachOpen = false; focusRequester.requestFocus()
                }
            }
        }

        if (pendingQuestions != null && last != null) {
            AnimatedContent(last.id in state.collapsedChoices, label = "choices",
                transitionSpec = { fadeIn() togetherWith fadeOut() }) { collapsed ->
                if (collapsed) {
                    Row(Modifier.fillMaxWidth().pufyGlass(CircleShape).pressable { state.collapsedChoices.remove(last.id) }
                        .padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.ListAlt, null, Modifier.size(16.dp), tint = c.text)
                        Text(pendingQuestions.first().q, style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text,
                            maxLines = 1, modifier = Modifier.weight(1f))
                        if (pendingQuestions.size > 1) Text("+${pendingQuestions.size - 1}", style = PufyType.caption.copy(fontWeight = FontWeight.Bold), color = c.secondaryText)
                        Icon(Icons.Rounded.KeyboardArrowUp, null, Modifier.size(16.dp), tint = c.secondaryText)
                    }
                } else {
                    Box(Modifier.fillMaxWidth().pufyGlass(RoundedCornerShape(26.dp))) {
                        ChoicePanel(pendingQuestions,
                            onSubmit = { answer -> state.dismissedChoices.add(last.id); state.text = answer; state.send() },
                            onDismiss = { state.dismissedChoices.add(last.id) },
                            onCollapse = { state.collapsedChoices.add(last.id) })
                    }
                }
            }
        }

        val aiConfigured = com.pufy.app.ai.AiClient.configState.collectAsState().value.first
        if (!aiConfigured) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(if (c.isDark) c.secondaryBackground else Color.White)
                    .border(1.dp, c.separator.copy(alpha = 0.5f), RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Outlined.Shield, null, Modifier.size(20.dp), tint = c.primary)
                Text(
                    text = stringResource(R.string.connect_ai_to_start),
                    style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium),
                    color = c.text,
                    modifier = Modifier.weight(1f)
                )
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(c.primary)
                        .pressable {
                            Haptics.light(view)
                            com.pufy.app.ui.AppNav.openAIConnect()
                        }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.connect),
                        style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold),
                        color = c.onPrimary
                    )
                }
            }
        }

        // Giriş alanı
        Column(Modifier.fillMaxWidth().heightIn(min = 46.dp).pufyGlass(RoundedCornerShape(23.dp))) {
            if (state.searchMode || state.reminderMode || state.deepMode) {
                Row(Modifier.padding(start = 10.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (state.searchMode) ModeChip(Icons.Outlined.Language, stringResource(R.string.search_web_action)) { state.searchMode = false }
                    if (state.reminderMode) ModeChip(Icons.Outlined.Notifications, stringResource(R.string.reminder)) { state.reminderMode = false }
                    if (state.deepMode) ModeChip(Icons.Outlined.Psychology, stringResource(R.string.deep_think_action)) { state.deepMode = false }
                }
            }
            if (!state.attachOpen && (state.images.isNotEmpty() || state.files.isNotEmpty() || state.isExtractingFiles) && dictPhase == Dictation.Phase.IDLE) {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()).padding(start = 10.dp, end = 10.dp, top = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    state.images.forEachIndexed { i, data -> Thumb(data, 76.dp) { state.images.removeAt(i) } }
                    state.files.forEachIndexed { i, file ->
                        FileChip(file = file, onRemove = { state.files.removeAt(i) })
                    }
                    if (state.isExtractingFiles) {
                        androidx.compose.material3.CircularProgressIndicator(
                            modifier = Modifier.size(20.dp).padding(2.dp),
                            strokeWidth = 2.dp,
                            color = c.primary
                        )
                    }
                }
            }
            if (dictPhase != Dictation.Phase.IDLE) {
                DictationBar(dictation, dictPhase) { t ->
                    state.text = if (state.text.isBlank()) t else state.text.trim() + " " + t
                    focusRequester.requestFocus()
                }
            } else Row(verticalAlignment = Alignment.Bottom) {
                val rotation by animateFloatAsState(if (state.attachOpen) 45f else 0f, Springs.standard(), label = "plus")
                Box(Modifier.padding(start = 4.dp).size(40.dp, 46.dp).pressable {
                    Haptics.light(view)
                    if (!state.attachOpen) keyboard?.hide()
                    state.attachOpen = !state.attachOpen
                }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Add, if (state.attachOpen) stringResource(R.string.close_menu) else stringResource(R.string.add_action), Modifier.size(24.dp).graphicsLayer { rotationZ = rotation },
                        tint = c.text)
                }
                Box(Modifier.weight(1f).heightIn(min = 46.dp).padding(start = 2.dp, top = 12.dp, bottom = 12.dp), contentAlignment = Alignment.CenterStart) {
                    if (state.text.isEmpty()) Text(when {
                        state.deepMode -> androidx.compose.ui.res.stringResource(com.pufy.app.R.string.deep_thought)
                        state.reminderMode -> androidx.compose.ui.res.stringResource(com.pufy.app.R.string.reminder_title)
                        state.searchMode -> androidx.compose.ui.res.stringResource(com.pufy.app.R.string.searching_web)
                        else -> androidx.compose.ui.res.stringResource(com.pufy.app.R.string.ask_pufy)
                    }, style = PufyType.body, color = c.secondaryText.copy(alpha = 0.75f))
                    BasicTextField(state.text, { state.text = it }, Modifier.fillMaxWidth().focusRequester(focusRequester)
                        .onFocusChanged { state.focused = it.isFocused; if (it.isFocused) state.attachOpen = false },
                        textStyle = PufyType.body.copy(color = c.text), cursorBrush = SolidColor(c.text), maxLines = 6,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
                }
                val showsMic = !loading && state.text.isBlank() && state.images.isEmpty() && state.files.isEmpty()
                Box(Modifier.padding(end = 6.dp, bottom = 6.dp)) {
                    AnimatedContent(if (showsMic) 0 else if (loading) 1 else 2, label = "send",
                        transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.6f)) togetherWith (fadeOut() + scaleOut(targetScale = 0.6f)) }) { kind ->
                        when (kind) {
                            0 -> Box(Modifier.size(34.dp).pressable { startDictation() }, contentAlignment = Alignment.Center) {
                                Icon(Icons.Outlined.Mic, stringResource(R.string.speak_to_type), Modifier.size(21.dp), tint = c.text)
                            }
                            1 -> Box(Modifier.size(34.dp).clip(CircleShape).background(c.primary).pressable { Haptics.light(view); ChatEngine.stop() },
                                contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Stop, stringResource(R.string.stop_action), Modifier.size(16.dp), tint = c.onPrimary) }
                            else -> {
                                val can = state.canSend
                                Box(Modifier.size(34.dp).clip(CircleShape).background(if (can) c.primary else c.disabled)
                                    .pressable(enabled = can) { Haptics.medium(view); state.send() }, contentAlignment = Alignment.Center) {
                                    Icon(Icons.Rounded.ArrowUpward, stringResource(R.string.send_action), Modifier.size(19.dp), tint = if (can) c.onPrimary else Color.White)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


@Composable
private fun DictationBar(dictation: Dictation, phase: Dictation.Phase, onText: (String) -> Unit) {
    val c = Pufy.colors
    val level by dictation.level.collectAsState()
    Row(Modifier.fillMaxWidth().height(46.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(34.dp).pressable { dictation.cancel() }, contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Close, stringResource(R.string.cancel), Modifier.size(18.dp), tint = c.secondaryText)
        }
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            if (phase == Dictation.Phase.TRANSCRIBING) com.pufy.app.ui.components.ShimmerText(stringResource(R.string.dictation_transcribing), PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            else Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                repeat(18) { i ->
                    val wave = (kotlin.math.sin(i * 0.9 + System.nanoTime() / 1e8) + 1) / 2
                    val h by animateFloatAsState((4 + 22 * level * (0.4 + 0.6 * wave)).toFloat(), Springs.quick(), label = "bar$i")
                    Box(Modifier.width(3.dp).height(h.dp).clip(CircleShape).background(c.text.copy(alpha = 0.8f)))
                }
            }
        }
        Box(Modifier.size(34.dp).clip(CircleShape).background(if (phase == Dictation.Phase.RECORDING) c.primary else c.disabled)
            .pressable(enabled = phase == Dictation.Phase.RECORDING) { dictation.finish(onText) }, contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Check, stringResource(R.string.done_action), Modifier.size(18.dp), tint = c.onPrimary)
        }
    }
}

@Composable
private fun ModeChip(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onRemove: () -> Unit) {
    val c = Pufy.colors
    Row(Modifier.clip(CircleShape).background(c.soft).pressable(onClick = onRemove).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Icon(icon, null, Modifier.size(14.dp), tint = c.onSoft)
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = c.onSoft)
        Icon(Icons.Rounded.Close, stringResource(R.string.close_mode_chip, title), Modifier.size(11.dp), tint = c.onSoft.copy(alpha = 0.7f))
    }
}

@Composable
private fun AttachTile(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    val c = Pufy.colors
    Column(Modifier.size(76.dp).clip(RoundedCornerShape(16.dp)).background(c.soft).pressable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(icon, null, Modifier.size(24.dp), tint = c.primary)
        Spacer(Modifier.height(6.dp))
        Text(title, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.primary)
    }
}

@Composable
private fun AttachRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String? = null, isOn: Boolean = false, onClick: () -> Unit) {
    val c = Pufy.colors
    Row(Modifier.fillMaxWidth().pressable(scale = 0.98f, onClick = onClick).padding(horizontal = 14.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(if (isOn) c.primary else c.soft), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(18.dp), tint = if (isOn) c.onPrimary else c.primary)
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = PufyType.body.copy(fontWeight = FontWeight.Medium), color = c.text)
            subtitle?.let { Text(it, style = PufyType.caption, color = c.secondaryText) }
        }
        if (isOn) Icon(Icons.Rounded.Check, null, Modifier.size(16.dp), tint = c.primary)
    }
}

@Composable
private fun Thumb(data: ByteArray, size: androidx.compose.ui.unit.Dp, onRemove: () -> Unit) {
    Box(Modifier.size(size).clip(RoundedCornerShape(16.dp))) {
        AsyncImage(data, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(Modifier.align(Alignment.TopEnd).padding(4.dp).size(22.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f))
            .clickable(remember { MutableInteractionSource() }, null, onClick = onRemove), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Close, stringResource(R.string.remove_image), Modifier.size(12.dp), tint = Color.White)
        }
    }
}

/** iOS ImageUtils.preparedJPEG: en uzun kenar 1600, JPEG %80 */
suspend fun prepareImage(context: Context, uri: Uri): ByteArray? = withContext(Dispatchers.IO) {
    runCatching {
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            // ImageDecoder kamera fotoğrafının yönünü (EXIF) kendisi düzeltir
            val src = android.graphics.ImageDecoder.createSource(context.contentResolver, uri)
            val bitmap = android.graphics.ImageDecoder.decodeBitmap(src) { d, info, _ ->
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > 1600) { val f = 1600f / longest; d.setTargetSize((info.size.width * f).toInt(), (info.size.height * f).toInt()) }
                d.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
            }
            ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        } else {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@runCatching null
            prepareImage(bytes)
        }
    }.getOrNull()
}

fun prepareImage(bytes: ByteArray, maxDimension: Int = 1600): ByteArray? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    val scale = minOf(1f, maxDimension.toFloat() / maxOf(bitmap.width, bitmap.height))
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
    return ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
}

