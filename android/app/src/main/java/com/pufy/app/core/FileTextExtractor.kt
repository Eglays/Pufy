package com.pufy.app.core

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.pufy.app.data.FileAttachment
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.Charset
import java.util.zip.ZipInputStream

object FileTextExtractor {
    const val MAX_FILE_SIZE = 25 * 1024 * 1024 // 25 MB
    const val MAX_TEXT_LENGTH = 60_000         // 60.000 karakter

    val SUPPORTED_EXTENSIONS = setOf(
        "pdf",
        "docx",
        "txt", "md", "csv", "json", "log",
        "swift", "kt", "py", "js", "ts", "html", "css", "xml", "yaml", "yml"
    )

    fun detectKind(ext: String): String = when (ext.lowercase()) {
        "pdf" -> "pdf"
        "docx" -> "docx"
        "txt", "md", "csv", "json", "log" -> "text"
        else -> "code"
    }

    suspend fun extract(context: Context, uri: Uri): Result<FileAttachment> = withContext(Dispatchers.IO) {
        runCatching {
            val (name, size) = queryFileInfo(context, uri)
            if (size > MAX_FILE_SIZE) {
                throw IllegalArgumentException(context.getString(com.pufy.app.R.string.file_too_large))
            }

            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException(context.getString(com.pufy.app.R.string.file_read_failed))

            processBytes(name, bytes, size)
        }
    }

    fun processBytes(name: String, bytes: ByteArray, reportedSize: Int = 0): FileAttachment {
        val size = if (reportedSize > 0) reportedSize else bytes.size
        if (bytes.size > MAX_FILE_SIZE || size > MAX_FILE_SIZE) {
            throw IllegalArgumentException("Dosya çok büyük")
        }

        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext !in SUPPORTED_EXTENSIONS) {
            throw IllegalArgumentException("Desteklenmeyen dosya türü")
        }

        val kind = detectKind(ext)
        var pageCount: Int? = null
        val rawText: String = when (kind) {
            "pdf" -> {
                ByteArrayInputStream(bytes).use { stream ->
                    PDDocument.load(stream).use { doc ->
                        pageCount = doc.numberOfPages
                        val stripper = PDFTextStripper()
                        val extracted = stripper.getText(doc).trim()
                        if (extracted.isEmpty()) {
                            throw IllegalStateException("Bu PDF'te okunabilir metin yok (taranmış belge olabilir)")
                        }
                        extracted
                    }
                }
            }
            "docx" -> {
                extractDocx(ByteArrayInputStream(bytes))
            }
            else -> {
                decodeText(bytes)
            }
        }

        val clean = rawText.trim()
        if (clean.isEmpty()) {
            throw IllegalStateException("Dosyada metin bulunamadı")
        }

        val truncated = clean.length > MAX_TEXT_LENGTH
        val finalText = if (truncated) clean.take(MAX_TEXT_LENGTH) else clean

        return FileAttachment(
            name = name,
            kind = kind,
            size = size,
            text = finalText,
            truncated = truncated,
            pageCount = pageCount
        )
    }

    fun extractDocx(stream: InputStream): String {
        val zip = ZipInputStream(stream)
        var entry = zip.nextEntry
        var documentXmlBytes: ByteArray? = null

        while (entry != null) {
            if (entry.name == "word/document.xml") {
                documentXmlBytes = zip.readBytes()
                break
            }
            zip.closeEntry()
            entry = zip.nextEntry
        }

        if (documentXmlBytes == null) {
            throw IllegalStateException("word/document.xml bulunamadı")
        }

        return parseDocxXml(ByteArrayInputStream(documentXmlBytes))
    }

    private fun parseDocxXml(stream: InputStream): String {
        val factory = XmlPullParserFactory.newInstance()
        factory.isNamespaceAware = true
        val parser = factory.newPullParser()
        parser.setInput(stream, "UTF-8")

        val sb = StringBuilder()
        var eventType = parser.eventType
        var inText = false

        while (eventType != XmlPullParser.END_DOCUMENT) {
            when (eventType) {
                XmlPullParser.START_TAG -> {
                    val name = parser.name.lowercase()
                    if (name == "t") {
                        inText = true
                    } else if (name == "tab") {
                        sb.append("\t")
                    } else if (name == "br") {
                        sb.append("\n")
                    }
                }
                XmlPullParser.TEXT -> {
                    if (inText) {
                        sb.append(parser.text)
                    }
                }
                XmlPullParser.END_TAG -> {
                    val name = parser.name.lowercase()
                    if (name == "t") {
                        inText = false
                    } else if (name == "p") {
                        sb.append("\n")
                    }
                }
            }
            eventType = parser.next()
        }
        return sb.toString().trim()
    }

    fun decodeText(bytes: ByteArray): String {
        val charsets = listOf(
            Charsets.UTF_8,
            runCatching { Charset.forName("windows-1254") }.getOrNull(),
            runCatching { Charset.forName("ISO-8859-9") }.getOrNull()
        ).filterNotNull()

        for (charset in charsets) {
            try {
                val decoder = charset.newDecoder()
                val charBuffer = decoder.decode(java.nio.ByteBuffer.wrap(bytes))
                return charBuffer.toString()
            } catch (_: Exception) {
            }
        }
        return String(bytes, Charsets.UTF_8)
    }

    private fun queryFileInfo(context: Context, uri: Uri): Pair<String, Int> {
        var name = uri.lastPathSegment ?: "dosya"
        var size = 0
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIndex != -1) name = cursor.getString(nameIndex) ?: name
                if (sizeIndex != -1) size = cursor.getInt(sizeIndex)
            }
        }
        return Pair(name, size)
    }
}
