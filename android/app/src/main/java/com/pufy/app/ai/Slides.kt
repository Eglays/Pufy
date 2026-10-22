package com.pufy.app.ai

import com.pufy.app.core.arr
import com.pufy.app.core.extractJsonObject
import com.pufy.app.core.nowSwift
import com.pufy.app.core.obj
import com.pufy.app.core.str
import com.pufy.app.data.ChatStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Sunum ([SLIDES]) — iOS SlideMaker: cevap ekrana geldikten SONRA ayrı istekle hazırlanır (cevap gecikmez).
 * Biçim iOS SlideDeck ile aynı (iPhone'da da açılır): {title, subtitle, slides, status, startedAt, theme, pattern, accent}
 */
object Slides {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + com.pufy.app.core.SafeErrors)
    val kinds = setOf("cover", "bullets", "compare", "stats", "timeline", "verdict", "section", "quote", "image", "proscons")
    private val themes = listOf("mono", "ocean", "forest", "sunset", "sand", "slate", "crimson", "teal", "gold", "midnight")
    private val patterns = setOf("rings", "dots", "grid", "waves", "diagonal", "blobs", "arcs", "none")

    fun pending(title: String) = buildJsonObject { put("title", title); put("slides", JsonArray(emptyList())); put("status", "generating"); put("startedAt", nowSwift()) }

    fun start(sessionID: String, messageID: String, answer: String) {
        val session = ChatStore.session(sessionID) ?: return
        val index = session.messages.indexOfFirst { it.id == messageID }
        val title = session.messages.getOrNull(index)?.deck?.str("title") ?: return
        val earlier = session.messages.take(maxOf(index, 0)).takeLast(5).filter { it.content.isNotEmpty() }
        val parts = earlier.map { (if (it.isUser) "KULLANICI: " else "ASİSTAN: ") + it.content.take(if (it.isUser) 800 else 7000) }.toMutableList()
        val clean = Tags.extractRich(answer).text
        if (clean.isNotEmpty()) parts.add("ASİSTAN (son cevap): " + clean.take(9000))
        val length = maxOf(clean.length, earlier.filter { !it.isUser }.maxOfOrNull { it.content.length } ?: 0)
        scope.launch {
            val deck = runCatching { make(title, parts.joinToString("\n\n"), length) }.getOrNull()
            ChatStore.mutateMessage(sessionID, messageID, notify = true) { m ->
                m.copy(deck = deck ?: JsonObject(LinkedHashMap(m.deck ?: pending(title)).apply { put("status", JsonPrimitive("failed")) }))
            }
        }
    }

    fun retry(sessionID: String, messageID: String) {
        val m = ChatStore.session(sessionID)?.messages?.firstOrNull { it.id == messageID } ?: return
        val title = m.deck?.str("title") ?: return
        ChatStore.mutateMessage(sessionID, messageID) { it.copy(deck = pending(title)) }
        start(sessionID, messageID, m.content)
    }

    private suspend fun make(title: String, conversation: String, contentLength: Int): JsonObject {
        val size = when { contentLength < 1300 -> "KISA (3-4 slayt)"; contentLength < 3500 -> "NORMAL (5-8 slayt)"; else -> "UZUN (9-15 slayt)" }
        val raw = AiClient.generate("Sunum konusu: $title\nİçerik: ~$contentLength karakter → $size\n\n$conversation",
            system = Prompts.SLIDES, maxOutputTokens = 8192, responseMimeType = "application/json", timeoutSeconds = 90, thinking = "low")
        val json = extractJsonObject(raw) ?: error("Sunum boş döndü.")
        val deckTitle = json.str("title")?.takeIf { it.isNotBlank() } ?: title
        val slides = json.arr("slides").orEmpty().mapNotNull { it as? JsonObject }.filter { it.str("kind")?.lowercase() in kinds }.toMutableList()
        if (slides.firstOrNull()?.str("kind") != "cover") slides.add(0, buildJsonObject { put("kind", "cover"); put("title", deckTitle); json.str("subtitle")?.let { put("subtitle", it) } })
        require(slides.size >= 3) { "Sunum çok kısa çıktı." }
        val theme = json.str("theme")?.lowercase()?.takeIf { it in themes } ?: themes[deckTitle.sumOf { it.code } % themes.size]
        return JsonObject(buildMap<String, JsonElement> {
            put("title", JsonPrimitive(deckTitle))
            json.str("subtitle")?.let { put("subtitle", JsonPrimitive(it)) }
            put("slides", JsonArray(slides.take(15)))
            put("status", JsonPrimitive("ready"))
            put("startedAt", JsonPrimitive(nowSwift()))
            put("theme", JsonPrimitive(theme))
            put("pattern", JsonPrimitive(json.str("pattern")?.lowercase()?.takeIf { it in patterns } ?: "rings"))
            json.str("accent")?.let { put("accent", JsonPrimitive(it)) }
        })
    }

    @Suppress("unused") private fun JsonObject.o(k: String) = obj(k)
}
