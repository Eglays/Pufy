package com.pufy.app.ui.chat

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle

// iOS MarkdownView.swift'teki MarkdownParser'ın birebir karşılığı (aynı blok türleri, aynı kurallar)

data class MdListItem(val indent: Int, val marker: String, val text: String)

sealed interface MdBlock {
    data class Paragraph(val text: String) : MdBlock
    data class Heading(val level: Int, val text: String) : MdBlock
    data class ListBlock(val items: List<MdListItem>) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val language: String, val code: String) : MdBlock
    data class Table(val header: List<String>, val rows: List<List<String>>) : MdBlock
    data object Rule : MdBlock
    data class Image(val topic: String, val caption: String?) : MdBlock
    data class Gallery(val items: List<Pair<String, String?>>) : MdBlock
}

object MarkdownParser {
    private val cache = object : LinkedHashMap<String, List<MdBlock>>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<MdBlock>>?) = size > 300
    }

    fun blocks(text: String): List<MdBlock> = synchronized(cache) { cache.getOrPut(text) { parse(text) } }

    fun parse(text: String): List<MdBlock> {
        val lines = text.split("\n")
        val blocks = mutableListOf<MdBlock>()
        val paragraph = mutableListOf<String>()
        var i = 0
        fun flush() { if (paragraph.isNotEmpty()) { blocks.add(MdBlock.Paragraph(paragraph.joinToString("\n"))); paragraph.clear() } }

        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trim()

            if (trimmed.startsWith("```")) {
                flush()
                val language = trimmed.drop(3).trim()
                val code = mutableListOf<String>()
                i++
                while (i < lines.size && !lines[i].trim().startsWith("```")) { code.add(lines[i]); i++ }
                i++
                blocks.add(MdBlock.Code(language, code.joinToString("\n")))
                continue
            }
            if (trimmed.isEmpty()) { flush(); i++; continue }

            val upper = trimmed.uppercase()
            if (upper.startsWith("[IMGS")) {
                flush()
                val colon = trimmed.indexOf(':')
                if (trimmed.endsWith("]") && colon > 0) {
                    val items = trimmed.substring(colon + 1, trimmed.length - 1).split("|").mapNotNull { raw ->
                        val parts = raw.split("=", limit = 2).map { it.trim() }
                        val topic = parts.firstOrNull()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                        topic to parts.getOrNull(1)
                    }
                    if (items.isNotEmpty()) blocks.add(MdBlock.Gallery(items.take(6)))
                }
                i++; continue
            }
            if (upper.startsWith("[IMG")) {
                flush()
                val colon = trimmed.indexOf(':')
                if (trimmed.endsWith("]") && colon > 0) {
                    val parts = trimmed.substring(colon + 1, trimmed.length - 1).split("|", limit = 2).map { it.trim() }
                    parts.firstOrNull()?.takeIf { it.isNotEmpty() }?.let { blocks.add(MdBlock.Image(it, parts.getOrNull(1))) }
                }
                i++; continue
            }
            if (trimmed.startsWith("#")) {
                val level = trimmed.takeWhile { it == '#' }.length
                val rest = trimmed.drop(level)
                if (level <= 6 && rest.startsWith(" ")) { flush(); blocks.add(MdBlock.Heading(level, rest.trim())); i++; continue }
            }
            if (trimmed == "---" || trimmed == "***" || trimmed == "___") { flush(); blocks.add(MdBlock.Rule); i++; continue }

            if (trimmed.startsWith("|") && i + 1 < lines.size && isTableSeparator(lines[i + 1])) {
                flush()
                val header = cells(trimmed)
                val rows = mutableListOf<List<String>>()
                i += 2
                while (i < lines.size) {
                    val row = lines[i].trim()
                    if (!row.startsWith("|")) break
                    val c = cells(row)
                    rows.add((c + List(maxOf(0, header.size - c.size)) { "" }).take(header.size))
                    i++
                }
                blocks.add(MdBlock.Table(header, rows))
                continue
            }
            if (listMarker(line) != null) {
                flush()
                val items = mutableListOf<MdListItem>()
                while (i < lines.size) { val item = listMarker(lines[i]) ?: break; items.add(item); i++ }
                blocks.add(MdBlock.ListBlock(items))
                continue
            }
            if (trimmed.startsWith(">")) {
                flush()
                val quoted = mutableListOf<String>()
                while (i < lines.size) {
                    val q = lines[i].trim()
                    if (!q.startsWith(">")) break
                    quoted.add(q.drop(1).trim()); i++
                }
                blocks.add(MdBlock.Quote(quoted.joinToString("\n")))
                continue
            }
            paragraph.add(line)
            i++
        }
        flush()
        return blocks
    }

    private fun listMarker(line: String): MdListItem? {
        val leading = line.takeWhile { it == ' ' || it == '\t' }.length
        val indent = minOf(leading / 2, 3)
        val body = line.drop(leading)
        if (body.length >= 2 && body[0] in "-*•+" && body[1] == ' ') return MdListItem(indent, if (indent == 0) "•" else "◦", body.drop(2))
        val digits = body.takeWhile { it.isDigit() }
        if (digits.isNotEmpty() && digits.length <= 3) {
            val after = body.drop(digits.length)
            if (after.length >= 2 && (after[0] == '.' || after[0] == ')') && after[1] == ' ') return MdListItem(indent, "$digits.", after.drop(2))
        }
        return null
    }

    private fun isTableSeparator(line: String): Boolean {
        val t = line.trim()
        if (!t.contains("-") || !(t.contains("|") || t.startsWith("-"))) return false
        return t.all { it in "|-: " }
    }

    private fun cells(row: String): List<String> = row.removePrefix("|").removeSuffix("|").split("|").map { it.trim() }

    /** Satır içi biçim: **kalın**, *italik*, `kod`, [bağlantı](adres) */
    fun inline(text: String, codeBackground: Color, linkColor: Color): AnnotatedString = buildAnnotatedString {
        var i = 0
        val n = text.length
        while (i < n) {
            val c = text[i]
            if (c == '`') {
                val end = text.indexOf('`', i + 1)
                if (end > i) {
                    withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBackground)) { append(text.substring(i + 1, end)) }
                    i = end + 1; continue
                }
            }
            if (text.startsWith("**", i) || text.startsWith("__", i)) {
                val mark = text.substring(i, i + 2)
                val end = text.indexOf(mark, i + 2)
                if (end > i + 2) {
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(inline(text.substring(i + 2, end), codeBackground, linkColor)) }
                    i = end + 2; continue
                }
            }
            if ((c == '*' || c == '_') && i + 1 < n && !text[i + 1].isWhitespace()) {
                val end = text.indexOf(c, i + 1)
                val wordBoundary = c == '*' || i == 0 || !text[i - 1].isLetterOrDigit()
                if (end > i + 1 && wordBoundary && !text[end - 1].isWhitespace()) {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(inline(text.substring(i + 1, end), codeBackground, linkColor)) }
                    i = end + 1; continue
                }
            }
            if (c == '~' && text.startsWith("~~", i)) {
                val end = text.indexOf("~~", i + 2)
                if (end > i + 2) {
                    withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(text.substring(i + 2, end)) }
                    i = end + 2; continue
                }
            }
            if (c == '[') {
                val close = text.indexOf("](", i + 1)
                val paren = if (close > 0) text.indexOf(')', close + 2) else -1
                if (close > i && paren > close) {
                    val label = text.substring(i + 1, close)
                    val url = text.substring(close + 2, paren).trim()
                    if (url.startsWith("http")) {
                        withLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)))) {
                            append(inline(label, codeBackground, linkColor))
                        }
                        i = paren + 1; continue
                    }
                }
            }
            append(c)
            i++
        }
    }
}
