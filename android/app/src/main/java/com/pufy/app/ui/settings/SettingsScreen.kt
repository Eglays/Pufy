package com.pufy.app.ui.settings

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.ApiFormat
import com.pufy.app.core.LegalLinks
import com.pufy.app.core.AIReportStore
import com.pufy.app.data.AppFiles
import com.pufy.app.data.Profile
import com.pufy.app.data.ChatStore
import com.pufy.app.data.MemoryStore
import com.pufy.app.data.NoteStore
import com.pufy.app.data.ReminderStore
import com.pufy.app.sync.SyncService
import com.pufy.app.ui.chat.prepareImage
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import kotlinx.coroutines.launch
import androidx.browser.customtabs.CustomTabsIntent

// iOS SettingsView karşılığı: profil, yapay zeka, görsel oluşturma, hesap

fun openWebUrl(context: android.content.Context, url: String) {
    runCatching {
        val customTabsIntent = CustomTabsIntent.Builder().build()
        customTabsIntent.launchUrl(context, Uri.parse(url))
    }.onFailure {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }
}

@Composable
fun SettingsScreen(onClose: () -> Unit) {
    val c = Pufy.colors
    val context = LocalContext.current
    var confirmDeleteStep1 by remember { mutableStateOf(false) }
    var confirmDeleteStep2 by remember { mutableStateOf(false) }
    var showHowToUse by remember { mutableStateOf(false) }

    fun executeDeleteAllData() {
        ChatStore.clearAll()
        MemoryStore.clearAll()
        NoteStore.clearAll()
        ReminderStore.clearAll()
        runCatching { AppFiles.miniApps.deleteRecursively() }
        runCatching { AppFiles.miniAppData.deleteRecursively() }
        AIReportStore.clearAll()
        com.pufy.app.core.Settings.clearAll()
        com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.ONBOARDING_DONE, false)
        com.pufy.app.ui.AppNav.onboarding.value = true
        onClose()
    }

    Column(Modifier.fillMaxSize().background(c.groupedBackground).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.settings_title), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = c.text, modifier = Modifier.weight(1f).padding(start = 4.dp))
            GlassIconButton(Icons.Rounded.Close, androidx.compose.ui.res.stringResource(com.pufy.app.R.string.close), size = 40.dp, iconSize = 18.dp, onClick = onClose)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)) {
            ProfileSection()
            AiSection()
            ImageSection()
            LanguageSection()

            // Tüm verilerimi sil satırı
            Group(title = null) {
                Row(
                    Modifier.fillMaxWidth()
                        .pressable { confirmDeleteStep1 = true }
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Text(
                        stringResource(R.string.delete_all_data),
                        style = PufyType.body.copy(fontWeight = FontWeight.Medium),
                        color = Color(0xFFFF3B30)
                    )
                }
            }

            // Yardım grubu
            Group(stringResource(R.string.help)) {
                Row(
                    Modifier.fillMaxWidth().pressable { showHowToUse = true }.padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.how_to_use), style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, Modifier.size(16.dp), tint = c.tertiaryText)
                }
                RowDivider()
                Row(
                    Modifier.fillMaxWidth().pressable {
                        com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.COACH_MARKS_COMPLETED, false)
                        com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_NEW_APP_SHOWN, false)
                        com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_MINI_EXIT_SHOWN, false)
                        com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.HINT_MEMORY_SHOWN, false)
                        onClose()
                    }.padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.reset_hints), style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                    Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(16.dp), tint = c.tertiaryText)
                }
            }

            // Hakkında ve yasal grubu
            Group(stringResource(R.string.about_and_legal)) {
                LegalRow(stringResource(R.string.privacy_policy)) {
                    openWebUrl(context, LegalLinks.privacy())
                }
                RowDivider()
                LegalRow(stringResource(R.string.terms_of_service)) {
                    openWebUrl(context, LegalLinks.terms())
                }
                RowDivider()
                LegalRow(stringResource(R.string.support)) {
                    openWebUrl(context, LegalLinks.support())
                }
                RowDivider()
                LegalRow(stringResource(R.string.account_and_data_deletion)) {
                    openWebUrl(context, LegalLinks.deletion())
                }
                RowDivider()
                Row(Modifier.fillMaxWidth().clickable {
                    com.pufy.app.core.Settings.setBool(com.pufy.app.core.Settings.ONBOARDING_DONE, false)
                    com.pufy.app.ui.AppNav.onboarding.value = true
                    onClose()
                }.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.show_onboarding_again), style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                }
            }

            // Sürüm etiketi
            Text(
                "Pufy 2.9.1 · Android",
                style = PufyType.caption,
                color = c.tertiaryText,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(bottom = 24.dp)
            )
        }
    }

    if (confirmDeleteStep1) {
        AlertDialog(
            onDismissRequest = { confirmDeleteStep1 = false },
            title = { Text(stringResource(R.string.delete_all_data_title)) },
            text = { Text(stringResource(R.string.delete_all_data_desc)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteStep1 = false
                        confirmDeleteStep2 = true
                    }
                ) {
                    Text(stringResource(R.string.delete), color = Color(0xFFFF3B30), fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteStep1 = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    if (confirmDeleteStep2) {
        AlertDialog(
            onDismissRequest = { confirmDeleteStep2 = false },
            title = { Text(stringResource(R.string.delete_all_data_confirm_title)) },
            text = { Text(stringResource(R.string.delete_all_data_confirm_desc)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteStep2 = false
                        executeDeleteAllData()
                    }
                ) {
                    Text(stringResource(R.string.delete_everything), color = Color(0xFFFF3B30), fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteStep2 = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    androidx.compose.animation.AnimatedVisibility(
        visible = showHowToUse,
        enter = fadeIn() + slideInVertically { it },
        exit = fadeOut() + slideOutVertically { it }
    ) {
        HowToUseScreen(onClose = { showHowToUse = false })
    }
}

@Composable
private fun LegalRow(title: String, onClick: () -> Unit) {
    val c = Pufy.colors
    Row(
        Modifier.fillMaxWidth().pressable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, Modifier.size(16.dp), tint = c.tertiaryText)
    }
}

@Composable
fun Group(title: String?, footer: String? = null, content: @Composable () -> Unit) {
    val c = Pufy.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        title?.let { Text(it.uppercase(), style = PufyType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp)) }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(if (c.isDark) c.secondaryBackground else Color.White)) { content() }
        footer?.let { Text(it, style = PufyType.footnote, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp)) }
    }
}

@Composable private fun RowDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Pufy.colors.separator.copy(alpha = 0.5f))

@Composable
fun Field(label: String, value: String, onChange: (String) -> Unit, placeholder: String = "", secret: Boolean = false, keyboard: KeyboardType = KeyboardType.Text) {
    val c = Pufy.colors
    var reveal by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = PufyType.body, color = c.text, modifier = Modifier.padding(end = 12.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            if (value.isEmpty()) Text(placeholder, style = PufyType.body, color = c.tertiaryText)
            BasicTextField(value, onChange, singleLine = true, textStyle = PufyType.body.copy(color = c.secondaryText, textAlign = androidx.compose.ui.text.style.TextAlign.End),
                cursorBrush = SolidColor(c.text), keyboardOptions = KeyboardOptions(keyboardType = if (secret) KeyboardType.Password else keyboard, autoCorrectEnabled = false),
                visualTransformation = if (secret && !reveal) PasswordVisualTransformation() else VisualTransformation.None, modifier = Modifier.fillMaxWidth())
        }
        if (secret) Icon(if (reveal) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, if (reveal) stringResource(R.string.hide) else stringResource(R.string.show),
            Modifier.padding(start = 8.dp).size(18.dp).pressable { reveal = !reveal }, tint = c.secondaryText)
    }
}

@Composable
private fun SelectRow(label: String, value: String, onClick: () -> Unit) {
    val c = Pufy.colors
    Row(Modifier.fillMaxWidth().pressable(scale = 0.99f, onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
        Text(value, style = PufyType.body, color = c.secondaryText)
    }
}

@Composable
private fun KeyField(value: String, onChange: (String) -> Unit, keyUrl: String?) {
    val c = Pufy.colors
    val context = LocalContext.current
    var reveal by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.api_key), style = PufyType.body, color = c.text, modifier = Modifier.padding(end = 12.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                if (value.isEmpty()) Text(stringResource(R.string.if_needed), style = PufyType.body, color = c.tertiaryText)
                BasicTextField(
                    value = value,
                    onValueChange = onChange,
                    singleLine = true,
                    textStyle = PufyType.body.copy(color = c.secondaryText, textAlign = androidx.compose.ui.text.style.TextAlign.End),
                    cursorBrush = SolidColor(c.text),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    visualTransformation = if (!reveal) PasswordVisualTransformation() else VisualTransformation.None,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Icon(
                if (reveal) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                if (reveal) stringResource(R.string.hide) else stringResource(R.string.show),
                Modifier.padding(start = 8.dp).size(18.dp).pressable { reveal = !reveal },
                tint = c.secondaryText
            )
        }
        if (!keyUrl.isNullOrBlank()) {
            Text(
                stringResource(R.string.get_key),
                style = PufyType.caption.copy(color = c.secondaryText),
                modifier = Modifier
                    .padding(top = 4.dp)
                    .pressable {
                        runCatching {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(keyUrl)))
                        }
                    }
            )
        }
    }
}

@Composable
private fun ModelField(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    placeholder: String = "",
    onFetch: () -> Unit,
    fetching: Boolean = false,
) {
    val c = Pufy.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = PufyType.caption, color = c.secondaryText)
            Box(Modifier.fillMaxWidth().padding(top = 2.dp)) {
                if (value.isEmpty()) Text(placeholder, style = PufyType.body, color = c.tertiaryText)
                BasicTextField(
                    value = value,
                    onValueChange = onChange,
                    singleLine = true,
                    textStyle = PufyType.body.copy(color = c.text),
                    cursorBrush = SolidColor(c.text),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        Text(
            if (fetching) stringResource(R.string.fetching) else stringResource(R.string.fetch_models),
            style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold),
            color = if (fetching) c.tertiaryText else c.text,
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(c.soft)
                .pressable(enabled = !fetching, onClick = onFetch)
                .padding(horizontal = 10.dp, vertical = 6.dp)
        )
    }
}

@Composable
private fun Toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = Pufy.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
        Switch(checked, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Color(0xFF34C759), checkedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent,
            uncheckedTrackColor = c.disabled, uncheckedThumbColor = Color.White))
    }
}

@Composable
private fun ActionRow(label: String, color: Color = Pufy.colors.text, busy: Boolean = false, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().pressable(scale = 0.99f, enabled = !busy, onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = PufyType.body.copy(fontWeight = FontWeight.Medium), color = color, modifier = Modifier.weight(1f))
        if (busy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Pufy.colors.secondaryText)
    }
}

@Composable
private fun ProfileSection() {
    val c = Pufy.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val name by Profile.nameFlow.collectAsState()
    var draft by remember(name) { mutableStateOf(name) }
    val avatarVersion by Profile.avatarVersion.collectAsState()
    val avatar = remember(avatarVersion) { Profile.avatarBytes()?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            prepareImage(context, uri)?.let { data ->
                val small = prepareImage(data, 512) ?: data
                Profile.setAvatar(small); SyncService.avatarChanged()
            }
        }
    }
    Group(stringResource(R.string.settings_profile)) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(68.dp).pressable { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Box(Modifier.size(64.dp).clip(CircleShape).background(c.soft), contentAlignment = Alignment.Center) {
                    if (avatar != null) Image(avatar, stringResource(R.string.profile_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Icon(Icons.Rounded.AccountCircle, stringResource(R.string.profile_photo), Modifier.fillMaxSize(), tint = c.primary.copy(alpha = 0.7f))
                }
                Box(Modifier.align(Alignment.BottomEnd).size(24.dp).clip(CircleShape).background(if (c.isDark) c.secondaryBackground else Color.White).padding(2.dp)
                    .clip(CircleShape).background(c.primary), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.CameraAlt, stringResource(R.string.change_photo), Modifier.size(12.dp), tint = c.onPrimary)
                }
            }
            Column(Modifier.weight(1f)) {
                Text(if (com.pufy.app.core.AppLocales.isEnglish()) "Full name" else "Ad Soyad", style = PufyType.caption, color = c.secondaryText)
                Box {
                    if (draft.isEmpty()) Text(if (com.pufy.app.core.AppLocales.isEnglish()) "Type your name" else "Adını ve soyadını yaz", style = PufyType.headline, color = c.tertiaryText)
                    BasicTextField(draft, { draft = it; Profile.setName(it) }, singleLine = true, textStyle = PufyType.headline.copy(color = c.text),
                        cursorBrush = SolidColor(c.text), modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

data class ProviderInfo(
    val id: String,
    val title: String,
    val endpoint: String,
    val format: ApiFormat,
    val keyUrl: String?,
    val modelHint: String = "gemini-2.5-flash",
    val isLocal: Boolean = false,
    val requiresKey: Boolean = true,
    val helpTextTr: String? = null,
    val helpTextEn: String? = null
) {
    fun helpText(isEn: Boolean): String? = if (isEn) helpTextEn else helpTextTr
    fun displayTitle(isEn: Boolean = com.pufy.app.core.AppLocales.isEnglish()): String = when (id) {
        "custom" -> if (isEn) "Custom server" else "Özel sunucu"
        "ollama" -> if (isEn) "Ollama (local)" else "Ollama (yerel)"
        "lmstudio" -> if (isEn) "LM Studio (local)" else "LM Studio (yerel)"
        else -> title
    }
}

val PROVIDERS = listOf(
    ProviderInfo("gemini", "Google Gemini", "https://generativelanguage.googleapis.com", ApiFormat.GEMINI, "https://aistudio.google.com/apikey", "gemini-2.5-flash"),
    ProviderInfo("openai", "OpenAI", "https://api.openai.com/v1", ApiFormat.OPENAI, "https://platform.openai.com/api-keys", "gpt-4o-mini"),
    ProviderInfo("anthropic", "Anthropic Claude", "https://api.anthropic.com/v1", ApiFormat.OPENAI, "https://console.anthropic.com/settings/keys", "claude-3-5-haiku-20241022"),
    ProviderInfo("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", ApiFormat.OPENAI, "https://openrouter.ai/keys", "google/gemini-2.5-flash"),
    ProviderInfo("nvidia", "NVIDIA", "https://integrate.api.nvidia.com/v1", ApiFormat.OPENAI, "https://build.nvidia.com/settings/api-keys", "meta/llama-3.3-70b-instruct"),
    ProviderInfo("groq", "Groq", "https://api.groq.com/openai/v1", ApiFormat.OPENAI, "https://console.groq.com/keys", "llama-3.3-70b-versatile"),
    ProviderInfo("deepseek", "DeepSeek", "https://api.deepseek.com/v1", ApiFormat.OPENAI, "https://platform.deepseek.com/api_keys", "deepseek-chat"),
    ProviderInfo("mistral", "Mistral", "https://api.mistral.ai/v1", ApiFormat.OPENAI, "https://console.mistral.ai/api-keys", "mistral-small-latest"),
    ProviderInfo("xai", "xAI", "https://api.x.ai/v1", ApiFormat.OPENAI, "https://console.x.ai", "grok-2-latest"),
    ProviderInfo("ollama", "Ollama (yerel)", "http://192.168.1.10:11434/v1", ApiFormat.OPENAI, null, "", isLocal = true, requiresKey = false,
        helpTextTr = "Bilgisayarında Ollama'yı ağdan erişilebilir başlat (OLLAMA_HOST=0.0.0.0 ollama serve). Telefonun ve bilgisayarın aynı Wi-Fi'de olmalı. Adrese bilgisayarının yerel IP'sini yaz.",
        helpTextEn = "Start Ollama on your computer accessible over the network (OLLAMA_HOST=0.0.0.0 ollama serve). Your phone and computer must be on the same Wi-Fi. Enter your computer's local IP address."),
    ProviderInfo("lmstudio", "LM Studio (yerel)", "http://192.168.1.10:1234/v1", ApiFormat.OPENAI, null, "", isLocal = true, requiresKey = false,
        helpTextTr = "LM Studio → Developer → Local Server'ı aç, 'Serve on Local Network' seçeneğini işaretle. Port 1234.",
        helpTextEn = "Open LM Studio → Developer → Local Server, check 'Serve on Local Network'. Port 1234."),
    ProviderInfo("custom", "Özel sunucu", "", ApiFormat.GEMINI, null, "", requiresKey = false)
)

@Composable
private fun AiSection() {
    val scope = rememberCoroutineScope()
    var providerId by remember { mutableStateOf(AiClient.aiProvider) }
    var endpoint by remember { mutableStateOf(AiClient.endpoint) }
    var key by remember { mutableStateOf(AiClient.apiKey) }
    var model by remember { mutableStateOf(AiClient.modelName) }
    var heavy by remember { mutableStateOf(AiClient.heavyModelName) }
    var search by remember { mutableStateOf(AiClient.googleSearchEnabled) }
    var customFormat by remember { mutableStateOf(AiClient.apiFormat) }

    var showProviderDialog by remember { mutableStateOf(false) }
    var fetchingMain by remember { mutableStateOf(false) }
    var fetchingHeavy by remember { mutableStateOf(false) }
    var availableModels by remember { mutableStateOf<List<String>?>(null) }
    var modelTarget by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val currentProv = remember(providerId) { PROVIDERS.firstOrNull { it.id == providerId } ?: PROVIDERS.last() }

    fun fetch(target: String) {
        if (target == "main") fetchingMain = true else fetchingHeavy = true
        scope.launch {
            runCatching {
                val format = if (providerId == "custom") customFormat else currentProv.format
                val ep = if (providerId == "custom") endpoint else currentProv.endpoint
                AiClient.fetchModels(ep, format, key)
            }.onSuccess { list ->
                if (list.isEmpty()) {
                    errorMessage = if (com.pufy.app.core.AppLocales.isEnglish()) "Model list returned empty." else "Model listesi boş döndü."
                } else {
                    availableModels = list
                    modelTarget = target
                }
            }.onFailure {
                errorMessage = it.message ?: (if (com.pufy.app.core.AppLocales.isEnglish()) "Could not connect to host. Are you on the same Wi-Fi?" else "Bilgisayara ulaşılamadı. Aynı Wi-Fi'de misiniz?")
            }
            fetchingMain = false
            fetchingHeavy = false
        }
    }

    val isEn = com.pufy.app.core.AppLocales.isEnglish()

    Group(stringResource(R.string.settings_ai), footer = stringResource(R.string.key_stored_securely)) {
        SelectRow(stringResource(R.string.provider), currentProv.displayTitle(isEn)) { showProviderDialog = true }

        if (providerId == "custom" || currentProv.isLocal) {
            RowDivider()
            Field(stringResource(R.string.address), endpoint, { endpoint = it; AiClient.endpoint = it }, "http://…", keyboard = KeyboardType.Uri)

            val isInsecureHttp = endpoint.lowercase().startsWith("http://") &&
                !endpoint.contains("192.168.") && !endpoint.contains("10.") &&
                !endpoint.contains("172.") && !endpoint.contains("localhost") &&
                !endpoint.contains("127.0.0.1")
            if (isInsecureHttp) {
                Text(
                    if (isEn) "Insecure connection, use https" else "Güvenli olmayan bağlantı, https kullan",
                    style = PufyType.caption,
                    color = Color(0xFFFF9500),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }

            currentProv.helpText(isEn)?.let { help ->
                Text(
                    help,
                    style = PufyType.caption,
                    color = Pufy.colors.secondaryText,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }
        }

        if (providerId == "custom") {
            RowDivider()
            SelectRow(stringResource(R.string.format), if (customFormat == ApiFormat.GEMINI) stringResource(R.string.gemini_compatible) else stringResource(R.string.openai_compatible)) {
                val next = if (customFormat == ApiFormat.GEMINI) ApiFormat.OPENAI else ApiFormat.GEMINI
                customFormat = next
                AiClient.apiFormat = next
            }
        }

        if (!currentProv.isLocal) { // özel sunucuda anahtar isteğe bağlı ama alan görünür
            RowDivider()
            KeyField(key, { key = it; AiClient.apiKey = it }, currentProv.keyUrl)
        }

        RowDivider()
        ModelField(stringResource(R.string.model), model, { model = it; AiClient.modelName = it }, currentProv.modelHint.ifEmpty { "model" }, onFetch = { fetch("main") }, fetching = fetchingMain)

        RowDivider()
        ModelField(stringResource(R.string.heavy_model), heavy, { heavy = it; AiClient.heavyModelName = it }, if (isEn) "empty = main model" else "boş = ana model", onFetch = { fetch("heavy") }, fetching = fetchingHeavy)

        if (providerId == "gemini" || (providerId == "custom" && customFormat == ApiFormat.GEMINI)) {
            RowDivider()
            Toggle(stringResource(R.string.search_on_web), search) { search = it; AiClient.googleSearchEnabled = it }
        }
    }

    if (showProviderDialog) {
        AlertDialog(
            onDismissRequest = { showProviderDialog = false },
            title = { Text(stringResource(R.string.select_provider)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    PROVIDERS.forEach { p ->
                        val pTitle = p.displayTitle(isEn)
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable {
                                providerId = p.id
                                AiClient.aiProvider = p.id
                                if (p.id != "custom") {
                                    endpoint = p.endpoint
                                    AiClient.endpoint = p.endpoint
                                    customFormat = p.format
                                    AiClient.apiFormat = p.format
                                    model = p.modelHint
                                    AiClient.modelName = p.modelHint
                                }
                                showProviderDialog = false
                            }.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(pTitle, style = PufyType.body, color = Pufy.colors.text, modifier = Modifier.weight(1f))
                            if (p.id == providerId) {
                                Text("✓", color = Pufy.colors.primary, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton({ showProviderDialog = false }) { Text(stringResource(R.string.close)) } }
        )
    }

    availableModels?.let { list ->
        AlertDialog(
            onDismissRequest = { availableModels = null; modelTarget = null },
            title = { Text(stringResource(R.string.select_model)) },
            text = {
                Box(Modifier.height(300.dp)) {
                    LazyColumn {
                        items(list) { m ->
                            Text(
                                m,
                                style = PufyType.body,
                                color = Pufy.colors.text,
                                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable {
                                    if (modelTarget == "main") {
                                        model = m
                                        AiClient.modelName = m
                                    } else {
                                        heavy = m
                                        AiClient.heavyModelName = m
                                    }
                                    availableModels = null
                                    modelTarget = null
                                }.padding(horizontal = 12.dp, vertical = 10.dp)
                            )
                        }
                    }
                }
            },
            confirmButton = { TextButton({ availableModels = null; modelTarget = null }) { Text(stringResource(R.string.cancel)) } }
        )
    }

    errorMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(stringResource(R.string.error)) },
            text = { Text(msg) },
            confirmButton = { TextButton({ errorMessage = null }) { Text(stringResource(R.string.ok)) } }
        )
    }
}

private data class ImageOption(val id: String, val title: String)

private val IMAGE_OPTIONS = listOf(
    ImageOption("off", "Kapalı"),
    ImageOption("same", "Sohbetle aynı (Gemini)"),
    ImageOption("gemini", "Google Gemini"),
    ImageOption("openai", "OpenAI")
)

@Composable
private fun ImageSection() {
    var imageProv by remember { mutableStateOf(AiClient.imageProvider) }
    var imageKey by remember { mutableStateOf(AiClient.imageApiKey) }
    var imageModel by remember { mutableStateOf(AiClient.imageModelName) }
    var showDialog by remember { mutableStateOf(false) }

    val current = remember(imageProv) { IMAGE_OPTIONS.firstOrNull { it.id == imageProv } ?: IMAGE_OPTIONS.first() }
    val currentTitle = when (current.id) {
        "off" -> stringResource(R.string.option_off)
        "same" -> stringResource(R.string.same_as_chat)
        else -> current.title
    }

    Group(stringResource(R.string.settings_image)) {
        SelectRow(stringResource(R.string.option), currentTitle) { showDialog = true }

        if (imageProv == "gemini" || imageProv == "openai") {
            RowDivider()
            Field(
                stringResource(R.string.api_key),
                imageKey,
                { imageKey = it; AiClient.imageApiKey = it },
                stringResource(R.string.chat_key_if_empty),
                secret = true
            )
            RowDivider()
            Field(
                stringResource(R.string.image_model),
                imageModel,
                { imageModel = it; AiClient.imageModelName = it },
                if (imageProv == "openai") "dall-e-3" else "gemini-3.1-flash-image"
            )
        }
    }

    if (showDialog) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(stringResource(R.string.settings_image)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    IMAGE_OPTIONS.forEach { opt ->
                        val optTitle = when (opt.id) {
                            "off" -> stringResource(R.string.option_off)
                            "same" -> stringResource(R.string.same_as_chat)
                            else -> opt.title
                        }
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable {
                                imageProv = opt.id
                                AiClient.imageProvider = opt.id
                                if (opt.id == "openai" && (imageModel.isBlank() || imageModel.startsWith("gemini"))) {
                                    imageModel = "dall-e-3"
                                    AiClient.imageModelName = "dall-e-3"
                                } else if (opt.id != "openai" && imageModel.startsWith("dall-e")) {
                                    imageModel = "gemini-3.1-flash-image"
                                    AiClient.imageModelName = "gemini-3.1-flash-image"
                                }
                                showDialog = false
                            }.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(optTitle, style = PufyType.body, color = Pufy.colors.text, modifier = Modifier.weight(1f))
                            if (opt.id == imageProv) Text("✓", color = Pufy.colors.primary, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            },
            confirmButton = { TextButton({ showDialog = false }) { Text(stringResource(R.string.close)) } }
        )
    }
}

@Composable
private fun LanguageSection() {
    var selectedLang by remember { mutableStateOf(com.pufy.app.core.AppLocales.getSelectedLanguage()) }
    var showDialog by remember { mutableStateOf(false) }

    Group(title = androidx.compose.ui.res.stringResource(com.pufy.app.R.string.settings_language)) {
        val currentLabel = when (selectedLang) {
            com.pufy.app.core.AppLocales.TURKISH -> "Türkçe"
            com.pufy.app.core.AppLocales.ENGLISH -> "English"
            else -> androidx.compose.ui.res.stringResource(com.pufy.app.R.string.lang_auto)
        }
        SelectRow(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.settings_language), currentLabel) {
            showDialog = true
        }
    }

    if (showDialog) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.settings_language)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val options = listOf(
                        com.pufy.app.core.AppLocales.AUTO to androidx.compose.ui.res.stringResource(com.pufy.app.R.string.lang_auto),
                        com.pufy.app.core.AppLocales.TURKISH to "Türkçe",
                        com.pufy.app.core.AppLocales.ENGLISH to "English"
                    )
                    options.forEach { (code, label) ->
                        Row(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .clickable {
                                    selectedLang = code
                                    com.pufy.app.core.AppLocales.setLanguage(code)
                                    showDialog = false
                                }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(label, style = PufyType.body, color = if (selectedLang == code) Pufy.colors.primary else Pufy.colors.text, modifier = Modifier.weight(1f))
                            if (selectedLang == code) Text("✓", color = Pufy.colors.primary, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            },
            confirmButton = { TextButton({ showDialog = false }) { Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.close)) } }
        )
    }
}
