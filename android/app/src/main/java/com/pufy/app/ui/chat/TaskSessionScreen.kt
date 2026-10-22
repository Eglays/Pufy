package com.pufy.app.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.StopCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.ai.ChatEngine
import com.pufy.app.core.swiftToEpochMillis
import com.pufy.app.data.ChatSession
import com.pufy.app.data.Message
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.ui.components.Haptics
import com.pufy.app.ui.components.ShimmerText
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.components.pufyGlass
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.sin

// iOS TaskSessionView.swift karşılığı: zamanlanmış görev sohbeti özel görünümü

@Composable
fun TaskSessionScreen(
    session: ChatSession,
    headerHeight: Dp,
    modifier: Modifier = Modifier,
    onOpenMenu: () -> Unit = {},
) {
    val c = Pufy.colors
    val reminders by ReminderStore.reminders.collectAsState()
    val task = reminders.firstOrNull { it.taskSessionID == session.id }
    val request = remember(session.messages) { session.messages.firstOrNull { it.isUser } }
    val generatingID by ChatEngine.generatingMessageID.collectAsState()

    // Sonuç mesajları (model rolü ve boş olmayanlar)
    val results = remember(session.messages, generatingID) {
        session.messages.filter { !it.isUser && (it.content.isNotEmpty() || it.id == generatingID) }
    }

    val isRunning = generatingID != null && session.messages.any { it.id == generatingID }

    val listState = rememberLazyListState()

    // Yeni sonuç gelince en alta kaydır
    LaunchedEffect(results.size, isRunning) {
        if (results.isNotEmpty() || isRunning) {
            val target = (results.size - 1).coerceAtLeast(0)
            listState.animateScrollToItem(target)
        }
    }

    val context = androidx.compose.ui.platform.LocalContext.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(top = headerHeight)
    ) {
        // Sabit görev balonu
        TaskHeaderCard(
            title = task?.title?.ifEmpty { session.title } ?: session.title,
            prompt = request?.content ?: task?.aiTaskPrompt.orEmpty(),
            kind = kindLabel(context, task),
            schedule = scheduleText(context, task),
            isRepeating = task?.isRepeatingTask == true,
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .padding(top = 6.dp, bottom = 10.dp)
        )

        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
            modifier = Modifier.weight(1f)
        ) {
            items(results, key = { it.id }) { message ->
                Column(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().animateContentSize(Springs.standard())
                ) {
                    ResultStamp(dateMillis = swiftToEpochMillis(message.timestamp))
                    SelectionContainer {
                        MarkdownView(message.content)
                    }
                }
            }

            if (isRunning) {
                item(key = "task_running") {
                    TaskRunningView()
                }
            } else if (task != null) {
                item(key = "task_footer") {
                    StatusFooter(
                        task = task,
                        hasResults = results.isNotEmpty(),
                        onRunNow = {
                            ChatEngine.runTaskNow(task.id)
                        },
                        onStop = {
                            ReminderStore.upsert(task.copy(isActive = false, taskDone = true))
                        },
                        onDelete = {
                            ReminderStore.delete(task.id)
                        }
                    )
                }
            }

            item(key = "spacer_bottom") {
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

// MARK: - Görev balonu

@Composable
private fun TaskHeaderCard(
    title: String,
    prompt: String,
    kind: String,
    schedule: String,
    isRepeating: Boolean,
    modifier: Modifier = Modifier,
) {
    val c = Pufy.colors
    var expanded by remember { mutableStateOf(false) }

    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(c.userBubble)
            .border(0.5.dp, c.text.copy(alpha = 0.06f), RoundedCornerShape(22.dp))
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(
                imageVector = if (isRepeating) Icons.Rounded.Repeat else Icons.Rounded.Schedule,
                contentDescription = null,
                tint = c.secondaryText,
                modifier = Modifier.size(13.dp)
            )
            Text(
                text = kind,
                style = PufyType.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                color = c.secondaryText
            )
            Spacer(Modifier.weight(1f))
            if (schedule.isNotEmpty()) {
                Text(
                    text = schedule,
                    style = PufyType.caption.copy(fontWeight = FontWeight.Medium),
                    color = c.secondaryText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        Text(
            text = title,
            style = PufyType.headline.copy(fontWeight = FontWeight.Bold),
            color = c.text,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )

        if (prompt.isNotEmpty() && prompt != title) {
            Text(
                text = prompt,
                style = PufyType.subheadline,
                color = c.secondaryText,
                maxLines = if (expanded) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .animateContentSize(Springs.standard())
            )
        }
    }
}

// MARK: - Damga (her sonucun üstünde logo + saat)

@Composable
private fun ResultStamp(dateMillis: Long) {
    val c = Pufy.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Image(
            painter = painterResource(R.drawable.chat_pp),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(18.dp).clip(CircleShape)
        )
        Text(
            text = "Pufy · ${dayTime(context, dateMillis)}",
            style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold),
            color = c.secondaryText
        )
    }
}

// MARK: - Alt durum

@Composable
private fun StatusFooter(
    task: Reminder,
    hasResults: Boolean,
    onRunNow: () -> Unit,
    onStop: () -> Unit,
    onDelete: () -> Unit,
) {
    val c = Pufy.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    val view = LocalView.current
    val isDone = task.taskDone == true || !task.isActive

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = if (hasResults) 4.dp else 24.dp)
    ) {
        if (isDone) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = if (task.isActive) Icons.Rounded.CheckCircle else Icons.Rounded.StopCircle,
                    contentDescription = null,
                    tint = c.secondaryText,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = if (task.isActive) stringResource(R.string.task_completed) else stringResource(R.string.task_stopped),
                    style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold),
                    color = c.secondaryText
                )
            }
            FooterButton(
                title = stringResource(R.string.task_delete),
                icon = Icons.Rounded.DeleteOutline,
                prominent = false,
                onClick = {
                    Haptics.light(view)
                    onDelete()
                }
            )
        } else {
            val nextMillis = nextDueMillis(task)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                val nextText = if (hasResults) {
                    context.getString(R.string.task_next_at, formatTime(nextMillis))
                } else {
                    context.getString(R.string.task_runs_at, dayTime(context, nextMillis))
                }
                Text(
                    text = nextText,
                    style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold),
                    color = c.text
                )
                if (nextMillis > System.currentTimeMillis()) {
                    Text(
                        text = relativeTime(context, nextMillis),
                        style = PufyType.caption,
                        color = c.secondaryText
                    )
                }
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FooterButton(
                    title = stringResource(R.string.task_run_now),
                    icon = Icons.Rounded.Bolt,
                    prominent = true,
                    onClick = {
                        Haptics.medium(view)
                        onRunNow()
                    }
                )
                if (task.isRepeatingTask) {
                    FooterButton(
                        title = stringResource(R.string.task_stop),
                        icon = Icons.Rounded.Stop,
                        prominent = false,
                        onClick = {
                            Haptics.light(view)
                            onStop()
                        }
                    )
                }
                FooterButton(
                    title = stringResource(R.string.delete),
                    icon = Icons.Rounded.DeleteOutline,
                    prominent = false,
                    onClick = {
                        Haptics.light(view)
                        onDelete()
                    }
                )
            }

            if (task.taskIntervalMinutes != null) {
                Text(
                    text = stringResource(R.string.task_bg_notice),
                    style = PufyType.caption.copy(fontSize = 11.sp),
                    color = c.tertiaryText
                )
            }
        }
    }
}

@Composable
private fun FooterButton(
    title: String,
    icon: ImageVector,
    prominent: Boolean,
    onClick: () -> Unit,
) {
    val c = Pufy.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            // Vurgulu buton düz dolgu: cam efektinin rengi bazı cihazlarda çizilmeyip yazı görünmez kalıyordu
            .let { if (prominent) it.clip(CircleShape).background(c.primary) else it.pufyGlass(CircleShape) }
            .pressable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (prominent) c.onPrimary else c.text,
            modifier = Modifier.size(15.dp)
        )
        Text(
            text = title,
            style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold),
            color = if (prominent) c.onPrimary else c.text
        )
    }
}

// MARK: - Çalışıyor animasyonu

@Composable
fun TaskRunningView(modifier: Modifier = Modifier) {
    val c = Pufy.colors
    val phrases = listOf(
        stringResource(R.string.task_phrase_running),
        stringResource(R.string.task_phrase_web),
        stringResource(R.string.task_phrase_comparing),
        stringResource(R.string.task_phrase_writing)
    )
    var elapsedSeconds by remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) {
        val start = System.currentTimeMillis()
        while (true) {
            delay(1000)
            elapsedSeconds = (System.currentTimeMillis() - start) / 1000
        }
    }

    val phraseIndex = (elapsedSeconds / 4).toInt().coerceAtMost(phrases.size - 1)

    val infinite = rememberInfiniteTransition(label = "task_running")
    val pulse by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart),
        label = "pulse"
    )
    val orbit by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(2600, easing = LinearEasing), RepeatMode.Restart),
        label = "orbit"
    )

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(c.secondaryBackground)
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Box(
            modifier = Modifier.size(76.dp),
            contentAlignment = Alignment.Center
        ) {
            for (i in 0..2) {
                val p = ((pulse + i / 3f) % 1f)
                val size = 36.dp + (36.dp * p)
                Box(
                    modifier = Modifier
                        .size(size)
                        .border(1.2.dp, c.text.copy(alpha = 0.28f * (1f - p)), CircleShape)
                )
            }

            Box(
                modifier = Modifier
                    .size(70.dp)
                    .rotate(orbit)
            ) {
                Box(
                    modifier = Modifier
                        .size(5.dp)
                        .clip(CircleShape)
                        .background(c.text)
                        .align(Alignment.CenterEnd)
                )
            }

            val scale = 1f + 0.05f * sin((elapsedSeconds * 3).toDouble()).toFloat()
            Image(
                painter = painterResource(R.drawable.chat_pp),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(36.dp)
                    .scale(scale)
                    .clip(CircleShape)
            )
        }

        Column(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.weight(1f)
        ) {
            ShimmerText(
                text = phrases[phraseIndex],
                style = PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold)
            )
            val isEn = com.pufy.app.core.AppLocales.isEnglish()
            val elapsedText = if (elapsedSeconds < 60) {
                if (isEn) "${elapsedSeconds}s" else "${elapsedSeconds} sn"
            } else {
                String.format(Locale.getDefault(), "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
            }
            Text(
                text = elapsedText,
                style = PufyType.caption,
                color = c.secondaryText
            )
        }
    }
}

// MARK: - Metin ve zaman yardımcıları

private fun kindLabel(context: android.content.Context, task: Reminder?): String {
    if (task == null) return context.getString(R.string.task_label)
    return if (task.isRepeatingTask) context.getString(R.string.task_label_recurring) else context.getString(R.string.task_label_scheduled)
}

private fun scheduleText(context: android.content.Context, task: Reminder?): String {
    if (task == null) return ""
    task.taskIntervalMinutes?.let { every ->
        val interval = if (every % 60 == 0) {
            context.getString(R.string.task_every_hours, every / 60)
        } else {
            context.getString(R.string.task_every_minutes, every)
        }
        val until = task.taskUntilMillis?.let {
            context.getString(R.string.task_until, formatTime(it))
        }.orEmpty()
        return interval + until
    }
    return when (task.repeat) {
        "daily" -> context.getString(R.string.task_daily_at, formatTime(task.dateMillis))
        "weekly" -> context.getString(R.string.task_weekly_at, formatWeekday(task.dateMillis), formatTime(task.dateMillis))
        "monthly" -> context.getString(R.string.task_monthly_at, formatDayOfMonth(task.dateMillis))
        "yearly" -> context.getString(R.string.task_yearly_at, dayTime(context, task.dateMillis))
        else -> dayTime(context, task.dateMillis)
    }
}

private fun nextDueMillis(task: Reminder): Long {
    val now = System.currentTimeMillis()
    if (task.dateMillis > now) return task.dateMillis
    task.taskIntervalMinutes?.let { every ->
        val intervalMillis = every * 60_000L
        val diff = now - task.dateMillis
        val steps = (diff / intervalMillis) + 1
        val next = task.dateMillis + (steps * intervalMillis)
        if (task.taskUntilMillis != null && next > task.taskUntilMillis) return task.dateMillis
        return next
    }
    return task.dateMillis
}

private fun formatTime(millis: Long): String {
    val locale = if (com.pufy.app.core.AppLocales.isEnglish()) Locale.US else Locale("tr", "TR")
    val sdf = SimpleDateFormat("HH:mm", locale)
    return sdf.format(Date(millis))
}

private fun formatWeekday(millis: Long): String {
    val locale = if (com.pufy.app.core.AppLocales.isEnglish()) Locale.US else Locale("tr", "TR")
    val sdf = SimpleDateFormat("EEEE", locale)
    return sdf.format(Date(millis))
}

private fun formatDayOfMonth(millis: Long): String {
    val cal = Calendar.getInstance().apply { timeInMillis = millis }
    return cal.get(Calendar.DAY_OF_MONTH).toString()
}

fun dayTime(context: android.content.Context, millis: Long): String {
    val cal = Calendar.getInstance().apply { timeInMillis = millis }
    val now = Calendar.getInstance()
    val time = formatTime(millis)

    val isToday = cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            cal.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
    if (isToday) return context.getString(R.string.time_today, time)

    now.add(Calendar.DAY_OF_YEAR, 1)
    val isTomorrow = cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            cal.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
    if (isTomorrow) return context.getString(R.string.time_tomorrow, time)

    now.add(Calendar.DAY_OF_YEAR, -2)
    val isYesterday = cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            cal.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
    if (isYesterday) return context.getString(R.string.time_yesterday, time)

    val locale = if (com.pufy.app.core.AppLocales.isEnglish()) Locale.US else Locale("tr", "TR")
    val sdf = SimpleDateFormat("d MMM HH:mm", locale)
    return sdf.format(Date(millis))
}

private fun relativeTime(context: android.content.Context, targetMillis: Long): String {
    val diffSec = ((targetMillis - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
    if (diffSec < 60) return context.getString(R.string.time_sec_later, diffSec)
    val diffMin = diffSec / 60
    if (diffMin < 60) return context.getString(R.string.time_min_later, diffMin)
    val diffHours = diffMin / 60
    val remMin = diffMin % 60
    return if (remMin == 0L) {
        context.getString(R.string.time_hours_later, diffHours)
    } else {
        context.getString(R.string.time_hours_min_later, diffHours, remMin)
    }
}
