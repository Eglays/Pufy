package com.pufy.app.ui.miniapp

import androidx.compose.foundation.layout.statusBarsPadding
import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.util.Base64
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.webkit.MimeTypeMap
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateIntOffsetAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import com.pufy.app.core.Settings
import com.pufy.app.data.MiniApp
import com.pufy.app.data.MiniAppStore
import com.pufy.app.data.Profile
import com.pufy.app.sync.SyncService
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.chat.prepareImage
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileInputStream

// iOS MiniAppView karşılığı: tam ekran uygulama + köşede yüzen cam kontroller (paylaş / düzenle / uygulamalar)

private enum class Spot(val alignment: Alignment, val isLeading: Boolean, val isTop: Boolean) {
    BottomEnd(Alignment.BottomEnd, false, false), BottomStart(Alignment.BottomStart, true, false),
    End(Alignment.CenterEnd, false, false), Start(Alignment.CenterStart, true, false),
    TopEnd(Alignment.TopEnd, false, true), TopStart(Alignment.TopStart, true, true);

    companion object {
        fun nearest(x: Float, y: Float, w: Float, h: Float): Spot {
            val leading = x < w / 2
            return when {
                y < h * 0.3f -> if (leading) TopStart else TopEnd
                y > h * 0.7f -> if (leading) BottomStart else BottomEnd
                else -> if (leading) Start else End
            }
        }
    }
}

@Composable
fun MiniAppScreen(app: MiniApp, onEdit: (MiniApp, String?) -> Unit) {
    val c = Pufy.colors
    val folder = app.folderName
    val hasFiles = remember(app.updatedAt) { MiniAppStore.hasFiles(app) }
    val isLegacy = !app.appSpecJson.isNullOrEmpty() && (folder == null || !hasFiles)
    val hasHtml = app.htmlContent.isNotEmpty()
    val errors = remember(app.id) { mutableStateListOf<String>() }
    var autoSpot by remember { mutableIntStateOf(0) }
    val spotKey = "pufy_control_spot_${folder ?: app.id}"
    var manualSpot by remember { mutableStateOf(if (Settings.has(spotKey)) Settings.int(spotKey) else null) }
    var reload by remember { mutableIntStateOf(0) }
    // Üst/alt sistem çubuklarının arkası sayfanın kendi zemin rengini alır: uygulama tek parça, tam ekran görünür
    var pageBackground by remember(app.id) { mutableStateOf<Color?>(null) }
    val barColor by androidx.compose.animation.animateColorAsState(pageBackground ?: c.background, label = "bars")

    Box(Modifier.fillMaxSize().background(barColor)) {
        when {
            isLegacy -> LegacyNotice()
            folder != null && hasFiles -> androidx.compose.runtime.key(reload, app.updatedAt) {
                AppWebView(app, folder, Modifier.fillMaxSize().safeDrawingPadding(),
                    onError = { if (errors.size < 20 && it !in errors) errors.add(it) },
                    onSpot = { autoSpot = it }, onBackground = { pageBackground = it })
            }
            hasHtml -> androidx.compose.runtime.key(reload, app.updatedAt) {
                AppWebView(app, null, Modifier.fillMaxSize().safeDrawingPadding(),
                    onError = { if (errors.size < 20 && it !in errors) errors.add(it) },
                    onSpot = { autoSpot = it }, onBackground = { pageBackground = it })
            }
            else -> NotDownloaded { reload++ }
        }
        val spot = Spot.entries[(manualSpot ?: autoSpot).coerceIn(0, 5)]
        FloatingControls(app, spot, errors.size,
            onFix = {
                val prefix = if (com.pufy.app.core.AppLocales.isEnglish()) "The following errors occurred in the app, please fix them:\n" else "Uygulamada şu hatalar oluştu, düzelt:\n"
                onEdit(app, prefix + errors.joinToString("\n") { "- $it" })
            },
            onEdit = { onEdit(app, null) },
            onMoved = { s -> manualSpot = s.ordinal; Settings.setInt(spotKey, s.ordinal) })

        var hintExitShown by remember { mutableStateOf(Settings.bool(Settings.HINT_MINI_EXIT_SHOWN)) }
        if (!hintExitShown) {
            com.pufy.app.ui.coach.HintBubble(
                text = androidx.compose.ui.res.stringResource(com.pufy.app.R.string.hint_mini_exit),
                onDismiss = {
                    Settings.setBool(Settings.HINT_MINI_EXIT_SHOWN, true)
                    hintExitShown = true
                },
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 16.dp)
            )
        }
    }
}

/** iOS legacyNotice karşılığı: hazır motorlar kaldırılan eski tip uygulamalar için uyarı */
@Composable
private fun LegacyNotice() {
    val c = Pufy.colors
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
        Icon(Icons.Rounded.Sync, null, Modifier.size(40.dp), tint = c.secondaryText)
        Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.legacy_app_title), style = PufyType.headline, color = c.text)
        Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.legacy_app_desc),
            style = PufyType.subheadline, color = c.secondaryText, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
    }
}

@Composable
private fun NotDownloaded(onRetry: () -> Unit) {
    val c = Pufy.colors
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
        Icon(Icons.Outlined.CloudDownload, null, Modifier.size(40.dp), tint = c.secondaryText)
        Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.not_downloaded_title), style = PufyType.headline, color = c.text)
        Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.not_downloaded_desc), style = PufyType.subheadline, color = c.secondaryText, textAlign = TextAlign.Center)
        Row(Modifier.pufyGlass(CircleShape).pressable { scope.launch { SyncService.fullResync(); onRetry() } }.padding(horizontal = 18.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Rounded.Sync, null, Modifier.size(16.dp), tint = c.text)
            Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.sync_now), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
        }
    }
}

@Composable
private fun FloatingControls(app: MiniApp, spot: Spot, errorCount: Int, onFix: () -> Unit, onEdit: () -> Unit, onMoved: (Spot) -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    val context = LocalContext.current
    var expanded by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    LaunchedEffect(poke) { expanded = true; delay(3500); expanded = false }
    var drag by remember { mutableStateOf(IntOffset.Zero) }
    val shown by animateIntOffsetAsState(drag, Springs.standard(), label = "drag")
    val density = LocalDensity.current

    BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
        val w = with(density) { maxWidth.toPx() }; val h = with(density) { maxHeight.toPx() }
        Column(Modifier.align(spot.alignment).padding(start = if (spot.isLeading) 14.dp else 0.dp, end = if (spot.isLeading) 0.dp else 14.dp,
            top = if (spot.isTop) 8.dp else 0.dp, bottom = if (spot.isTop) 0.dp else 4.dp),
            horizontalAlignment = if (spot.isLeading) Alignment.Start else Alignment.End, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!spot.isTop) ErrorPill(errorCount, onFix)
            AnimatedContent(expanded, label = "controls", transitionSpec = {
                (fadeIn() + scaleIn(initialScale = 0.5f)) togetherWith (fadeOut() + scaleOut(targetScale = 0.5f))
            }) { open ->
                if (open) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GlassIconButton(Icons.Outlined.Edit, androidx.compose.ui.res.stringResource(com.pufy.app.R.string.edit_app), size = 42.dp, iconSize = 17.dp, onClick = onEdit)
                    GlassIconButton(Icons.Outlined.GridView, androidx.compose.ui.res.stringResource(com.pufy.app.R.string.apps), size = 42.dp, iconSize = 17.dp) { AppNav.showSwitcher() }
                } else Box(Modifier.offset { shown }.size(34.dp).pufyGlass(CircleShape)
                    .pointerInput(spot) {
                        detectDragGestures(onDragEnd = {
                            // Bırakılan noktaya en yakın köşe
                            val base = basePosition(spot, w, h, with(density) { 48.dp.toPx() })
                            onMoved(Spot.nearest(base.x + drag.x, base.y + drag.y, w, h)); Haptics.medium(view)
                            drag = IntOffset.Zero
                        }, onDragCancel = { drag = IntOffset.Zero }) { change, amount ->
                            change.consume(); drag = IntOffset(drag.x + amount.x.toInt(), drag.y + amount.y.toInt())
                        }
                    }
                    .pressable { Haptics.light(view); poke++ }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.MoreHoriz, androidx.compose.ui.res.stringResource(com.pufy.app.R.string.app_options), Modifier.size(18.dp), tint = c.text.copy(alpha = 0.7f))
                }
            }
            if (spot.isTop) ErrorPill(errorCount, onFix)
        }
    }
}

private fun basePosition(spot: Spot, w: Float, h: Float, margin: Float) = androidx.compose.ui.geometry.Offset(
    if (spot.isLeading) margin else w - margin, when { spot.isTop -> margin; spot == Spot.Start || spot == Spot.End -> h / 2; else -> h - margin })

@Composable
private fun ErrorPill(count: Int, onFix: () -> Unit) {
    val c = Pufy.colors
    AnimatedVisibility(count > 0, enter = fadeIn() + slideInVertically { it }, exit = fadeOut() + slideOutVertically { it }) {
        Row(Modifier.pufyGlass(CircleShape).pressable(onClick = onFix).padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.Warning, null, Modifier.size(15.dp), tint = Color(0xFFFF9500))
            Text(if (count == 1) androidx.compose.ui.res.stringResource(com.pufy.app.R.string.one_error_occurred) else androidx.compose.ui.res.stringResource(com.pufy.app.R.string.errors_occurred_count, count), style = PufyType.footnote, color = c.text)
            Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.fix), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.onPrimary,
                modifier = Modifier.background(c.primary, CircleShape).padding(horizontal = 10.dp, vertical = 4.dp))
        }
    }
}


@SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
@Composable
private fun AppWebView(app: MiniApp, folder: String?, modifier: Modifier, onError: (String) -> Unit, onSpot: (Int) -> Unit, onBackground: (Color) -> Unit) {
    val context = LocalContext.current
    val c = Pufy.colors
    val scope = rememberCoroutineScope()
    var photoReply by remember { mutableStateOf<((String?) -> Unit)?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val reply = photoReply; photoReply = null
        if (uri == null) reply?.invoke(null) else scope.launch { reply?.invoke(prepareImage(context, uri)?.let { "data:image/jpeg;base64," + Base64.encodeToString(it, Base64.NO_WRAP) }) }
    }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val reply = photoReply; photoReply = null; val u = cameraUri
        if (!ok || u == null) reply?.invoke(null) else scope.launch { reply?.invoke(prepareImage(context, u)?.let { "data:image/jpeg;base64," + Base64.encodeToString(it, Base64.NO_WRAP) }) }
    }

    if (folder != null) {
        remember(folder) { com.pufy.app.apps.MiniAppFiles.folder(folder).takeIf { java.io.File(it, "pufy-ui.css").exists() }?.let { com.pufy.app.apps.MiniAppFiles.ensureKit(folder) } }
    }
    val host = folder?.let { com.pufy.app.apps.LocalServer.host(it) } ?: "localhost"
    val bridgeFolder = folder ?: app.id
    val bridge = remember(app.id) {
        PufyBridge(context, app, bridgeFolder, onError, onSpot) { useCamera, reply ->
            photoReply = reply
            if (useCamera) {
                val f = File(context.cacheDir, "app-kamera-${System.currentTimeMillis()}.jpg")
                val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
                cameraUri = uri; camera.launch(uri)
            } else pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }
    }
    DisposableEffect(bridge) { onDispose { bridge.webView?.destroy(); bridge.dispose() } }
    // Gece/gündüz değişince sayfanın yeni zemin rengi çubuklara da geçsin
    LaunchedEffect(c.isDark) { bridge.webView?.let { w -> kotlinx.coroutines.delay(350); readBackground(w, onBackground) } }

    AndroidView(modifier = modifier, factory = { ctx ->
        WebView(ctx).apply {
            // ÖNEMLİ: içeriğe göre yükseklikte (WRAP_CONTENT) WebView'da CSS 100vh = 0 oluyordu → uygulamalar ekranın dışına kayıyordu
            layoutParams = android.view.ViewGroup.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(c.background.toArgb())
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.cacheMode = WebSettings.LOAD_NO_CACHE
            settings.setSupportZoom(false)
            overScrollMode = WebView.OVER_SCROLL_NEVER
            addJavascriptInterface(bridge, "PufyNative")
            bridge.webView = this
            val name = Profile.name
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                    if (folder != null) com.pufy.app.apps.LocalServer.serve(request.url, folder, app.entryPoint) else null

                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    if (folder == null || Uri.parse(url ?: "").host == host) view.evaluateJavascript(PufyBridge.script(name), null)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    if (folder != null && Uri.parse(url ?: "").host != host) return
                    view.evaluateJavascript(PufyBridge.script(name), null)
                    view.evaluateJavascript(PufyBridge.VIEWPORT, null)
                    view.evaluateJavascript(ControlSpotScript.SOURCE, null)
                    readBackground(view, onBackground)
                    view.postDelayed({ readBackground(view, onBackground) }, 1500)
                }

                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (folder != null && request.url.host == host) return false
                    if (folder == null && (request.url.scheme == "about" || request.url.scheme == "data")) return false
                    // Dış bağlantılar tarayıcıda açılır (köprü yalnızca uygulamanın kendi sayfalarında çalışır)
                    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, request.url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) {
                    if (folder == null || request.origin.host == host) request.grant(request.resources) else request.deny()
                }
            }
            // Sıkıştırınca uygulama değiştirici (iOS ile aynı)
            var fired = false
            val pinch = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                var total = 1f
                override fun onScaleBegin(detector: ScaleGestureDetector): Boolean { total = 1f; return true }
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    total *= detector.scaleFactor
                    if (total < 0.78f && !fired) { fired = true; Haptics.medium(this@apply); AppNav.showSwitcher(cards = true) }
                    return true
                }
            })
            setOnTouchListener { _, e ->
                pinch.onTouchEvent(e)
                if (e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL) fired = false
                false
            }
            // Ölçülmeden yüklenen sayfada 100vh sıfır kalıyordu (içerik ekranın dışına kayıyordu): boyut gelince yükle (iOS PufyWebView ile aynı)
            fun performLoad() {
                if (folder != null) {
                    loadUrl(com.pufy.app.apps.LocalServer.url(folder, app.entryPoint))
                } else {
                    loadDataWithBaseURL(null, app.htmlContent, "text/html", "utf-8", null)
                }
            }
            if (width > 1 && height > 1) performLoad() else addOnLayoutChangeListener(object : android.view.View.OnLayoutChangeListener {
                override fun onLayoutChange(v: android.view.View, l: Int, t: Int, r: Int, b: Int, ol: Int, ot: Int, or: Int, ob: Int) {
                    if (r - l > 1 && b - t > 1) { v.removeOnLayoutChangeListener(this); v.post { performLoad() } }
                }
            })
        }
    })
}


private const val BG_SCRIPT = "(function(){function ok(c){return c && c!=='transparent' && c!=='rgba(0, 0, 0, 0)';}" +
    "var b=document.body?getComputedStyle(document.body).backgroundColor:'';if(!ok(b))b=getComputedStyle(document.documentElement).backgroundColor;return ok(b)?b:'';})()"

/** Sayfanın zemin rengini okur ("rgb(r, g, b)") */
private fun readBackground(view: WebView, onBackground: (Color) -> Unit) {
    view.evaluateJavascript(BG_SCRIPT) { raw ->
        val nums = Regex("[\\d.]+").findAll(raw ?: "").map { it.value.toFloat() }.toList()
        if (nums.size >= 3 && (nums.getOrNull(3) ?: 1f) > 0.5f) onBackground(Color(nums[0] / 255f, nums[1] / 255f, nums[2] / 255f))
    }
}
