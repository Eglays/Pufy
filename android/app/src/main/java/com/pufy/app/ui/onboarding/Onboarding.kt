package com.pufy.app.ui.onboarding

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Send
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.ApiFormat
import com.pufy.app.core.AppLocales
import com.pufy.app.core.LegalLinks
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.settings.PROVIDERS
import com.pufy.app.ui.settings.ProviderInfo
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.launch

// iOS OnboardingView karşılığı: tanıtım + verilerin sende + yapay zekayı bağla

private data class Page(val icon: ImageVector, val title: String, val text: String)

enum class OnboardingStep { INTRO, PRIVACY, CONNECT_AI }

@Composable
fun OnboardingScreen(
    needsSetup: Boolean,
    initialStep: OnboardingStep = OnboardingStep.INTRO,
    onFinish: () -> Unit,
    onOpenSettings: () -> Unit
) {
    var step by remember { mutableStateOf(initialStep) }

    when (step) {
        OnboardingStep.INTRO -> {
            IntroPager(
                onFinish = onFinish,
                onNext = { step = OnboardingStep.PRIVACY }
            )
        }
        OnboardingStep.PRIVACY -> {
            PrivacyStepScreen(
                onContinue = { step = OnboardingStep.CONNECT_AI }
            )
        }
        OnboardingStep.CONNECT_AI -> {
            ConnectAIScreen(
                onContinue = onFinish,
                onSkip = onFinish
            )
        }
    }
}

// MARK: - 1. Tanıtım Pager

@Composable
private fun IntroPager(onFinish: () -> Unit, onNext: () -> Unit) {
    val c = Pufy.colors
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val isEn = com.pufy.app.core.AppLocales.isEnglish()
    val pages = remember(isEn) {
        if (isEn) listOf(
            Page(Icons.Outlined.Forum, "Welcome to Pufy", "Your personal AI assistant that answers questions, searches the web, and sets reminders. You can connect any AI model you want."),
            Page(Icons.Outlined.Hub, "Knows you", "As you talk, it learns important things about you and keeps them in your personal network. It remembers when needed, and you can delete anything you want."),
            Page(Icons.Outlined.GridView, "Mini Apps", "Pinch with two fingers or tap the apps icon. Tell Pufy what you want, and it will build an app or game for you."),
            Page(Icons.Outlined.Mic, "Type by voice", "Tap the microphone in the message box, speak in English or Turkish; Pufy will transcribe your voice into text.")
        ) else listOf(
            Page(Icons.Outlined.Forum, "Pufy'ye hoş geldin", "Sorularını cevaplayan, web'de araştıran, hatırlatıcı kuran kişisel yapay zeka asistanın. İstediğin yapay zeka modelini bağlayabilirsin."),
            Page(Icons.Outlined.Hub, "Seni tanır", "Konuştukça seninle ilgili önemli şeyleri öğrenir ve kişisel ağında saklar. Gerektiğinde hatırlar, istemediğini silersin."),
            Page(Icons.Outlined.GridView, "Uygulamalar", "İki parmakla kıstır veya uygulamalar ikonuna dokun. Ne istediğini anlat, Pufy senin için bir uygulama ya da oyun yazsın."),
            Page(Icons.Outlined.Mic, "Konuşarak yaz", "Mesaj kutusundaki mikrofona dokun, Türkçe ya da İngilizce karışık konuş; Pufy sesini yazıya döker.")
        )
    }
    val pager = rememberPagerState { pages.size }
    val last = pager.currentPage == pages.size - 1

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding()) {
        HorizontalPager(pager, Modifier.weight(1f)) { index ->
            val p = pages[index]
            Column(Modifier.fillMaxSize().padding(horizontal = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.weight(1f))
                Box(Modifier.size(128.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(128.dp).clip(CircleShape).background(c.soft))
                    Icon(p.icon, null, Modifier.size(54.dp), tint = c.primary)
                    if (index == 2) SwipeHand()
                }
                Spacer(Modifier.height(22.dp))
                Text(p.title, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = c.text, textAlign = TextAlign.Center)
                Spacer(Modifier.height(14.dp))
                Text(p.text, style = PufyType.body, color = c.secondaryText, textAlign = TextAlign.Center)
                Spacer(Modifier.weight(2f))
            }
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(pages.size) { i ->
                val w by animateDpAsState(if (i == pager.currentPage) 18.dp else 6.dp, Springs.quick(), label = "dot")
                Box(Modifier.width(w).height(6.dp).clip(CircleShape).background(c.text.copy(alpha = if (i == pager.currentPage) 1f else 0.2f)))
            }
        }
        Box(Modifier.padding(horizontal = 24.dp).fillMaxWidth().clip(CircleShape).background(c.primary).pressable {
            Haptics.medium(view)
            if (!last) {
                scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
            } else {
                onNext()
            }
        }.padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.continue_text), style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = c.onPrimary)
        }
        Text(stringResource(R.string.onboarding_skip), style = PufyType.subheadline, color = c.secondaryText, modifier = Modifier.align(Alignment.CenterHorizontally)
            .graphicsLayer { alpha = if (last) 0f else 1f }.pressable(enabled = !last, onClick = onFinish).padding(vertical = 8.dp, horizontal = 24.dp))

        val isEn = AppLocales.isEnglish()
        val termsUrl = LegalLinks.terms(!isEn)
        val privacyUrl = LegalLinks.privacy(!isEn)

        val legalAnnotated = remember(isEn) {
            buildAnnotatedString {
                if (isEn) {
                    append("By continuing, you agree to the ")
                    pushStringAnnotation(tag = "terms", annotation = termsUrl)
                    withStyle(SpanStyle(color = c.text, textDecoration = TextDecoration.Underline)) {
                        append("Terms of Service")
                    }
                    pop()
                    append(" and ")
                    pushStringAnnotation(tag = "privacy", annotation = privacyUrl)
                    withStyle(SpanStyle(color = c.text, textDecoration = TextDecoration.Underline)) {
                        append("Privacy Policy")
                    }
                    pop()
                    append(".")
                } else {
                    append("Devam ederek ")
                    pushStringAnnotation(tag = "terms", annotation = termsUrl)
                    withStyle(SpanStyle(color = c.text, textDecoration = TextDecoration.Underline)) {
                        append("Kullanım koşulları")
                    }
                    pop()
                    append(" ve ")
                    pushStringAnnotation(tag = "privacy", annotation = privacyUrl)
                    withStyle(SpanStyle(color = c.text, textDecoration = TextDecoration.Underline)) {
                        append("Gizlilik politikası")
                    }
                    pop()
                    append("'nı kabul etmiş olursun.")
                }
            }
        }

        ClickableText(
            text = legalAnnotated,
            style = PufyType.caption.copy(color = c.secondaryText, textAlign = TextAlign.Center),
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .padding(horizontal = 28.dp)
                .padding(bottom = 12.dp),
            onClick = { offset ->
                legalAnnotated.getStringAnnotations(tag = "terms", start = offset, end = offset).firstOrNull()?.let {
                    try {
                        val ct = CustomTabsIntent.Builder().build()
                        ct.launchUrl(context, Uri.parse(it.item))
                    } catch (_: Throwable) {
                        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it.item))) } catch (_: Throwable) {}
                    }
                }
                legalAnnotated.getStringAnnotations(tag = "privacy", start = offset, end = offset).firstOrNull()?.let {
                    try {
                        val ct = CustomTabsIntent.Builder().build()
                        ct.launchUrl(context, Uri.parse(it.item))
                    } catch (_: Throwable) {
                        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it.item))) } catch (_: Throwable) {}
                    }
                }
            }
        )
    }
}

// MARK: - 2. "Verilerin sende" Ekranı

@Composable
private fun PrivacyStepScreen(onContinue: () -> Unit) {
    val context = LocalContext.current
    val c = Pufy.colors
    val view = LocalView.current
    val isEn = AppLocales.isEnglish()

    val privacyItems = listOf(
        Triple(Icons.Outlined.PhoneAndroid, stringResource(R.string.privacy_item_1_title), stringResource(R.string.privacy_item_1_desc)),
        Triple(Icons.Outlined.PersonOff, stringResource(R.string.privacy_item_2_title), stringResource(R.string.privacy_item_2_desc)),
        Triple(Icons.Outlined.Key, stringResource(R.string.privacy_item_3_title), stringResource(R.string.privacy_item_3_desc)),
        Triple(Icons.Outlined.Send, stringResource(R.string.privacy_item_4_title), stringResource(R.string.privacy_item_4_desc))
    )

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp, vertical = 16.dp)) {
        Spacer(Modifier.height(16.dp))

        // Üst İkon & Başlık
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(88.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(88.dp).clip(CircleShape).background(c.soft))
                Icon(Icons.Outlined.Shield, null, Modifier.size(44.dp), tint = c.primary)
            }
            Text(
                text = stringResource(R.string.privacy_step_title),
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = c.text,
                textAlign = TextAlign.Center
            )
        }

        Spacer(Modifier.height(28.dp))

        // 4 Madde
        Column(
            modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            privacyItems.forEach { (icon, title, desc) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = Modifier.size(36.dp).clip(CircleShape).background(c.soft),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(icon, null, Modifier.size(18.dp), tint = c.primary)
                    }
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(title, style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                        Text(desc, style = PufyType.subheadline, color = c.secondaryText)
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))

        // Devam Butonu
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(CircleShape)
                .background(c.primary)
                .pressable {
                    Haptics.medium(view)
                    onContinue()
                }
                .padding(vertical = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = stringResource(R.string.continue_text),
                style = PufyType.body.copy(fontWeight = FontWeight.SemiBold),
                color = c.onPrimary
            )
        }

        Spacer(Modifier.height(10.dp))

        // Gizlilik politikası linki
        val privacyUrl = LegalLinks.privacy(!isEn)
        Text(
            text = stringResource(R.string.privacy_policy),
            style = PufyType.caption.copy(color = c.secondaryText, textDecoration = TextDecoration.Underline),
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .clickable {
                    try {
                        val ct = CustomTabsIntent.Builder().build()
                        ct.launchUrl(context, Uri.parse(privacyUrl))
                    } catch (_: Throwable) {
                        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(privacyUrl))) } catch (_: Throwable) {}
                    }
                }
                .padding(vertical = 6.dp)
        )
    }
}

// MARK: - 3. Yapay Zekanı Bağla Ekranı (Tüm Sağlayıcılar & Yerel Destek)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ConnectAIScreen(onContinue: () -> Unit, onSkip: () -> Unit) {
    val context = LocalContext.current
    val c = Pufy.colors
    val view = LocalView.current
    val scope = rememberCoroutineScope()

    var selectedProviderId by remember { mutableStateOf("gemini") }
    val currentProvider = remember(selectedProviderId) {
        PROVIDERS.firstOrNull { it.id == selectedProviderId } ?: PROVIDERS.first()
    }

    var customEndpoint by remember { mutableStateOf("") }
    var customFormat by remember { mutableStateOf(ApiFormat.OPENAI) }
    var apiKey by remember { mutableStateOf("") }
    var revealKey by remember { mutableStateOf(false) }
    var model by remember { mutableStateOf("") }

    var isFetchingModels by remember { mutableStateOf(false) }
    var availableModels by remember { mutableStateOf<List<String>?>(null) }
    var showModelDialog by remember { mutableStateOf(false) }
    var modelSearchQuery by remember { mutableStateOf("") }

    var isTesting by remember { mutableStateOf(false) }
    var testSuccess by remember { mutableStateOf(false) }
    var testErrorMessage by remember { mutableStateOf<String?>(null) }

    fun effectiveEndpoint(): String {
        return if (currentProvider.isLocal || selectedProviderId == "custom") {
            if (customEndpoint.isNotBlank()) customEndpoint.trim() else currentProvider.endpoint
        } else {
            currentProvider.endpoint
        }
    }

    fun effectiveFormat(): ApiFormat {
        return if (selectedProviderId == "custom") customFormat else currentProvider.format
    }

    fun effectiveModel(): String {
        val trimmed = model.trim()
        if (trimmed.isNotEmpty()) return trimmed
        return currentProvider.modelHint
    }

    fun saveConfig() {
        val cleanKey = apiKey.trim().removePrefix("Bearer ").trim()
        val ep = effectiveEndpoint()
        val fmt = effectiveFormat()
        val mdl = effectiveModel()
        val isGemini = fmt == ApiFormat.GEMINI

        if (cleanKey.isNotEmpty() || currentProvider.isLocal) {
            AiClient.apiKey = cleanKey
            AiClient.endpoint = ep
            AiClient.apiFormat = fmt
            AiClient.modelName = mdl
            AiClient.heavyModelName = mdl
            AiClient.aiProvider = selectedProviderId
            AiClient.googleSearchEnabled = isGemini
            AiClient.imageModelName = if (isGemini) "gemini-3.1-flash-image" else ""
        }
        onContinue()
    }

    fun isNonLocalInsecureHttp(url: String): Boolean {
        if (!url.startsWith("http://", ignoreCase = true)) return false
        val host = Uri.parse(url).host ?: ""
        val isLocalIp = host == "localhost" || host == "127.0.0.1" || host.endsWith(".local") ||
                host.startsWith("192.168.") || host.startsWith("10.") ||
                (host.startsWith("172.") && host.split(".").getOrNull(1)?.toIntOrNull() in 16..31)
        return !isLocalIp
    }

    Column(Modifier.fillMaxSize().background(c.groupedBackground).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            // Başlık
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.onboarding_connect_ai), fontSize = 26.sp, fontWeight = FontWeight.Bold, color = c.text)
                Text(stringResource(R.string.onboarding_connect_ai_subtitle), style = PufyType.subheadline, color = c.secondaryText)
            }

            // Sağlayıcı Seçimi: 12 seçenek sığsın diye 2 sütunlu ızgara
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.select_provider), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    maxItemsInEachRow = 2
                ) {
                    PROVIDERS.forEach { p ->
                        val isSelected = p.id == selectedProviderId
                        val bg = if (isSelected) (if (c.isDark) Color.White.copy(alpha = 0.15f) else Color.White) else (if (c.isDark) c.secondaryBackground else Color.White.copy(alpha = 0.6f))
                        val borderMod = if (isSelected) Modifier.border(1.5.dp, c.text, RoundedCornerShape(14.dp)) else Modifier

                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(bg)
                                .then(borderMod)
                                .clickable {
                                    Haptics.light(view)
                                    selectedProviderId = p.id
                                    testSuccess = false
                                    testErrorMessage = null
                                    model = p.modelHint
                                    if (p.isLocal) {
                                        customEndpoint = p.endpoint
                                        apiKey = ""
                                    }
                                }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(p.displayTitle(), style = PufyType.body.copy(fontWeight = FontWeight.SemiBold, fontSize = 14.sp), color = if (isSelected) c.text else c.secondaryText, maxLines = 1)
                                if (p.id == "gemini") {
                                    Box(Modifier.clip(CircleShape).background(Color(0xFF34A853).copy(alpha = 0.18f)).padding(horizontal = 5.dp, vertical = 1.dp)) {
                                        Text(stringResource(R.string.free_tier), fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color(0xFF34A853), maxLines = 1, softWrap = false)
                                    }
                                }
                            }
                            Text(
                                text = if (p.isLocal) (if (com.pufy.app.core.AppLocales.isEnglish()) "Local model" else "Yerel model") else if (p.id == "custom") stringResource(R.string.custom_server) else if (p.format == ApiFormat.GEMINI) "Gemini" else (if (com.pufy.app.core.AppLocales.isEnglish()) "OpenAI compatible" else "OpenAI uyumlu"),
                                style = PufyType.caption.copy(fontSize = 11.sp),
                                color = c.tertiaryText
                            )
                        }
                    }
                }
            }

            // Yerel Sağlayıcılar veya Özel Sunucu Adresi
            if (currentProvider.isLocal || selectedProviderId == "custom") {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.address), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if (c.isDark) c.secondaryBackground else Color.White).padding(horizontal = 14.dp, vertical = 12.dp)) {
                        BasicTextField(
                            value = customEndpoint,
                            onValueChange = {
                                customEndpoint = it
                                testSuccess = false
                                testErrorMessage = null
                            },
                            textStyle = PufyType.body.copy(color = c.text),
                            cursorBrush = SolidColor(c.text),
                            modifier = Modifier.fillMaxWidth(),
                            decorationBox = { inner ->
                                if (customEndpoint.isEmpty()) Text(currentProvider.endpoint.ifEmpty { "http://192.168.1.10:11434/v1" }, style = PufyType.body, color = c.tertiaryText)
                                inner()
                            }
                        )
                    }

                    // Güvensiz http uyarısı
                    if (isNonLocalInsecureHttp(effectiveEndpoint())) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Outlined.WarningAmber, null, Modifier.size(15.dp), tint = Color(0xFFE65100))
                            Text(stringResource(R.string.insecure_http_warning), fontSize = 12.sp, color = Color(0xFFE65100))
                        }
                    }

                    // Yerel yardım metni
                    currentProvider.helpText(AppLocales.isEnglish())?.let { help ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.soft).padding(10.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            Icon(Icons.Outlined.Info, null, Modifier.size(16.dp), tint = c.secondaryText)
                            Text(help, style = PufyType.caption, color = c.secondaryText)
                        }
                    }

                    if (selectedProviderId == "custom") {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                                .background(if (customFormat == ApiFormat.GEMINI) c.text else (if (c.isDark) c.secondaryBackground else Color.White))
                                .clickable { customFormat = ApiFormat.GEMINI }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                                Text("Gemini", style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = if (customFormat == ApiFormat.GEMINI) c.background else c.text)
                            }
                            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                                .background(if (customFormat == ApiFormat.OPENAI) c.text else (if (c.isDark) c.secondaryBackground else Color.White))
                                .clickable { customFormat = ApiFormat.OPENAI }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                                Text("OpenAI uyumlu", style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = if (customFormat == ApiFormat.OPENAI) c.background else c.text)
                            }
                        }
                    }
                }
            }

            // API Anahtarı (Yalnızca anahtar gerektiren sağlayıcılar)
            if (!currentProvider.isLocal) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.api_key), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, modifier = Modifier.weight(1f))
                        currentProvider.keyUrl?.let { url ->
                            Row(Modifier.clickable {
                                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                            }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(stringResource(R.string.get_key), style = PufyType.footnote.copy(fontWeight = FontWeight.Medium), color = c.primary)
                                Icon(Icons.Outlined.OpenInNew, null, Modifier.size(13.dp), tint = c.primary)
                            }
                        }
                    }

                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if (c.isDark) c.secondaryBackground else Color.White).padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) {
                            BasicTextField(
                                value = apiKey,
                                onValueChange = { apiKey = it; testSuccess = false; testErrorMessage = null },
                                textStyle = PufyType.body.copy(color = c.text),
                                cursorBrush = SolidColor(c.text),
                                visualTransformation = if (revealKey) VisualTransformation.None else PasswordVisualTransformation(),
                                modifier = Modifier.fillMaxWidth(),
                                decorationBox = { inner ->
                                    if (apiKey.isEmpty()) Text(stringResource(R.string.paste_api_key), style = PufyType.body, color = c.tertiaryText)
                                    inner()
                                }
                            )
                        }

                        Icon(
                            imageVector = if (revealKey) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = null,
                            tint = c.tertiaryText,
                            modifier = Modifier.size(20.dp).clickable { revealKey = !revealKey }
                        )

                        Spacer(Modifier.width(10.dp))

                        Text(
                            text = stringResource(R.string.paste),
                            style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold),
                            color = c.primary,
                            modifier = Modifier.clickable {
                                val clip = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                                val text = clip?.primaryClip?.getItemAt(0)?.text?.toString()
                                if (!text.isNullOrBlank()) {
                                    apiKey = text.trim()
                                    testSuccess = false
                                    testErrorMessage = null
                                }
                            }
                        )
                    }
                }
            }

            // Model Alanı
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.model), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if (c.isDark) c.secondaryBackground else Color.White).padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        BasicTextField(
                            value = model,
                            onValueChange = { model = it; testSuccess = false; testErrorMessage = null },
                            textStyle = PufyType.body.copy(color = c.text),
                            cursorBrush = SolidColor(c.text),
                            modifier = Modifier.fillMaxWidth(),
                            decorationBox = { inner ->
                                if (model.isEmpty()) Text(currentProvider.modelHint.ifEmpty { if (com.pufy.app.core.AppLocales.isEnglish()) "Model name" else "Model adı" }, style = PufyType.body, color = c.tertiaryText)
                                inner()
                            }
                        )
                    }

                    val canFetch = !currentProvider.requiresKey || apiKey.isNotBlank()
                    if (isFetchingModels) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = c.primary, strokeWidth = 2.dp)
                    } else {
                        Row(Modifier.clickable(enabled = canFetch) {
                            isFetchingModels = true
                            scope.launch {
                                runCatching {
                                    AiClient.fetchModels(effectiveEndpoint(), effectiveFormat(), apiKey.trim())
                                }.onSuccess { list ->
                                    isFetchingModels = false
                                    availableModels = list
                                    showModelDialog = true
                                }.onFailure {
                                    isFetchingModels = false
                                    testErrorMessage = if (currentProvider.isLocal) context.getString(R.string.local_connection_failed) else (it.message ?: "Modeller getirilemedi.")
                                }
                            }
                        }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Outlined.CloudDownload, null, Modifier.size(16.dp), tint = if (canFetch) c.primary else c.tertiaryText)
                            Text(stringResource(R.string.fetch_models), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = if (canFetch) c.primary else c.tertiaryText)
                        }
                    }
                }
            }

            // Bağlantıyı Dene Butonu
            val canTest = !currentProvider.requiresKey || apiKey.isNotBlank()
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.fillMaxWidth().clip(CircleShape).background(c.soft).clickable(enabled = !isTesting && canTest) {
                    Haptics.light(view)
                    isTesting = true
                    testSuccess = false
                    testErrorMessage = null
                    scope.launch {
                        val res = AiClient.testConnectionDetailed(
                            endpoint = effectiveEndpoint(),
                            format = effectiveFormat(),
                            apiKey = apiKey.trim(),
                            model = effectiveModel()
                        )
                        isTesting = false
                        res.onSuccess {
                            testSuccess = true
                            Haptics.success(view)
                        }.onFailure {
                            testErrorMessage = if (currentProvider.isLocal) context.getString(R.string.local_connection_failed) else (it.message ?: "Bağlantı kurulamadı.")
                            Haptics.medium(view)
                        }
                    }
                }.padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                    if (isTesting) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = c.text, strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.test_connection), style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = if (canTest) c.text else c.tertiaryText)
                    }
                }

                if (testSuccess) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Outlined.CheckCircle, null, Modifier.size(18.dp), tint = Color(0xFF34A853))
                        Text(stringResource(R.string.connected_success), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color(0xFF34A853))
                    }
                } else if (testErrorMessage != null) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(18.dp), tint = Color(0xFFEA4335))
                            Text(testErrorMessage ?: "", style = PufyType.subheadline, color = Color(0xFFEA4335))
                        }
                        Text(stringResource(R.string.continue_anyway), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, modifier = Modifier.clickable { saveConfig() })
                    }
                }
            }
        }

        // Alt Butonlar (Devam & Sonra Yaparım)
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val canProceed = testSuccess || apiKey.isBlank() || currentProvider.isLocal
            Box(Modifier.fillMaxWidth().clip(CircleShape).background(if (canProceed) c.primary else c.primary.copy(alpha = 0.5f)).pressable(enabled = canProceed) {
                Haptics.medium(view)
                saveConfig()
            }.padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.continue_text), style = PufyType.body.copy(fontWeight = FontWeight.SemiBold), color = c.onPrimary)
            }

            Text(stringResource(R.string.do_it_later), style = PufyType.subheadline, color = c.secondaryText, modifier = Modifier.clickable { onSkip() }.padding(vertical = 6.dp))
        }
    }

    // Model Seçici Dialog
    if (showModelDialog && availableModels != null) {
        val filtered = remember(modelSearchQuery, availableModels) {
            val list = availableModels ?: emptyList()
            if (modelSearchQuery.isBlank()) list
            else list.filter { it.contains(modelSearchQuery, ignoreCase = true) }
        }
        AlertDialog(
            onDismissRequest = { showModelDialog = false },
            title = { Text(stringResource(R.string.models_title), style = PufyType.headline) },
            text = {
                Column(Modifier.fillMaxWidth().height(360.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (c.isDark) c.secondaryBackground else Color.White).padding(10.dp)) {
                        BasicTextField(
                            value = modelSearchQuery,
                            onValueChange = { modelSearchQuery = it },
                            textStyle = PufyType.body.copy(color = c.text),
                            modifier = Modifier.fillMaxWidth(),
                            decorationBox = { inner ->
                                if (modelSearchQuery.isEmpty()) Text(stringResource(R.string.search_models), style = PufyType.body, color = c.tertiaryText)
                                inner()
                            }
                        )
                    }
                    LazyColumn(Modifier.weight(1f)) {
                        items(filtered) { m ->
                            Row(Modifier.fillMaxWidth().clickable {
                                model = m
                                showModelDialog = false
                                testSuccess = false
                            }.padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(m, style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showModelDialog = false }) { Text(stringResource(R.string.close)) }
            }
        )
    }
}

@Composable
private fun SwipeHand() {
    val t by rememberInfiniteTransition(label = "hand").animateFloat(0f, 1f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing)), label = "t")
    Icon(Icons.Rounded.TouchApp, null, Modifier.offset(x = (60 - 70 * t).dp, y = 52.dp).size(32.dp).graphicsLayer { alpha = 1 - t }, tint = Pufy.colors.secondaryText)
}
