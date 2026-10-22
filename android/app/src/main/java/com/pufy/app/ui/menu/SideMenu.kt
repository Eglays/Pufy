package com.pufy.app.ui.menu

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.ChatEngine
import com.pufy.app.core.AppLocales
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.ChatSession
import com.pufy.app.data.ChatStore
import com.pufy.app.data.Note
import com.pufy.app.data.NoteStore
import com.pufy.app.data.Profile
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs

// iOS SideMenuView karşılığı: arama, hatırlatıcılar, notlar, görevler, sabitlenenler, sohbetler, profil

private const val REMINDER_LIMIT = 3
private const val NOTE_LIMIT = 4
private const val SESSION_LIMIT = 7

@Composable
fun SideMenu(onClose: () -> Unit, modifier: Modifier = Modifier) {
    val c = Pufy.colors
    val sessions by ChatStore.sessions.collectAsState()
    val currentID by ChatEngine.currentSessionID.collectAsState()
    val generatingID by ChatEngine.generatingMessageID.collectAsState()
    val reminders by ReminderStore.reminders.collectAsState()
    val notes by NoteStore.notes.collectAsState()
    var query by remember { mutableStateOf("") }
    var searching by remember { mutableStateOf(false) }
    var showAllReminders by remember { mutableStateOf(false) }
    var showAllNotes by remember { mutableStateOf(false) }
    var showAllSessions by remember { mutableStateOf(false) }
    var showAllTasks by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<ChatSession?>(null) }

    val q = query.trim()
    val filtered = remember(sessions, q) {
        val list = sessions.filter { it.messages.isNotEmpty() || it.isSpaceChat }
        if (q.isEmpty()) list else list.filter { s ->
            s.title.contains(q, ignoreCase = true) || s.messages.any { it.content.contains(q, ignoreCase = true) }
        }
    }
    val generatingSession = generatingID?.let { id -> sessions.firstOrNull { s -> s.messages.any { it.id == id } }?.id }
    fun select(s: ChatSession) { ChatEngine.open(s.id); onClose() }

    Column(modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding().padding(top = 8.dp)) {
        Box(Modifier.height(44.dp).padding(horizontal = 20.dp).fillMaxWidth()) {
            AnimatedContent(searching, label = "search", transitionSpec = {
                (fadeIn() + slideInHorizontally { if (targetState) it / 3 else 0 }) togetherWith fadeOut()
            }) { isSearching ->
                if (isSearching) SearchField(query, { query = it }) { query = ""; searching = false }
                else Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Pufy", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = c.text, letterSpacing = (-0.4).sp)
                    Spacer(Modifier.weight(1f))
                    GlassIconButton(Icons.Outlined.Search, stringResource(R.string.search_chats), size = 40.dp, iconSize = 17.dp) { searching = true }
                }
            }
        }
        Spacer(Modifier.height(10.dp))

        LazyColumn(Modifier.weight(1f), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp)) {
            if (q.isEmpty()) {
                item("reminders") {
                    Section(stringResource(R.string.reminders)) {
                        val upcoming = reminders.filter { !it.isExpired() && !it.isTimer }.sortedBy { it.dateMillis }
                        if (upcoming.isEmpty()) Hint(stringResource(R.string.reminder_hint))
                        else {
                            (if (showAllReminders) upcoming else upcoming.take(REMINDER_LIMIT)).forEach { ReminderRow(it) }
                            if (upcoming.size > REMINDER_LIMIT) ShowAll(showAllReminders, upcoming.size - REMINDER_LIMIT) { showAllReminders = !showAllReminders }
                        }
                    }
                }
                item("d1") { Divider() }
                item("notes") {
                    Section(stringResource(R.string.notes), action = {
                        Box(Modifier.padding(end = 14.dp).size(30.dp).pressable {
                            val note = Note(title = "Yeni not", content = "")
                            NoteStore.upsert(note); AppNav.openNoteID.value = note.id
                        }, contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Add, stringResource(R.string.new_note), Modifier.size(16.dp), tint = c.secondaryText) }
                    }) {
                        val sorted = notes.sortedByDescending { it.updatedAt }
                        if (sorted.isEmpty()) Hint(stringResource(R.string.note_hint))
                        else {
                            (if (showAllNotes) sorted else sorted.take(NOTE_LIMIT)).forEach { NoteRow(it) }
                            if (sorted.size > NOTE_LIMIT) ShowAll(showAllNotes, sorted.size - NOTE_LIMIT) { showAllNotes = !showAllNotes }
                        }
                    }
                }
                item("d2") { Divider() }
            }
            val tasks = filtered.filter { it.isSpaceChat }
            if (tasks.isNotEmpty()) {
                item("tasks") {
                    Section(stringResource(R.string.tasks)) {
                        (if (showAllTasks || q.isNotEmpty()) tasks else tasks.take(REMINDER_LIMIT)).forEach { s ->
                            SessionRow(s, Icons.Rounded.AutoAwesome, s.id == currentID, s.id == generatingSession, { select(s) }, { renaming = s })
                        }
                        if (tasks.size > REMINDER_LIMIT && q.isEmpty()) ShowAll(showAllTasks, tasks.size - REMINDER_LIMIT) { showAllTasks = !showAllTasks }
                    }
                }
                item("d3") { Divider() }
            }
            val pinned = filtered.filter { it.isPinned && !it.isSpaceChat }
            if (pinned.isNotEmpty()) item("pinned") {
                Section(stringResource(R.string.pinned)) {
                    pinned.forEach { s -> SessionRow(s, Icons.Rounded.PushPin, s.id == currentID, s.id == generatingSession, { select(s) }, { renaming = s }) }
                }
            }
            val recent = filtered.filter { !it.isPinned && !it.isSpaceChat }
            item("recent") {
                Section(if (q.isEmpty()) stringResource(R.string.chats) else stringResource(R.string.results)) {
                    if (recent.isEmpty() && pinned.isEmpty() && tasks.isEmpty()) {
                        Column(Modifier.fillMaxWidth().padding(top = 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(if (q.isEmpty()) Icons.Outlined.ChatBubbleOutline else Icons.Outlined.Search, null, Modifier.size(34.dp), tint = c.tertiaryText)
                            Text(if (q.isEmpty()) stringResource(R.string.no_chats_yet) else stringResource(R.string.no_results), style = PufyType.subheadline, color = c.secondaryText)
                        }
                    } else {
                        (if (showAllSessions || q.isNotEmpty()) recent else recent.take(SESSION_LIMIT)).forEach { s ->
                            SessionRow(s, null, s.id == currentID, s.id == generatingSession, { select(s) }, { renaming = s })
                        }
                        if (recent.size > SESSION_LIMIT && q.isEmpty()) ShowAll(showAllSessions, recent.size - SESSION_LIMIT) { showAllSessions = !showAllSessions }
                    }
                }
            }
        }
        Footer()
    }

    renaming?.let { target -> RenameDialog(target) { renaming = null } }
}

@Composable
private fun SearchField(query: String, onChange: (String) -> Unit, onCancel: () -> Unit) {
    val c = Pufy.colors
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(250); runCatching { focus.requestFocus() } }
    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.weight(1f).height(42.dp).pufyGlass(CircleShape).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Outlined.Search, null, Modifier.size(17.dp), tint = c.secondaryText)
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text(stringResource(R.string.search_chats), style = PufyType.body, color = c.secondaryText)
                BasicTextField(query, onChange, Modifier.fillMaxWidth().focusRequester(focus), singleLine = true,
                    textStyle = PufyType.body.copy(color = c.text), cursorBrush = SolidColor(c.text))
            }
            if (query.isNotEmpty()) Icon(Icons.Rounded.Cancel, stringResource(R.string.clear_search), Modifier.size(18.dp).pressable { onChange("") }, tint = c.tertiaryText)
        }
        Text(stringResource(R.string.cancel), style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text, modifier = Modifier.pressable(onClick = onCancel))
    }
}

@Composable
private fun Section(title: String, action: (@Composable () -> Unit)? = null, content: @Composable () -> Unit) {
    val c = Pufy.colors
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp).animateContentSize(Springs.standard()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold), color = c.text,
                modifier = Modifier.padding(horizontal = 20.dp).padding(bottom = 4.dp).weight(1f))
            action?.invoke()
        }
        content()
    }
}

@Composable private fun Divider() = HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = Pufy.colors.separator)

@Composable
private fun Hint(text: String) = Text(text, style = PufyType.caption, color = Pufy.colors.secondaryText, modifier = Modifier.padding(horizontal = 20.dp))

@Composable
private fun ShowAll(expanded: Boolean, hidden: Int, onClick: () -> Unit) {
    val c = Pufy.colors
    Row(Modifier.pressable(onClick = onClick).padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(if (expanded) stringResource(R.string.show_less) else stringResource(R.string.show_all, hidden), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
        Icon(if (expanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, null, Modifier.size(14.dp), tint = c.secondaryText)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ReminderRow(r: Reminder) {
    val c = Pufy.colors
    var menu by remember { mutableStateOf(false) }
    val repeatName = mapOf("daily" to stringResource(R.string.repeat_daily), "weekly" to stringResource(R.string.repeat_weekly),
        "monthly" to stringResource(R.string.repeat_monthly), "yearly" to stringResource(R.string.repeat_yearly),
        "weekdays" to stringResource(R.string.repeat_weekdays))[r.repeat]
    val taskBadge = stringResource(R.string.task_badge)
    Box(Modifier.padding(horizontal = 12.dp, vertical = 3.dp)) {
        Column(Modifier.fillMaxWidth().pufyGlass(RoundedCornerShape(16.dp), shadow = false)
            .combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = { menu = true }) { AppNav.editingReminder.value = r }
            .padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(r.title, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
            Text(buildString {
                append(AppLocales.uiFormat(r.dateMillis, "d MMM yyyy HH:mm"))
                repeatName?.let { append(" · $it") }
                if (r.isAITask) append(" · $taskBadge")
            }, fontSize = 11.sp, color = c.secondaryText)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text(stringResource(R.string.edit)) }, onClick = { menu = false; AppNav.editingReminder.value = r }, leadingIcon = { Icon(Icons.Outlined.Edit, null) })
            DropdownMenuItem({ Text(stringResource(R.string.delete)) }, onClick = { menu = false; ReminderStore.delete(r.id) },
                leadingIcon = { Icon(Icons.Outlined.Delete, null) })
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NoteRow(note: Note) {
    val c = Pufy.colors
    var menu by remember { mutableStateOf(false) }
    val preview = note.content.lines().map { it.trim() }.firstOrNull { it.isNotEmpty() }
        ?.let { com.pufy.app.data.NoteLine.checkItem(it)?.second ?: it.removePrefix("- ") }
    Box(Modifier.padding(horizontal = 8.dp)) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .combinedClickable(onLongClick = { menu = true }) { AppNav.openNoteID.value = note.id }
            .padding(horizontal = 12.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(note.title.ifBlank { stringResource(R.string.untitled_note) }, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
            preview?.let { Text(it, style = PufyType.caption, color = c.secondaryText, maxLines = 1) }
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text(stringResource(R.string.delete)) }, onClick = { menu = false; NoteStore.delete(note.id) }, leadingIcon = { Icon(Icons.Outlined.Delete, null) })
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SessionRow(s: ChatSession, icon: ImageVector?, isCurrent: Boolean, isGenerating: Boolean, onClick: () -> Unit, onRename: () -> Unit) {
    val c = Pufy.colors
    val view = LocalView.current
    var menu by remember { mutableStateOf(false) }
    val bg by animateColorAsState(if (isCurrent) c.soft else Color.Transparent, Springs.quick(), label = "bg")
    Box(Modifier.padding(horizontal = 8.dp)) {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(bg)
            .combinedClickable(onLongClick = { Haptics.medium(view); menu = true }, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            icon?.let { Icon(it, null, Modifier.size(13.dp), tint = c.primary) }
            Text(s.title, style = PufyType.subheadline.copy(fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal),
                color = c.text, maxLines = 1, modifier = Modifier.weight(1f))
            if (isGenerating) CircularProgressIndicator(Modifier.size(12.dp), color = c.secondaryText, strokeWidth = 1.5.dp)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text(stringResource(R.string.rename)) }, onClick = { menu = false; onRename() }, leadingIcon = { Icon(Icons.Outlined.Edit, null) })
            if (!s.isSpaceChat) DropdownMenuItem({ Text(if (s.isPinned) stringResource(R.string.unpin) else stringResource(R.string.pin)) },
                onClick = { menu = false; ChatStore.mutate(s.id) { it.copy(isPinned = !it.isPinned) } }, leadingIcon = { Icon(Icons.Outlined.PushPin, null) })
            DropdownMenuItem({ Text(stringResource(R.string.delete), color = Color(0xFFFF3B30)) }, onClick = {
                menu = false
                if (ChatEngine.currentSessionID.value == s.id) ChatEngine.newSession()
                ChatStore.delete(s.id)
            }, leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = Color(0xFFFF3B30)) })
        }
    }
}

@Composable
private fun RenameDialog(session: ChatSession, onDone: () -> Unit) {
    var title by remember { mutableStateOf(session.title) }
    AlertDialog(onDismissRequest = onDone, title = { Text(stringResource(R.string.rename)) },
        text = { OutlinedTextField(title, { title = it }, singleLine = true, label = { Text(stringResource(R.string.new_title)) }) },
        confirmButton = { TextButton({ title.trim().takeIf { it.isNotEmpty() }?.let { t -> ChatStore.mutate(session.id) { it.copy(title = t) } }; onDone() }) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(onDone) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun Footer() {
    val c = Pufy.colors
    val name by Profile.nameFlow.collectAsState()
    val avatarVersion by Profile.avatarVersion.collectAsState()
    val avatar = remember(avatarVersion) {
        Profile.avatarBytes()?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
    }
    Row(Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp).fillMaxWidth().pufyGlass(RoundedCornerShape(22.dp))
        .padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).clip(CircleShape).border(1.5.dp, c.primary.copy(alpha = 0.35f), CircleShape)
            .pressable { AppNav.memoryBookVisible.value = true }, contentAlignment = Alignment.Center) {
            if (avatar != null) Image(avatar, stringResource(R.string.personal_map), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else Icon(Icons.Rounded.AccountCircle, stringResource(R.string.personal_map), Modifier.fillMaxSize(), tint = c.primary.copy(alpha = 0.7f))
        }
        Row(Modifier.weight(1f).pressable(scale = 0.98f) { AppNav.settingsVisible.value = true }, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(name.ifEmpty { stringResource(R.string.profile) }, style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                Text(AiClient.modelName.ifEmpty { stringResource(R.string.no_model_selected) }, style = PufyType.caption, color = c.secondaryText, maxLines = 1)
            }
            Icon(Icons.Outlined.Settings, stringResource(R.string.settings_title), Modifier.size(19.dp), tint = c.secondaryText)
        }
    }
}

