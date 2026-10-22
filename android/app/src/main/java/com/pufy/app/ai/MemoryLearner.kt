package com.pufy.app.ai

import com.pufy.app.core.TR
import com.pufy.app.core.arr
import com.pufy.app.core.extractJsonObject
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.core.str
import com.pufy.app.core.strings
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.MemoryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * Kişisel Ağ öğrenmesi (iOS MemoryStore.learn + MemoryExtractor): kullanıcının mesajından kendisi hakkındaki KALICI
 * bilgileri çıkarır, bilinenleri günceller ya da siler. Kurallar iOS'tan üretilen Prompts.MEMORY_EXTRACTOR.
 */
object MemoryLearner {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + com.pufy.app.core.SafeErrors)
    private val lock = Mutex()
    private val pending = mutableListOf<String>()

    fun learn(userText: String, context: String?) {
        val text = userText.trim()
        val askedQuestion = context?.contains("?") == true
        val lowered = text.lowercase(TR)
        val isCorrection = listOf("unut", "sil", "hatırlama", "yanlış", "değilim", "yok artık", "artık").any { lowered.contains(it) }
        if (!(text.length >= 15 || isCorrection || (askedQuestion && text.length >= 2))) return
        synchronized(pending) {
            pending.add(if (context != null && askedQuestion) "Asistanın sorusu: \"${context.takeLast(400)}\"\nKullanıcının cevabı: \"$text\"" else "Kullanıcı: \"$text\"")
        }
        scope.launch { drain() }
    }

    private suspend fun drain() = lock.withLock {
        while (true) {
            val batch = synchronized(pending) { if (pending.isEmpty()) null else pending.joinToString("\n\n---\n\n").also { pending.clear() } } ?: break
            runCatching { learnBatch(batch) }
        }
    }

    private suspend fun learnBatch(text: String) {
        val known = MemoryStore.items.value
        val idMap = known.mapIndexed { i, item -> "m$i" to (item.str("id") ?: "") }.toMap()
        val knownText = if (known.isEmpty()) "(henüz yok)" else known.mapIndexed { i, it -> "m$i [${MemoryStore.category(it)}] ${it.str("detail") ?: ""}" }.joinToString("\n")
        val prompt = "Bugün: ${turkeyFormat(System.currentTimeMillis(), "d MMMM yyyy")}\n\nBİLİNENLER:\n$knownText\n\nYENİ KONUŞMA:\n\"\"\"\n${text.take(12000)}\n\"\"\""
        val raw = AiClient.generate(prompt, system = Prompts.MEMORY_EXTRACTOR, maxOutputTokens = 8192, responseMimeType = "application/json", thinking = "low")
        val json = extractJsonObject(raw) ?: return
        val categories = setOf("identity", "people", "work", "skills", "interests", "preferences", "traits", "places", "goals", "health")

        for (key in json.strings("remove")) idMap[key]?.let { MemoryStore.delete(it) }
        for (u in json.arr("update").orEmpty().mapNotNull { it as? JsonObject }) {
            val id = idMap[u.str("id") ?: continue] ?: continue
            val item = MemoryStore.items.value.firstOrNull { it.str("id") == id } ?: continue
            val map = LinkedHashMap<String, JsonElement>(item)
            u.str("label")?.takeIf { it.isNotBlank() }?.let { map["text"] = JsonPrimitive(it) }
            u.str("detail")?.takeIf { it.isNotBlank() }?.let { map["detail"] = JsonPrimitive(it) }
            u.str("category")?.lowercase()?.takeIf { it in categories }?.let { map["category"] = JsonPrimitive(it) }
            u.str("entity")?.let { map["entity"] = JsonPrimitive(it) }
            u.str("relation")?.let { map["relation"] = JsonPrimitive(it) }
            (u["importance"] as? JsonPrimitive)?.let { it.intOrNull ?: it.content.toIntOrNull() }?.let { map["importance"] = JsonPrimitive(it.coerceIn(1, 5)) }
            u.strings("keywords").takeIf { it.isNotEmpty() }?.let { k -> map["keywords"] = JsonArray(k.map(::JsonPrimitive)) }
            map["updatedAt"] = JsonPrimitive(nowSwift())
            MemoryStore.upsert(JsonObject(map))
        }
        val adds = json.arr("add") ?: json.arr("facts")
        for (f in adds.orEmpty().mapNotNull { it as? JsonObject }) {
            val detail = f.str("detail")?.trim()?.takeIf { it.isNotEmpty() } ?: continue
            val norm = normalize(detail)
            if (MemoryStore.items.value.any { similarity(normalize(it.str("detail") ?: ""), norm) > 0.7 }) continue
            val now = nowSwift()
            // iOS MemoryItem'ın zorunlu alanlarının hepsi yazılır (iPhone okuyabilsin)
            MemoryStore.upsert(JsonObject(buildMap {
                put("id", JsonPrimitive(newID()))
                put("text", JsonPrimitive(f.str("label")?.takeIf { it.isNotBlank() } ?: detail.take(24)))
                put("detail", JsonPrimitive(detail))
                put("category", JsonPrimitive(f.str("category")?.lowercase()?.takeIf { it in categories } ?: "other"))
                f.str("entity")?.let { put("entity", JsonPrimitive(it)) }
                f.str("relation")?.let { put("relation", JsonPrimitive(it)) }
                put("importance", JsonPrimitive(((f["importance"] as? JsonPrimitive)?.let { it.intOrNull ?: it.content.toIntOrNull() } ?: 3).coerceIn(1, 5)))
                put("isManual", JsonPrimitive(false))
                put("createdAt", JsonPrimitive(now)); put("updatedAt", JsonPrimitive(now))
                put("keywords", JsonArray(f.strings("keywords").map(::JsonPrimitive)))
                put("weight", JsonPrimitive(0.5)); put("angle", JsonPrimitive(0)); put("icon", JsonPrimitive("sparkle"))
            }))
        }
    }

    private fun normalize(t: String) = t.lowercase(TR).trim().trim { !it.isLetterOrDigit() }
    private fun similarity(a: String, b: String): Double {
        val sa = a.split(" ").filter { it.length > 2 }.toSet(); val sb = b.split(" ").filter { it.length > 2 }.toSet()
        if (sa.isEmpty() || sb.isEmpty()) return 0.0
        return sa.intersect(sb).size.toDouble() / sa.union(sb).size
    }

    @Suppress("unused") private fun id() = newID()
}
