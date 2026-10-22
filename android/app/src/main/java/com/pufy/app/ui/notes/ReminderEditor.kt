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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.core.AppLocales
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.settings.Group
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import java.util.Calendar
import java.util.TimeZone

// iOS ReminderEditorSheet karşılığı: başlık, tarih-saat, tekrar, not

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReminderEditor(reminder: Reminder, onClose: () -> Unit) {
    val context = LocalContext.current
    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { _ -> }
    val c = Pufy.colors
    val isNew = reminder.title.isEmpty()
    var title by remember { mutableStateOf(reminder.title) }
    var note by remember { mutableStateOf(reminder.note) }
    var repeat by remember { mutableStateOf(reminder.repeat) }
    var date by remember { mutableLongStateOf(reminder.dateMillis.takeIf { it > 0 } ?: (System.currentTimeMillis() + 3600_000)) }
    var pickDate by remember { mutableStateOf(false) }
    var pickTime by remember { mutableStateOf(false) }
    val canSave = title.isNotBlank()

    val repeats = listOf(
        "none" to stringResource(R.string.repeat_none),
        "daily" to stringResource(R.string.repeat_daily),
        "weekly" to stringResource(R.string.repeat_weekly),
        "monthly" to stringResource(R.string.repeat_monthly),
        "yearly" to stringResource(R.string.repeat_yearly)
    )

    fun onSave() {
        if (!canSave) return
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        ReminderStore.upsert(reminder.copy(title = title.trim(), note = note, repeat = repeat, dateMillis = date, isActive = true))
        onClose()
    }

    Column(Modifier.fillMaxSize().background(c.groupedBackground).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClose) { Text(stringResource(R.string.cancel), color = c.text) }
            Text(if (isNew) stringResource(R.string.new_reminder) else stringResource(R.string.edit), style = PufyType.headline, color = c.text, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextButton({ onSave() }, enabled = canSave) {
                Text(stringResource(R.string.save), fontWeight = FontWeight.SemiBold, color = if (canSave) c.text else c.tertiaryText)
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Group(stringResource(R.string.title_label)) {
                Box(Modifier.fillMaxWidth().padding(16.dp)) {
                    if (title.isEmpty()) Text(stringResource(R.string.reminder_title), style = PufyType.body, color = c.tertiaryText)
                    BasicTextField(title, { title = it }, singleLine = true, textStyle = PufyType.body.copy(color = c.text), cursorBrush = SolidColor(c.text), modifier = Modifier.fillMaxWidth())
                }
            }
            Group(stringResource(R.string.date_time)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.date), style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                    Chip(AppLocales.uiFormat(date, "d MMM yyyy")) { pickDate = true }
                    Box(Modifier.size(8.dp))
                    Chip(AppLocales.uiFormat(date, "HH:mm")) { pickTime = true }
                }
            }
            Group(stringResource(R.string.repeat)) {
                repeats.forEachIndexed { i, (key, label) ->
                    Row(Modifier.fillMaxWidth().pressable(scale = 0.99f) { repeat = key }.padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(label, style = PufyType.body, color = c.text, modifier = Modifier.weight(1f))
                        if (repeat == key) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = c.text)
                    }
                    if (i < repeats.size - 1) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator.copy(alpha = 0.5f))
                }
            }
            Group(stringResource(R.string.note)) {
                Box(Modifier.fillMaxWidth().heightIn(min = 90.dp).padding(16.dp)) {
                    if (note.isEmpty()) Text(stringResource(R.string.add_note), style = PufyType.body, color = c.tertiaryText)
                    BasicTextField(note, { note = it }, textStyle = PufyType.body.copy(color = c.text), cursorBrush = SolidColor(c.text), modifier = Modifier.fillMaxWidth())
                }
            }
            if (!isNew) Text(stringResource(R.string.delete_reminder), style = PufyType.body.copy(fontWeight = FontWeight.Medium), color = Color(0xFFFF3B30),
                modifier = Modifier.align(Alignment.CenterHorizontally).pressable { ReminderStore.delete(reminder.id); onClose() }.padding(12.dp))
        }
    }

    if (pickDate) {
        val state = rememberDatePickerState(initialSelectedDateMillis = date + TimeZone.getDefault().getOffset(date))
        DatePickerDialog(onDismissRequest = { pickDate = false }, confirmButton = {
            TextButton({
                state.selectedDateMillis?.let { utc ->
                    val picked = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = utc }
                    date = Calendar.getInstance().apply {
                        timeInMillis = date
                        set(picked.get(Calendar.YEAR), picked.get(Calendar.MONTH), picked.get(Calendar.DAY_OF_MONTH))
                    }.timeInMillis
                }
                pickDate = false
            }) { Text(stringResource(R.string.ok)) }
        }, dismissButton = { TextButton({ pickDate = false }) { Text(stringResource(R.string.cancel)) } }) { DatePicker(state) }
    }
    if (pickTime) {
        val cal = Calendar.getInstance().apply { timeInMillis = date }
        val state = rememberTimePickerState(cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE), is24Hour = true)
        androidx.compose.material3.AlertDialog({ pickTime = false }, confirmButton = {
            TextButton({ date = Calendar.getInstance().apply { timeInMillis = date; set(Calendar.HOUR_OF_DAY, state.hour); set(Calendar.MINUTE, state.minute); set(Calendar.SECOND, 0) }.timeInMillis; pickTime = false }) { Text(stringResource(R.string.ok)) }
        }, dismissButton = { TextButton({ pickTime = false }) { Text(stringResource(R.string.cancel)) } }, text = { TimePicker(state) })
    }
}

@Composable
private fun Chip(text: String, onClick: () -> Unit) {
    val c = Pufy.colors
    Text(text, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = c.text,
        modifier = Modifier.clip(CircleShape).background(c.soft).pressable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp))
}
