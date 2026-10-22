package com.pufy.app.ui.chat

import androidx.compose.material.icons.outlined.AddBox
import androidx.compose.foundation.border
import android.content.ClipData
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.clickable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.StickyNote2
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Share
import androidx.compose.runtime.collectAsState
import com.pufy.app.core.AIReportStore
import com.pufy.app.core.AppLocales
import com.pufy.app.core.ReportDialog
import androidx.compose.material.icons.rounded.ArrowOutward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.pufy.app.R
import com.pufy.app.ai.AiClient
import com.pufy.app.ai.ResearchEngine
import com.pufy.app.ai.Tags
import com.pufy.app.data.AppFiles
import com.pufy.app.data.Message
import com.pufy.app.data.WebSource
import com.pufy.app.ui.AppNav
import com.pufy.app.ui.components.PulsingPufy
import com.pufy.app.ui.components.ShimmerBox
import com.pufy.app.ui.components.ShimmerText
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import com.pufy.app.ui.theme.Springs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

// iOS MessageRowView karşılığı

@Composable
fun MessageRow(
    message: Message,
    isLastResponse: Boolean,
    isGenerating: Boolean,
    onImageTap: (Any) -> Unit,
    onRegenerate: () -> Unit,
    onAction: (String) -> Unit,
) {
    if (message.isUser) UserRow(message, onImageTap) else AssistantRow(message, isLastResponse, isGenerating, onImageTap, onRegenerate, onAction)
}

@Composable
fun formatFileSize(bytes: Int): String {
    if (bytes < 1024) return "$bytes B"
    val kb = bytes / 1024.0
    if (kb < 1024) return String.format(java.util.Locale.US, "%.0f KB", kb)
    val mb = kb / 1024.0
    return String.format(java.util.Locale.US, "%.1f MB", mb)
}

@Composable
fun FileChip(
    file: com.pufy.app.data.FileAttachment,
    onRemove: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
    isLoading: Boolean = false,
) {
    val c = Pufy.colors
    val icon = when (file.kind) {
        "pdf" -> Icons.Rounded.PictureAsPdf
        "code" -> Icons.Rounded.Code
        else -> Icons.Rounded.Description
    }
    val sizeText = formatFileSize(file.size)

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(c.soft)
            .then(if (onClick != null) Modifier.pressable(onClick = onClick) else Modifier)
            .padding(start = 8.dp, end = if (onRemove != null) 4.dp else 10.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (isLoading) {
            androidx.compose.material3.CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = c.primary
            )
        } else {
            Icon(icon, null, Modifier.size(16.dp), tint = c.primary)
        }
        Column {
            Text(
                text = file.name,
                style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold),
                color = c.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 130.dp)
            )
            Text(
                text = sizeText,
                style = PufyType.caption.copy(fontSize = 10.sp),
                color = c.secondaryText
            )
        }
        if (onRemove != null) {
            Box(
                Modifier
                    .size(20.dp)
                    .clip(CircleShape)
                    .clickable(remember { MutableInteractionSource() }, null, onClick = onRemove),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Rounded.Close, stringResource(R.string.remove_action), Modifier.size(12.dp), tint = c.secondaryText)
            }
        }
    }
}

@Composable
fun FilePreviewDialog(
    file: com.pufy.app.data.FileAttachment,
    onDismiss: () -> Unit,
) {
    val c = Pufy.colors
    val isEn = com.pufy.app.core.AppLocales.isEnglish()
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 520.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(c.secondaryBackground)
                .padding(20.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            file.name,
                            style = PufyType.subheadline.copy(fontWeight = FontWeight.Bold),
                            color = c.text,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        val kindLabel = file.kind.uppercase()
                        val details = buildList {
                            add(kindLabel)
                            if (file.pageCount != null && file.pageCount > 0) add("${file.pageCount} ${if (isEn) "pages" else "sayfa"}")
                            add(formatFileSize(file.size))
                        }.joinToString(" · ")
                        Text(details, style = PufyType.caption, color = c.secondaryText)
                    }
                    Box(
                        Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(c.soft)
                            .clickable(remember { MutableInteractionSource() }, null, onClick = onDismiss),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Rounded.Close, stringResource(R.string.close), Modifier.size(16.dp), tint = c.text)
                    }
                }

                Box(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(c.soft.copy(alpha = 0.5f))
                        .padding(12.dp)
                ) {
                    val scrollState = rememberScrollState()
                    Column(modifier = Modifier.verticalScroll(scrollState)) {
                        SelectionContainer {
                            Text(
                                text = file.text.ifEmpty { if (isEn) "(No text extracted)" else "(Metin çıkarılamadı)" },
                                style = PufyType.caption.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, lineHeight = 16.sp),
                                color = c.text
                            )
                        }
                    }
                }

                if (file.truncated) {
                    Text(
                        if (isEn) "Text truncated to 60,000 characters." else "Metin 60.000 karakter sınırına göre kısaltılmıştır.",
                        style = PufyType.caption,
                        color = c.secondaryText
                    )
                }
            }
        }
    }
}

@Composable
private fun UserRow(message: Message, onImageTap: (Any) -> Unit) {
    val c = Pufy.colors
    var previewFile by remember { mutableStateOf<com.pufy.app.data.FileAttachment?>(null) }
    Column(Modifier.fillMaxWidth().padding(start = 44.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        message.syncImages.forEach { name ->
            val file = File(AppFiles.syncImages, name)
            AsyncImage(file, stringResource(R.string.sent_image), contentScale = ContentScale.Fit,
                modifier = Modifier.widthIn(max = 230.dp).heightIn(max = 260.dp).clip(RoundedCornerShape(18.dp)).pressable { onImageTap(file) })
        }
        message.files?.takeIf { it.isNotEmpty() }?.let { files ->
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                files.forEach { file ->
                    FileChip(file = file, onRemove = null, onClick = { previewFile = file })
                }
            }
        }
        if (message.content.isNotEmpty()) {
            SelectionContainer {
                Text(message.content, style = PufyType.body, color = c.text,
                    modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(c.userBubble).padding(horizontal = 16.dp, vertical = 11.dp))
            }
        }
    }

    if (previewFile != null) {
        FilePreviewDialog(file = previewFile!!, onDismiss = { previewFile = null })
    }
}

@Composable
private fun AssistantRow(
    message: Message, isLastResponse: Boolean, isGenerating: Boolean,
    onImageTap: (Any) -> Unit, onRegenerate: () -> Unit, onAction: (String) -> Unit,
) {
    val c = Pufy.colors
    val reportedIds by AIReportStore.reportedIds.collectAsState()
    val revealedIds by AIReportStore.revealedIds.collectAsState()
    val isReported = reportedIds.contains(message.id)
    val isRevealed = revealedIds.contains(message.id)
    var showReportDialog by remember { mutableStateOf(false) }
    val isEn = AppLocales.isEnglish()

    val text = remember(message.content) { Tags.displayText(message.content) }
    val images = remember(message.content) { Tags.imageURLs(message.content) }
    val defaultThinking = stringResource(R.string.thinking)
    val status = message.thinkingSteps.lastOrNull() ?: defaultThinking
    val isDrawing = isGenerating && images.isEmpty() && status == ResearchEngine.DRAWING
    val isThinking = isGenerating && text.isEmpty() && images.isEmpty() && !isDrawing

    if (isReported && !isRevealed) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(c.soft)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Outlined.Flag, null, Modifier.size(15.dp), tint = c.secondaryText)
            Text(
                if (isEn) "This response was reported and hidden." else "Bu cevap bildirildi ve gizlendi.",
                style = PufyType.caption,
                color = c.secondaryText,
                modifier = Modifier.weight(1f)
            )
            Text(
                if (isEn) "Show" else "Göster",
                style = PufyType.caption.copy(fontWeight = FontWeight.SemiBold),
                color = c.text,
                modifier = Modifier.pressable { AIReportStore.toggleReveal(message.id) }
            )
        }
        return
    }

    Column(Modifier.fillMaxWidth().animateContentSize(Springs.standard()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (isReported && isRevealed) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(c.soft.copy(alpha = 0.6f))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Outlined.Flag, null, Modifier.size(13.dp), tint = c.secondaryText)
                Text(
                    if (isEn) "Reported response" else "Bildirilen cevap",
                    style = PufyType.caption,
                    color = c.secondaryText,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    if (isEn) "Hide" else "Gizle",
                    style = PufyType.caption.copy(fontWeight = FontWeight.Medium),
                    color = c.secondaryText,
                    modifier = Modifier.pressable { AIReportStore.toggleReveal(message.id) }
                )
            }
        }

        AnimatedVisibility(!isThinking && isLastResponse, enter = fadeIn() + scaleIn(initialScale = 0.8f), exit = fadeOut()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Image(painterResource(R.drawable.chat_pp), null, Modifier.size(20.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                Text("Pufy", style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
            }
        }

        when {
            isDrawing -> DrawingCard()
            isThinking -> ThinkingIndicator(status, message.reasoning)
            !message.reasoning.isNullOrEmpty() -> ReasoningDisclosure(message.reasoning)
        }

        message.widgets?.mapNotNull { it as? kotlinx.serialization.json.JsonObject }?.forEachIndexed { i, w -> WidgetCard(w, message.id, i, isGenerating) }
        message.compare?.let { CompareCard(it) }

        images.forEach { url ->
            val model: Any = AiClient.resolveGeneratedImage(url) ?: url
            AsyncImage(model, stringResource(R.string.created_image), contentScale = ContentScale.FillWidth,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).pressable { onImageTap(model) })
        }

        if (text.isNotEmpty() && !isDrawing) {
            SelectionContainer { MarkdownView(if (isGenerating) text else text) }
        }

        message.quiz?.let { QuizCard(it, message.id, onAction) }
        message.deck?.let { SlideDeckCard(it, message.id, message.timestamp) }

        if (!isGenerating) {
            message.sources?.takeIf { it.isNotEmpty() }?.let { SourceChips(it) }
            Badges(message)
            if (text.isNotEmpty()) ActionBar(text, isLastResponse, onRegenerate, onReport = { showReportDialog = true })
            if (isLastResponse) message.actions?.takeIf { it.isNotEmpty() }?.let { ActionChipsRow(it, onAction) }
            message.appRequest?.let { req ->
                Row(
                    Modifier.clip(CircleShape)
                        .background(c.secondaryBackground)
                        .border(0.5.dp, c.text.copy(alpha = 0.08f), CircleShape)
                        .pressable { AppNav.openCreator(req.name, req.prompt) }
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(Icons.Outlined.AddBox, null, Modifier.size(13.dp), tint = c.text)
                    Text(androidx.compose.ui.res.stringResource(com.pufy.app.R.string.create_app_action), style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
                }
            }
        }
    }

    if (showReportDialog) {
        ReportDialog(
            messageId = message.id,
            messageText = text,
            modelName = AiClient.modelName,
            onDismiss = { showReportDialog = false }
        )
    }
}

@Composable
private fun ThinkingIndicator(status: String, reasoning: String?) {
    val c = Pufy.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PulsingPufy(Modifier.size(26.dp))
            AnimatedContent(status, transitionSpec = {
                (fadeIn() + slideInVertically { it / 2 }) togetherWith (fadeOut() + slideOutVertically { -it / 2 })
            }, label = "status") { s ->
                ShimmerText(s, PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold))
            }
        }
        if (!reasoning.isNullOrEmpty()) {
            val clean = reasoning.replace("**", "").trim()
            val tail = if (clean.length > 320) "…" + clean.takeLast(320) else clean
            Box(Modifier.padding(start = 36.dp).heightIn(max = 74.dp)
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black, Color.Black)), blendMode = BlendMode.DstIn)
                }, contentAlignment = Alignment.BottomStart) {
                Text(tail, style = PufyType.footnote, color = c.secondaryText, modifier = Modifier.animateContentSize())
            }
        }
    }
}

@Composable
private fun ReasoningDisclosure(reasoning: String) {
    val c = Pufy.colors
    var expanded by remember { mutableStateOf(false) }
    val rotation by animateFloatAsState(if (expanded) 90f else 0f, Springs.standard(), label = "chev")
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.pressable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Outlined.Psychology, null, Modifier.size(15.dp), tint = c.secondaryText)
            Text(stringResource(R.string.reasoning_process), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText)
            Icon(Icons.Rounded.ChevronRight, null, Modifier.size(14.dp).graphicsLayer { rotationZ = rotation }, tint = c.secondaryText)
        }
        AnimatedVisibility(expanded, enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
            Row {
                Box(Modifier.padding(end = 10.dp).size(2.dp, 40.dp).background(c.secondaryText.copy(alpha = 0.25f)))
                Text(reasoning.replace("**", ""), style = PufyType.footnote, color = c.secondaryText)
            }
        }
    }
}

@Composable
private fun DrawingCard() {
    val c = Pufy.colors
    Box(Modifier.fillMaxWidth().padding(end = 40.dp).clip(RoundedCornerShape(22.dp))) {
        ShimmerBox(Modifier.fillMaxWidth().heightIn(min = 220.dp))
        Row(Modifier.align(Alignment.Center), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PulsingPufy(Modifier.size(22.dp))
            ShimmerText(stringResource(R.string.drawing_image), PufyType.subheadline.copy(fontWeight = FontWeight.SemiBold))
        }
        Spacer(Modifier.size(1.dp).background(c.background))
    }
}

@Composable
private fun SourceChips(sources: List<WebSource>) {
    val c = Pufy.colors
    val uri = LocalUriHandler.current
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        sources.take(8).forEach { s ->
            Row(Modifier.clip(CircleShape).background(c.secondaryBackground).pressable { runCatching { uri.openUri(s.url) } }
                .padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AsyncImage("https://www.google.com/s2/favicons?domain=${s.host}&sz=64", null, Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)))
                Text(s.host, style = PufyType.caption.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
            }
        }
    }
}

@Composable
private fun Badges(m: Message) {
    if (m.searchQuery == null && m.reminderTitle == null && m.noteTitle == null) return
    val c = Pufy.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (m.searchQuery != null) Badge(Icons.Outlined.Language, stringResource(R.string.searched_web), c.primary)
        m.reminderTitle?.let { Badge(Icons.Outlined.NotificationsActive, it, c.reminder) }
        m.noteTitle?.let { Badge(Icons.AutoMirrored.Outlined.StickyNote2, it, c.primary) { m.noteID?.let { id -> AppNav.openNoteID.value = id } } }
    }
}

@Composable
private fun Badge(icon: ImageVector, text: String, color: Color, onClick: (() -> Unit)? = null) {
    Row(Modifier.clip(CircleShape).background(color.copy(alpha = 0.10f)).let { if (onClick != null) it.pressable(onClick = onClick) else it }
        .padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, Modifier.size(12.dp), tint = color)
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun ActionBar(text: String, showRegenerate: Boolean, onRegenerate: () -> Unit, onReport: () -> Unit = {}) {
    val c = Pufy.colors
    val clipboard = LocalClipboard.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isEn = AppLocales.isEnglish()
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1500); copied = false } }
    Row(Modifier.padding(start = 0.dp)) {
        @Composable fun action(icon: ImageVector, label: String, onClick: () -> Unit) =
            Box(Modifier.size(34.dp, 30.dp).pressable(onClick = onClick), contentAlignment = Alignment.Center) {
                Icon(icon, label, Modifier.size(17.dp), tint = c.secondaryText)
            }
        action(if (copied) Icons.Rounded.Check else Icons.Outlined.ContentCopy, if (isEn) "Copy" else "Kopyala") {
            scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Pufy", text))) }
            copied = true
        }
        if (showRegenerate) action(Icons.Outlined.Refresh, if (isEn) "Regenerate" else "Yeniden oluştur", onRegenerate)
        action(Icons.Outlined.Share, if (isEn) "Share" else "Paylaş") {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))
        }
        action(Icons.Outlined.Flag, if (isEn) "Report" else "Bildir", onReport)
    }
}

@Composable
fun FollowUpSuggestions(items: List<Pair<String, String>>, onPick: (String) -> Unit) {
    val c = Pufy.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.follow_up_title), style = PufyType.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, modifier = Modifier.padding(start = 4.dp))
        items.forEach { (title, question) ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(c.secondaryBackground).pressable { onPick(question) }
                .padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(question, style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text)
                    Text(title, style = PufyType.caption, color = c.secondaryText, maxLines = 1)
                }
                Icon(Icons.Rounded.ArrowOutward, null, Modifier.size(13.dp), tint = c.secondaryText)
            }
        }
    }
}
