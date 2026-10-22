package com.pufy.app.ui.creator

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Calculate
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.Spellcheck
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.apps.AgentStep
import com.pufy.app.apps.CreatorSession
import com.pufy.app.apps.FileProgress
import com.pufy.app.apps.MiniAppFiles
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.Message
import com.pufy.app.ui.chat.MarkdownView
import com.pufy.app.ui.components.AppIconTile
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.PulsingPufy
import com.pufy.app.ui.components.ShimmerText
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs

// iOS AppCreatorView karşılığı: uygulamayı sohbet ederek yaz / düzenle, canlı ilerleme, sürüm geçmişi

private val suggestions = listOf(
    Icons.Outlined.GridView to R.string.sugg_block_game, Icons.Outlined.CreditCard to R.string.sugg_expense_tracker,
    Icons.Outlined.Timer to R.string.sugg_pomodoro, Icons.Outlined.Spellcheck to R.string.sugg_word_game,
    Icons.Outlined.ShoppingCart to R.string.sugg_shopping_list, Icons.Outlined.WaterDrop to R.string.sugg_water_tracker,
)

@Composable
fun CreatorScreen(
    session: CreatorSession,
    initialPrompt: String?,
    initialName: String? = null,
    autoSend: Boolean = true,
    onClose: () -> Unit,
    onOpen: (String) -> Unit
) {
    val c = Pufy.colors
    val view = LocalView.current
    val name by session.name.collectAsState()
    val icon by session.icon.collectAsState()
    val color by session.colorHex.collectAsState()
    val messages by session.messages.collectAsState()
    val versions by session.versions.collectAsState()
    val building by session.builder.isBuilding.collectAsState()
    var prompt by remember { mutableStateOf(if (!autoSend) initialPrompt ?: "" else "") }
    var restoreTarget by remember { mutableStateOf<MiniAppFiles.Version?>(null) }
    var historyMenu by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val list = rememberLazyListState()
    val hasFiles = session.appID != null || MiniAppFiles.hasFiles(session.folder)

    LaunchedEffect(Unit) {
        if (!initialName.isNullOrBlank() && session.name.value.isBlank()) {
            session.name.value = initialName
        }
        if (autoSend && !initialPrompt.isNullOrBlank()) {
            kotlinx.coroutines.delay(400); session.send(initialPrompt)
        } else if (session.appID == null && messages.isEmpty()) {
            kotlinx.coroutines.delay(500); runCatching { focus.requestFocus() }
        }
    }
    LaunchedEffect(messages.size, building) { list.animateScrollToItem(maxOf(0, list.layoutInfo.totalItemsCount - 1)) }
    DisposableEffect(Unit) { onDispose { session.persistIfNeeded() } }

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        // Üst bar
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GlassIconButton(Icons.Rounded.Close, stringResource(R.string.close), size = 38.dp, iconSize = 16.dp, onClick = onClose)
            AppIconTile(icon, color, 34.dp)
            Box(Modifier.weight(1f)) {
                if (name.isEmpty()) Text(stringResource(R.string.app_name_placeholder), style = PufyType.headline, color = c.tertiaryText)
                BasicTextField(name, { session.name.value = it }, singleLine = true, textStyle = PufyType.headline.copy(color = c.text),
                    cursorBrush = SolidColor(c.text), modifier = Modifier.fillMaxWidth())
            }
            if (versions.isNotEmpty()) Box {
                GlassIconButton(Icons.Outlined.History, stringResource(R.string.version_history), size = 38.dp, iconSize = 18.dp) { historyMenu = true }
                DropdownMenu(historyMenu, { historyMenu = false }) {
                    Text(stringResource(R.string.versions_restore_hint), style = PufyType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    val defaultChangeLabel = stringResource(R.string.version_change_default)
                    versions.take(15).forEach { v ->
                        DropdownMenuItem({ Text("${turkeyFormat(v.dateMillis, "d MMM HH:mm")} · ${v.label.ifEmpty { defaultChangeLabel }.take(36)}") },
                            onClick = { historyMenu = false; restoreTarget = v })
                    }
                }
            }
            if (session.appID != null) Text(stringResource(R.string.open_action), style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold), color = c.onPrimary,
                modifier = Modifier.clip(CircleShape).background(c.primary).pressable { session.persistIfNeeded(); Haptics.medium(view); onOpen(session.appID!!) }
                    .padding(horizontal = 16.dp, vertical = 9.dp))
        }

        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            if (messages.isEmpty() && !building) item("empty") { EmptyState { session.send("$it yap") } }
            val lastModel = messages.lastOrNull { !it.isUser }?.id
            items(messages, key = { it.id }) { m -> CreatorRow(m, !building && m.id == lastModel) }
            if (building) item("build") { BuildProgressCard(session) }
        }

        // Yazma alanı
        Row(Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 8.dp).fillMaxWidth().heightIn(min = 46.dp).pufyGlass(RoundedCornerShape(23.dp)),
            verticalAlignment = Alignment.Bottom) {
            Box(Modifier.weight(1f).padding(start = 16.dp, top = 12.dp, bottom = 12.dp)) {
                if (prompt.isEmpty()) Text(if (hasFiles) stringResource(R.string.creator_prompt_placeholder_edit) else stringResource(R.string.creator_prompt_placeholder_new), style = PufyType.body, color = c.secondaryText.copy(alpha = 0.75f))
                BasicTextField(prompt, { prompt = it }, Modifier.fillMaxWidth().focusRequester(focus), maxLines = 6, textStyle = PufyType.body.copy(color = c.text),
                    cursorBrush = SolidColor(c.text), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            }
            val can = !building && prompt.isNotBlank()
            Box(Modifier.padding(end = 6.dp, bottom = 6.dp).size(34.dp).clip(CircleShape).background(if (can || building) c.primary else c.disabled)
                .pressable(enabled = can || building) {
                    if (building) session.cancel() else { Haptics.medium(view); session.send(prompt); prompt = "" }
                }, contentAlignment = Alignment.Center) {
                Icon(if (building) Icons.Rounded.Stop else Icons.Rounded.ArrowUpward, if (building) stringResource(R.string.stop_action) else stringResource(R.string.send_action), Modifier.size(if (building) 15.dp else 19.dp),
                    tint = if (can || building) c.onPrimary else Color.White)
            }
        }
    }

    restoreTarget?.let { v ->
        AlertDialog({ restoreTarget = null }, title = { Text(stringResource(R.string.creator_restore_title)) }, text = { Text(stringResource(R.string.creator_restore_desc)) },
            confirmButton = { TextButton({ session.restore(v); restoreTarget = null; Haptics.success(view) }) { Text(stringResource(R.string.restore_action)) } },
            dismissButton = { TextButton({ restoreTarget = null }) { Text(stringResource(R.string.cancel)) } })
    }
}

@Composable
private fun EmptyState(onPick: (String) -> Unit) {
    val c = Pufy.colors
    Column(Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.creator_empty_title), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = c.text)
        Text(stringResource(R.string.creator_empty_desc),
            style = PufyType.subheadline, color = c.secondaryText)
        suggestions.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { (ic, stringResId) ->
                    val title = stringResource(stringResId)
                    Row(Modifier.weight(1f).heightIn(min = 56.dp).clip(RoundedCornerShape(16.dp)).background(c.soft).pressable(scale = 0.97f) { onPick(title) }
                        .padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(ic, null, Modifier.size(18.dp), tint = c.text)
                        Text(title, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text)
                    }
                }
            }
        }
    }
}

@Composable
private fun CreatorRow(m: Message, showAvatar: Boolean) {
    val c = Pufy.colors
    if (m.isUser) {
        Box(Modifier.fillMaxWidth().padding(start = 44.dp), contentAlignment = Alignment.CenterEnd) {
            Text(if (m.content.startsWith("Uygulamada şu hatalar oluştu") || m.content.startsWith("Uygulama çalışırken şu hatalar oluştu")) stringResource(R.string.fix_errors) else m.content,
                style = PufyType.body, color = c.text, modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(c.userBubble).padding(horizontal = 16.dp, vertical = 11.dp))
        }
    } else Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        AnimatedVisibility(showAvatar, enter = fadeIn(), exit = fadeOut()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Image(painterResource(R.drawable.chat_pp), null, Modifier.size(20.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                Text("Pufy", style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
            }
        }
        MarkdownView(m.content)
        val changed = m.thinkingSteps.filter { it.startsWith("✓ ") }
        if (changed.isNotEmpty()) Row(Modifier.clip(CircleShape).background(c.soft).padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Outlined.Description, null, Modifier.size(13.dp), tint = c.secondaryText)
            Text(if (changed.size == 1) changed[0].drop(2) else stringResource(R.string.files_updated, changed.size), style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
        }
    }
}

@Composable
private fun BuildProgressCard(session: CreatorSession) {
    val c = Pufy.colors
    val b = session.builder
    val status by b.status.collectAsState()
    val steps by b.steps.collectAsState()
    val files by b.files.collectAsState()
    val liveReply by b.liveReply.collectAsState()
    val reasoning by b.reasoning.collectAsState()
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.soft).padding(14.dp).animateContentSize(Springs.standard()),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PulsingPufy(Modifier.size(26.dp))
            val defaultThinking = stringResource(R.string.thinking)
            AnimatedContent(status.ifEmpty { defaultThinking }, label = "status", transitionSpec = { (fadeIn() + slideInVertically { it / 2 }) togetherWith fadeOut() }) {
                ShimmerText(it, PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        if (steps.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            steps.forEach { s ->
                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    Box(Modifier.width(16.dp).padding(top = 2.dp), contentAlignment = Alignment.Center) {
                        when (s.state) {
                            AgentStep.State.PENDING -> Icon(Icons.Rounded.RadioButtonUnchecked, null, Modifier.size(14.dp), tint = c.tertiaryText)
                            AgentStep.State.RUNNING -> CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp, color = c.secondaryText)
                            AgentStep.State.DONE -> Icon(Icons.Rounded.CheckCircle, null, Modifier.size(14.dp), tint = c.primary)
                            AgentStep.State.FAILED -> Icon(Icons.Rounded.Error, null, Modifier.size(14.dp), tint = Color(0xFFFF9500))
                        }
                    }
                    Column {
                        Text(s.title, style = PufyType.footnote.copy(fontWeight = if (s.state == AgentStep.State.RUNNING) FontWeight.SemiBold else FontWeight.Normal),
                            color = if (s.state == AgentStep.State.PENDING) c.secondaryText else c.text)
                        s.detail?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 11.sp, color = c.secondaryText, maxLines = 3) }
                    }
                }
            }
        }
        if (liveReply.isNotEmpty()) Text(liveReply, style = PufyType.subheadline, color = c.secondaryText, maxLines = 4)
        else if (files.isEmpty() && reasoning.isNotEmpty()) Text(reasoning.takeLast(240), style = PufyType.footnote, color = c.tertiaryText, maxLines = 3)
        if (files.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.background).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            files.forEach { f ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) {
                        when (f.state) {
                            FileProgress.State.WRITING -> CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp, color = c.secondaryText)
                            FileProgress.State.WRITTEN -> Icon(Icons.Rounded.CheckCircle, null, Modifier.size(15.dp), tint = c.text)
                            FileProgress.State.PATCHED -> Icon(Icons.Rounded.Edit, null, Modifier.size(15.dp), tint = c.text)
                            FileProgress.State.DELETED -> Icon(Icons.Rounded.Delete, null, Modifier.size(15.dp), tint = c.secondaryText)
                            FileProgress.State.FAILED -> Icon(Icons.Rounded.Error, null, Modifier.size(15.dp), tint = Color(0xFFFF3B30))
                        }
                    }
                    Text(f.path, fontFamily = FontFamily.Monospace, fontSize = 13.sp, color = c.text, modifier = Modifier.weight(1f), maxLines = 1)
                    if (f.added > 0 || f.state == FileProgress.State.WRITING) Text("+${f.added}", fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF21B354))
                    if (f.removed > 0) Text("−${f.removed}", fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFE64045))
                }
            }
        }
    }
}

