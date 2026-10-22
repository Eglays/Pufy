package com.pufy.app.data

import com.pufy.app.core.PufyJson
import com.pufy.app.core.arr
import com.pufy.app.core.bool
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.core.num
import com.pufy.app.core.obj
import com.pufy.app.core.str
import com.pufy.app.core.strings
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// iOS Models.swift'in karşılığı. Belgeler iPhone ile aynı sunucudan eşitlendiği için biçim birebir aynı;
// bu cihazın bilmediği alanlar `extra` içinde aynen korunur (kaydedince kaybolmaz).

data class WebSource(val title: String, val url: String) {
    val host: String get() = runCatching { java.net.URI(url).host?.removePrefix("www.") }.getOrNull() ?: title
}

data class ChoiceQuestion(val q: String, val options: List<String>, val multi: Boolean? = null)

data class FileAttachment(
    val name: String,
    val kind: String, // "pdf" | "text" | "docx" | "code"
    val size: Int,
    val text: String,
    val truncated: Boolean,
    val pageCount: Int? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("name", name)
        put("kind", kind)
        put("size", size)
        put("text", text)
        put("truncated", truncated)
        if (pageCount != null) put("pageCount", pageCount)
    }

    companion object {
        fun fromJson(o: JsonObject): FileAttachment? {
            val name = o.str("name") ?: return null
            val kind = o.str("kind") ?: "text"
            val size = o.num("size")?.toInt() ?: 0
            val text = o.str("text") ?: ""
            val truncated = o.bool("truncated") ?: false
            val pageCount = o.num("pageCount")?.toInt()
            return FileAttachment(name, kind, size, text, truncated, pageCount)
        }
    }
}

data class AppRequestData(val name: String, val prompt: String)

data class Message(
    val id: String = newID(),
    val content: String,
    val role: String,                       // "user" | "model" | "system"
    val timestamp: Double = nowSwift(),
    /** Fotoğrafların dosya adları (bu cihazda SyncImages klasöründe; sunucuda /api/files) */
    val syncImages: List<String> = emptyList(),
    val isSearching: Boolean = false,
    val searchQuery: String? = null,
    val thinkingSteps: List<String> = emptyList(),
    val reminderTitle: String? = null,
    val isVoiceInitiated: Boolean = false,
    val reasoning: String? = null,
    val sources: List<WebSource>? = null,
    val imageTopics: List<String>? = null,
    val noteTitle: String? = null,
    val noteID: String? = null,
    val actions: List<String>? = null,
    val pendingDeckTitle: String? = null,
    /** Zengin parçalar ham JSON olarak (iOS ile aynı biçim): choices, widgets, compare, quiz, deck */
    val choices: JsonObject? = null,
    val widgets: JsonArray? = null,
    val compare: JsonObject? = null,
    val quiz: JsonObject? = null,
    val deck: JsonObject? = null,
    val files: List<FileAttachment>? = null,
    val appRequest: AppRequestData? = null,
    val extra: JsonObject = JsonObject(emptyMap()),
) {
    val isUser get() = role == "user"

    val choiceQuestions: List<ChoiceQuestion>
        get() = choices?.arr("questions")?.mapNotNull { q ->
            val o = q as? JsonObject ?: return@mapNotNull null
            ChoiceQuestion(o.str("q") ?: return@mapNotNull null, o.strings("options"), o.bool("multi"))
        } ?: emptyList()

    fun toJson(): JsonObject {
        val map = LinkedHashMap<String, JsonElement>(extra)
        map["id"] = JsonPrimitive(id)
        map["content"] = JsonPrimitive(content)
        map["role"] = JsonPrimitive(role)
        map["timestamp"] = JsonPrimitive(timestamp)
        map["imageDatas"] = JsonArray(emptyList())
        if (syncImages.isNotEmpty()) map["syncImages"] = JsonArray(syncImages.map(::JsonPrimitive)) else map.remove("syncImages")
        map["isSearching"] = JsonPrimitive(isSearching)
        map["thinkingSteps"] = JsonArray(thinkingSteps.map(::JsonPrimitive))
        map["isVoiceInitiated"] = JsonPrimitive(isVoiceInitiated)
        fun opt(key: String, value: JsonElement?) { if (value == null) map.remove(key) else map[key] = value }
        opt("searchQuery", searchQuery?.let(::JsonPrimitive))
        opt("reminderTitle", reminderTitle?.let(::JsonPrimitive))
        opt("reasoning", reasoning?.let(::JsonPrimitive))
        opt("sources", sources?.let { s -> JsonArray(s.map { buildJsonObject { put("title", it.title); put("url", it.url) } }) })
        opt("imageTopics", imageTopics?.let { JsonArray(it.map(::JsonPrimitive)) })
        opt("noteTitle", noteTitle?.let(::JsonPrimitive))
        opt("noteID", noteID?.let(::JsonPrimitive))
        opt("actions", actions?.let { JsonArray(it.map(::JsonPrimitive)) })
        opt("pendingDeckTitle", pendingDeckTitle?.let(::JsonPrimitive))
        opt("choices", choices)
        opt("widgets", widgets)
        opt("compare", compare)
        opt("quiz", quiz)
        opt("deck", deck)
        opt("files", files?.let { fs -> JsonArray(fs.map { it.toJson() }) })
        opt("appRequest", appRequest?.let { buildJsonObject { put("name", it.name); put("prompt", it.prompt) } })
        return JsonObject(map)
    }

    companion object {
        private val known = setOf("id", "content", "role", "timestamp", "imageDatas", "syncImages", "isSearching", "searchQuery",
            "thinkingSteps", "reminderTitle", "isVoiceInitiated", "reasoning", "sources", "imageTopics", "noteTitle", "noteID",
            "actions", "pendingDeckTitle", "choices", "widgets", "compare", "quiz", "deck", "files", "appRequest")

        fun fromJson(o: JsonObject): Message? {
            val id = o.str("id") ?: return null
            return Message(
                id = id,
                content = o.str("content") ?: "",
                role = o.str("role") ?: "user",
                timestamp = o.num("timestamp") ?: nowSwift(),
                syncImages = o.strings("syncImages"),
                isSearching = false,
                searchQuery = o.str("searchQuery"),
                thinkingSteps = o.strings("thinkingSteps"),
                reminderTitle = o.str("reminderTitle"),
                isVoiceInitiated = o.bool("isVoiceInitiated") ?: false,
                reasoning = o.str("reasoning"),
                sources = o.arr("sources")?.mapNotNull { s ->
                    val so = s as? JsonObject ?: return@mapNotNull null
                    WebSource(so.str("title") ?: "", so.str("url") ?: return@mapNotNull null)
                },
                imageTopics = o.arr("imageTopics")?.let { o.strings("imageTopics") },
                noteTitle = o.str("noteTitle"),
                noteID = o.str("noteID"),
                actions = o.arr("actions")?.let { o.strings("actions") },
                pendingDeckTitle = o.str("pendingDeckTitle"),
                choices = o.obj("choices"),
                widgets = o.arr("widgets"),
                compare = o.obj("compare"),
                quiz = o.obj("quiz"),
                deck = o.obj("deck"),
                files = o.arr("files")?.mapNotNull { (it as? JsonObject)?.let(FileAttachment::fromJson) },
                appRequest = o.obj("appRequest")?.let { AppRequestData(it.str("name") ?: "", it.str("prompt") ?: "") },
                extra = JsonObject(o.filterKeys { it !in known }),
            )
        }
    }
}

data class ChatSession(
    val id: String = newID(),
    val title: String,
    val messages: List<Message> = emptyList(),
    val createdAt: Double = nowSwift(),
    val isPinned: Boolean = false,
    val isSpaceChat: Boolean = false,
    val followUp: String? = null,
    val extra: JsonObject = JsonObject(emptyMap()),
) {
    val lastActivity: Double get() = messages.lastOrNull()?.timestamp ?: createdAt

    fun toJson(): JsonObject {
        val map = LinkedHashMap<String, JsonElement>(extra)
        map["id"] = JsonPrimitive(id)
        map["title"] = JsonPrimitive(title)
        map["messages"] = JsonArray(messages.map { it.toJson() })
        map["createdAt"] = JsonPrimitive(createdAt)
        map["isPinned"] = JsonPrimitive(isPinned)
        map["isSpaceChat"] = JsonPrimitive(isSpaceChat)
        if (followUp != null) map["followUp"] = JsonPrimitive(followUp) else map.remove("followUp")
        return JsonObject(map)
    }

    companion object {
        const val DEFAULT_TITLE = "Yeni Sohbet"
        private val known = setOf("id", "title", "messages", "createdAt", "isPinned", "isSpaceChat", "followUp")

        fun fromJson(o: JsonObject): ChatSession? {
            val id = o.str("id") ?: return null
            return ChatSession(
                id = id,
                title = o.str("title") ?: DEFAULT_TITLE,
                messages = o.arr("messages")?.mapNotNull { (it as? JsonObject)?.let(Message::fromJson) } ?: emptyList(),
                createdAt = o.num("createdAt") ?: nowSwift(),
                isPinned = o.bool("isPinned") ?: false,
                isSpaceChat = o.bool("isSpaceChat") ?: false,
                followUp = o.str("followUp"),
                extra = JsonObject(o.filterKeys { it !in known }),
            )
        }
    }
}

/** iOS MiniApp (AppTab.swift) */
data class MiniApp(val raw: JsonObject) {
    val id get() = raw.str("id") ?: ""
    val name get() = raw.str("name") ?: "Uygulama"
    val icon get() = raw.str("icon") ?: "app"
    val description get() = raw.str("description") ?: ""
    val folderName get() = raw.str("folderName")
    val entryPoint get() = raw.str("entryPoint") ?: "index.html"
    val colorHex get() = raw.str("colorHex")
    val updatedAt get() = raw.num("updatedAt") ?: 0.0
    val createdAt get() = raw.num("createdAt") ?: 0.0
    val htmlContent get() = raw.str("htmlContent") ?: ""
    val appSpecJson get() = raw.str("appSpecJson")
    val messages: List<Message> get() = raw.arr("messages")?.mapNotNull { (it as? JsonObject)?.let(Message::fromJson) } ?: emptyList()

    fun with(block: MutableMap<String, JsonElement>.() -> Unit): MiniApp = MiniApp(JsonObject(LinkedHashMap(raw).apply(block)))

    companion object {
        fun create(name: String, icon: String, description: String, folder: String, colorHex: String?, messages: List<Message>): MiniApp {
            val now = nowSwift()
            return MiniApp(buildJsonObject {
                put("id", newID()); put("name", name); put("icon", icon); put("description", description)
                put("htmlContent", ""); put("folderName", folder); put("entryPoint", "index.html")
                if (colorHex != null) put("colorHex", colorHex)
                put("createdAt", now); put("updatedAt", now)
                put("messages", JsonArray(messages.map { it.toJson() }))
            })
        }
    }
}

fun JsonObject.toPretty(): String = PufyJson.encodeToString(JsonObject.serializer(), this)
