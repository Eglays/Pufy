package com.pufy.app.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Mail
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pufy.app.R
import com.pufy.app.data.AppFiles
import com.pufy.app.ui.components.pressable
import com.pufy.app.ui.theme.Pufy
import com.pufy.app.ui.theme.PufyType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@Serializable
data class AIReport(
    val id: String = UUID.randomUUID().toString(),
    val date: String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).format(Date()),
    val reason: String,
    val description: String,
    val messageText: String,
    val modelName: String
)

object AIReportStore {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val _reportedIds = MutableStateFlow<Set<String>>(emptySet())
    val reportedIds = _reportedIds.asStateFlow()

    private val _revealedIds = MutableStateFlow<Set<String>>(emptySet())
    val revealedIds = _revealedIds.asStateFlow()

    fun init() {
        val saved = Settings.stringSet("ai_reported_message_ids")
        _reportedIds.value = saved
    }

    fun isReported(messageId: String): Boolean = _reportedIds.value.contains(messageId)
    fun isRevealed(messageId: String): Boolean = _revealedIds.value.contains(messageId)

    fun toggleReveal(messageId: String) {
        val current = _revealedIds.value
        _revealedIds.value = if (current.contains(messageId)) current - messageId else current + messageId
    }

    fun submitReport(
        messageId: String,
        reason: String,
        description: String,
        messageText: String,
        modelName: String,
        onDone: (AIReport) -> Unit
    ) {
        val report = AIReport(
            reason = reason,
            description = description.trim(),
            messageText = messageText.take(2000),
            modelName = modelName
        )

        // Cihazda sakla
        val existingReports = AppFiles.readArray("ai_reports.json").toMutableList()
        val reportJson = buildJsonObject {
            put("id", report.id)
            put("date", report.date)
            put("reason", report.reason)
            put("description", report.description)
            put("messageText", report.messageText)
            put("modelName", report.modelName)
        }
        existingReports.add(reportJson)
        AppFiles.writeArray("ai_reports.json", existingReports)

        // Bildirilen ID'yi kaydet
        val newSet = _reportedIds.value + messageId
        _reportedIds.value = newSet
        Settings.setStringSet("ai_reported_message_ids", newSet)

        val rev = _revealedIds.value - messageId
        _revealedIds.value = rev

        // REPORT_ENDPOINT doluysa POST at
        LegalLinks.REPORT_ENDPOINT?.let { endpoint ->
            kotlinx.coroutines.GlobalScope.launch(Dispatchers.IO) {
                runCatching {
                    val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        doOutput = true
                        setRequestProperty("Content-Type", "application/json")
                        connectTimeout = 10000
                        readTimeout = 10000
                    }
                    conn.outputStream.use { os ->
                        os.write(json.encodeToString(AIReport.serializer(), report).toByteArray())
                    }
                    conn.responseCode
                    conn.disconnect()
                }
            }
        }

        onDone(report)
    }

    fun clearAll() {
        _reportedIds.value = emptySet()
        _revealedIds.value = emptySet()
        Settings.setStringSet("ai_reported_message_ids", emptySet())
        AppFiles.writeArray("ai_reports.json", emptyList())
    }
}

@Composable
fun ReportDialog(
    messageId: String,
    messageText: String,
    modelName: String,
    onDismiss: () -> Unit
) {
    val isEn = AppLocales.isEnglish()
    val c = Pufy.colors
    val context = LocalContext.current
    var selectedReasonIndex by remember { mutableIntStateOf(0) }
    var description by remember { mutableStateOf("") }
    var submittedReport by remember { mutableStateOf<AIReport?>(null) }

    val reasons = remember(isEn) {
        if (isEn) listOf(
            "Offensive / hateful",
            "Sexual content",
            "Violent / dangerous",
            "False / misleading information",
            "Other"
        ) else listOf(
            "Saldırgan / nefret içeren",
            "Cinsel içerik",
            "Şiddet / tehlikeli",
            "Yanlış / yanıltıcı bilgi",
            "Diğer"
        )
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                if (submittedReport != null) {
                    if (isEn) "Report Submitted" else "Bildirim Kaydedildi"
                } else {
                    if (isEn) "Report Response" else "Cevabı Bildir"
                },
                style = PufyType.headline,
                color = c.text
            )
        },
        text = {
            if (submittedReport != null) {
                val rep = submittedReport!!
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Icon(
                        Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = Color(0xFF34C759)
                    )
                    Text(
                        if (isEn) "Thank you, your report has been saved." else "Teşekkürler, bildirimin kaydedildi.",
                        style = PufyType.body.copy(fontWeight = FontWeight.SemiBold),
                        color = c.text,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                    Text(
                        if (isEn) "This response was reported and hidden." else "Bu cevap bildirildi ve gizlendi.",
                        style = PufyType.caption,
                        color = c.secondaryText,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )

                    HorizontalDivider(color = c.separator.copy(alpha = 0.5f))

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(c.soft)
                            .pressable {
                                sendReportEmail(context, rep)
                            }
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(Icons.Outlined.Mail, null, Modifier.size(16.dp), tint = c.text)
                        Spacer(Modifier.size(8.dp))
                        Text(
                            if (isEn) "Send via email as well" else "E-postayla da gönder",
                            style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium),
                            color = c.text
                        )
                    }
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        if (isEn) "Reason for reporting:" else "Bildirme sebebi:",
                        style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium),
                        color = c.secondaryText
                    )

                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        reasons.forEachIndexed { index, reason ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .clickable { selectedReasonIndex = index }
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = selectedReasonIndex == index,
                                    onClick = { selectedReasonIndex = index },
                                    colors = RadioButtonDefaults.colors(
                                        selectedColor = c.primary,
                                        unselectedColor = c.secondaryText
                                    )
                                )
                                Text(
                                    reason,
                                    style = PufyType.body,
                                    color = c.text,
                                    modifier = Modifier.padding(start = 4.dp)
                                )
                            }
                        }
                    }

                    HorizontalDivider(color = c.separator.copy(alpha = 0.5f))

                    Text(
                        if (isEn) "Explanation (max 500 characters):" else "Açıklama (en fazla 500 karakter):",
                        style = PufyType.subheadline.copy(fontWeight = FontWeight.Medium),
                        color = c.secondaryText
                    )

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(c.soft)
                            .padding(10.dp)
                    ) {
                        BasicTextField(
                            value = description,
                            onValueChange = { if (it.length <= 500) description = it },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 60.dp),
                            textStyle = PufyType.body.copy(color = c.text),
                            cursorBrush = SolidColor(c.text),
                            decorationBox = { innerTextField ->
                                if (description.isEmpty()) {
                                    Text(
                                        if (isEn) "Additional details (optional)..." else "Ek açıklama (isteğe bağlı)...",
                                        style = PufyType.body,
                                        color = c.tertiaryText
                                    )
                                }
                                innerTextField()
                            }
                        )
                    }
                    Text(
                        "${500 - description.length}",
                        style = PufyType.caption,
                        color = c.tertiaryText,
                        modifier = Modifier.align(Alignment.End)
                    )
                }
            }
        },
        confirmButton = {
            if (submittedReport != null) {
                TextButton(onClick = onDismiss) {
                    Text(if (isEn) "Done" else "Tamam", fontWeight = FontWeight.SemiBold)
                }
            } else {
                TextButton(
                    onClick = {
                        val reason = reasons[selectedReasonIndex]
                        AIReportStore.submitReport(
                            messageId = messageId,
                            reason = reason,
                            description = description,
                            messageText = messageText,
                            modelName = modelName
                        ) { rep ->
                            submittedReport = rep
                        }
                    }
                ) {
                    Text(if (isEn) "Submit" else "Gönder", fontWeight = FontWeight.SemiBold)
                }
            }
        },
        dismissButton = if (submittedReport == null) {
            {
                TextButton(onClick = onDismiss) {
                    Text(if (isEn) "Cancel" else "Vazgeç")
                }
            }
        } else null
    )
}

private fun sendReportEmail(context: Context, report: AIReport) {
    val subject = "[Pufy AI Report] ${report.reason} - ${report.id.take(8)}"
    val body = """
        Report ID: ${report.id}
        Date: ${report.date}
        Reason: ${report.reason}
        Model: ${report.modelName}

        Description:
        ${report.description.ifEmpty { "(None)" }}

        Response Text:
        ${report.messageText}
    """.trimIndent()

    val intent = Intent(Intent.ACTION_SENDTO).apply {
        data = Uri.parse("mailto:${LegalLinks.SUPPORT_EMAIL}")
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, body)
    }
    runCatching { context.startActivity(Intent.createChooser(intent, null)) }
}
