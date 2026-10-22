package com.pufy.app.ui.notes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.core.nowSwift
import com.pufy.app.data.MemoryStore
import com.pufy.app.data.NoteLine
import com.pufy.app.data.NoteStore
import com.pufy.app.ui.chat.MarkdownView
import com.pufy.app.ui.components.GlassIconButton
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.core.str

// iOS NoteDetailView karşılığı: okuma (dokunarak işaretlenen maddeler) ve düzenleme

@Composable
fun NoteScreen(noteID: String, onClose: () -> Unit) {
    val c = Pufy.colors
    val context = LocalContext.current
    val notes by NoteStore.notes.collectAsState()
    val note = notes.firstOrNull { it.id == noteID } ?: run { onClose(); return }
    var editing by remember { mutableStateOf(note.content.isEmpty()) }
    var title by remember(noteID) { mutableStateOf(note.title) }
    var body by remember(noteID) { mutableStateOf(note.content) }
    fun save() { if (title != note.title || body != note.content) NoteStore.upsert(note.copy(title = title.ifBlank { context.getString(R.string.untitled_note) }, content = body, updatedAt = nowSwift())) }

    Column(Modifier.fillMaxSize().background(c.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GlassIconButton(Icons.Rounded.Close, stringResource(R.string.close), size = 40.dp, iconSize = 18.dp) { save(); onClose() }
            Box(Modifier.weight(1f))
            GlassIconButton(Icons.Outlined.Share, stringResource(R.string.share), size = 40.dp, iconSize = 17.dp) {
                context.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(android.content.Intent.EXTRA_TEXT, "${note.title}\n\n${note.content}"), null))
            }
            GlassIconButton(Icons.Outlined.Delete, stringResource(R.string.delete), size = 40.dp, iconSize = 17.dp) { NoteStore.delete(note.id); onClose() }
            GlassIconButton(if (editing) Icons.Rounded.Check else Icons.Outlined.Edit, if (editing) stringResource(R.string.done_action) else stringResource(R.string.edit), size = 40.dp, iconSize = 18.dp) {
                if (editing) save(); editing = !editing
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (editing) {
                BasicTextField(title, { title = it }, textStyle = PufyType.largeTitle.copy(color = c.text, fontSize = 26.sp), cursorBrush = SolidColor(c.text), modifier = Modifier.fillMaxWidth())
                BasicTextField(body, { body = it }, textStyle = PufyType.body.copy(color = c.text), cursorBrush = SolidColor(c.text),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 300.dp), decorationBox = { inner ->
                        if (body.isEmpty()) Text(stringResource(R.string.note_placeholder), style = PufyType.body, color = c.tertiaryText); inner()
                    })
            } else {
                Text(note.title, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = c.text)
                note.checklistProgress?.let { (done, total) -> Text(stringResource(R.string.checklist_completed_count, done, total), style = PufyType.footnote, color = c.secondaryText) }
                val lines = note.content.lines()
                var buffer = mutableListOf<String>()
                @Composable fun flush() { if (buffer.isNotEmpty()) { MarkdownView(buffer.joinToString("\n")); buffer = mutableListOf() } }
                lines.forEachIndexed { i, raw ->
                    val item = NoteLine.checkItem(raw.trim())
                    if (item == null) buffer.add(raw) else {
                        flush()
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).pressable(scale = 0.98f) { NoteStore.toggle(note.id, i) }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(if (item.first) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, Modifier.size(22.dp),
                                tint = if (item.first) c.primary else c.tertiaryText)
                            Text(item.second, style = PufyType.body.copy(textDecoration = if (item.first) TextDecoration.LineThrough else null),
                                color = if (item.first) c.secondaryText else c.text)
                        }
                    }
                }
                flush()
            }
        }
    }
}

