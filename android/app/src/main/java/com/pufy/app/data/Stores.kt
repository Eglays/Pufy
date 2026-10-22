package com.pufy.app.data

import android.content.Context
import com.pufy.app.core.PufyJson
import com.pufy.app.core.bool
import com.pufy.app.core.int
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.core.num
import com.pufy.app.core.str
import com.pufy.app.core.strings
import com.pufy.app.core.swiftToEpochMillis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File

/** Uygulamanın dosya klasörleri */
object AppFiles {
    lateinit var root: File; private set
    val syncImages get() = File(root, "SyncImages").apply { mkdirs() }
    val miniApps get() = File(root, "MiniApps").apply { mkdirs() }
    val miniAppData get() = File(root, "MiniAppData").apply { mkdirs() }
    fun init(context: Context) { root = context.filesDir }

    fun readArray(name: String): List<JsonObject> = runCatching {
        (PufyJson.parseToJsonElement(File(root, name).readText()) as JsonArray).mapNotNull { it as? JsonObject }
    }.getOrDefault(emptyList())

    fun writeArray(name: String, items: List<JsonObject>) {
        val file = File(root, name)
        val tmp = File(root, "$name.tmp")
        tmp.writeText(PufyJson.encodeToString(JsonArray.serializer(), JsonArray(items)))
        tmp.renameTo(file)
    }
}

private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO + com.pufy.app.core.SafeErrors)

/** Kısa aralıklarla gelen değişiklikleri tek yazmaya toplar (akış sırasında her harfte diske yazmasın) */
private class Debouncer(private val delayMs: Long = 400, private val action: () -> Unit) {
    private var job: Job? = null
    @Synchronized fun schedule() { job?.cancel(); job = io.launch { delay(delayMs); action() } }
    fun now() { job?.cancel(); action() }
}

// MARK: - Sohbetler

object ChatStore {
    private val _sessions = MutableStateFlow<List<ChatSession>>(emptyList())
    val sessions: StateFlow<List<ChatSession>> = _sessions.asStateFlow()
    private val saver = Debouncer { AppFiles.writeArray("sessions.json", _sessions.value.map { it.toJson() }) }
    /** Değişiklik olunca (eşitleme gönderimi için) */
    var onChange: (() -> Unit)? = null

    fun load() { _sessions.value = AppFiles.readArray("sessions.json").mapNotNull(ChatSession::fromJson) }

    fun session(id: String?) = _sessions.value.firstOrNull { it.id == id }

    fun upsert(session: ChatSession, notify: Boolean = true) {
        _sessions.update { list -> if (list.any { it.id == session.id }) list.map { if (it.id == session.id) session else it } else listOf(session) + list }
        saver.schedule(); if (notify) onChange?.invoke()
    }

    fun mutate(id: String, notify: Boolean = true, block: (ChatSession) -> ChatSession) {
        _sessions.update { list -> list.map { if (it.id == id) block(it) else it } }
        saver.schedule(); if (notify) onChange?.invoke()
    }

    fun mutateMessage(sessionID: String, messageID: String, notify: Boolean = false, block: (Message) -> Message) =
        mutate(sessionID, notify) { s -> s.copy(messages = s.messages.map { if (it.id == messageID) block(it) else it }) }

    fun moveToTop(id: String) = _sessions.update { list ->
        val s = list.firstOrNull { it.id == id } ?: return@update list
        if (s.isPinned) list else listOf(s) + list.filter { it.id != id }
    }

    fun delete(id: String) { _sessions.update { it.filter { s -> s.id != id } }; saver.schedule(); onChange?.invoke() }

    fun flush() = saver.now()

    /** Diğer cihazdan gelen sohbet (iOS applyRemoteSession) */
    fun applyRemote(session: ChatSession) {
        _sessions.update { list -> if (list.any { it.id == session.id }) list.map { if (it.id == session.id) session else it } else list + session }
        _sessions.update { list -> list.sortedWith(compareByDescending<ChatSession> { it.isPinned }.thenByDescending { it.lastActivity }) }
        saver.schedule()
    }

    fun applyRemoteDeletion(id: String) { _sessions.update { it.filter { s -> s.id != id } }; saver.schedule() }

    fun clearAll() { _sessions.value = emptyList(); AppFiles.writeArray("sessions.json", emptyList()); saver.now() }
}

// MARK: - Kişisel Ağ

object MemoryStore {
    private val _items = MutableStateFlow<List<JsonObject>>(emptyList())
    val items: StateFlow<List<JsonObject>> = _items.asStateFlow()
    private val saver = Debouncer { AppFiles.writeArray("memory.json", _items.value) }
    var onChange: (() -> Unit)? = null

    fun load() { _items.value = AppFiles.readArray("memory.json") }

    fun applyRemote(item: JsonObject) {
        val id = item.str("id") ?: return
        _items.update { list -> if (list.any { it.str("id") == id }) list.map { if (it.str("id") == id) item else it } else list + item }
        saver.schedule()
    }
    fun applyRemoteDeletion(id: String) { _items.update { it.filter { i -> i.str("id") != id } }; saver.schedule() }

    fun upsert(item: JsonObject) { applyRemote(item); onChange?.invoke() }
    fun delete(id: String) { applyRemoteDeletion(id); onChange?.invoke() }
    fun clearAll() { _items.value = emptyList(); AppFiles.writeArray("memory.json", emptyList()); saver.now() }

    val categoryOrder = listOf("identity", "people", "work", "skills", "interests", "preferences", "traits", "places", "goals", "health", "other")
    private val categoryTitles = mapOf("identity" to "Kimlik", "people" to "İnsanlar", "work" to "İş & Okul", "skills" to "Beceriler",
        "interests" to "İlgi Alanları", "preferences" to "Tercihler", "traits" to "Kişilik", "places" to "Yerler",
        "goals" to "Hedefler", "health" to "Sağlık", "other" to "Diğer")

    fun category(item: JsonObject) = item.str("category")?.takeIf { it in categoryOrder } ?: "other"
    private val categoryTitlesEn = mapOf("identity" to "Identity", "people" to "People", "work" to "Work & School", "skills" to "Skills",
        "interests" to "Interests", "preferences" to "Preferences", "traits" to "Personality", "places" to "Places",
        "goals" to "Goals", "health" to "Health", "other" to "Other")
    /** Ekranda görünen ad (dile göre); promptText Türkçe adları kullanmaya devam eder */
    fun categoryTitle(key: String) = if (com.pufy.app.core.AppLocales.isEnglish()) categoryTitlesEn[key] ?: "Other" else categoryTitles[key] ?: "Diğer"
    fun importance(item: JsonObject) = (item.int("importance") ?: 3).coerceIn(1, 5)

    /** Yapay zekaya verilen Kişisel Ağ: TAMAMI (iOS MemoryStore.promptText) */
    fun promptText(query: String): String {
        val items = _items.value
        if (items.isEmpty()) return "Henüz bir bilgi yok."
        val related = relevant(query, 8)
        val relatedIDs = related.mapNotNull { it.str("id") }.toSet()
        val sorted = items.sortedWith(compareBy<JsonObject> { categoryOrder.indexOf(category(it)) }.thenByDescending { importance(it) })
        val shown = if (sorted.size <= 150) sorted else sorted.filter { importance(it) >= 3 || it.str("id") in relatedIDs }.take(150)
        val lines = mutableListOf<String>()
        var current: String? = null
        for (item in shown) {
            val c = category(item)
            if (c != current) { current = c; lines.add("${categoryTitles[c] ?: "Diğer"}:") }
            lines.add("  - ${item.str("detail") ?: item.str("text") ?: ""}")
        }
        if (related.isNotEmpty()) lines.add("Bu mesajla en ilgili görünenler: " + related.joinToString("; ") { it.str("detail") ?: "" })
        return lines.joinToString("\n")
    }

    private fun tokens(text: String) = text.lowercase(com.pufy.app.core.TR).split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 3 }
    private fun matches(a: String, b: String): Boolean {
        val n = minOf(a.length, b.length)
        if (n < 3) return a == b
        val prefix = maxOf(3, minOf(a.length, b.length) - 2)
        return a.take(prefix) == b.take(prefix) || a.startsWith(b) || b.startsWith(a)
    }

    fun relevant(query: String, limit: Int = 8): List<JsonObject> {
        val qt = tokens(query)
        if (qt.isEmpty()) return emptyList()
        return _items.value.mapNotNull { item ->
            val kw = item.strings("keywords").flatMap(::tokens)
            val words = tokens(listOfNotNull(item.str("text"), item.str("detail"), item.str("entity"), item.str("relation")).joinToString(" "))
            var score = 0.0
            for (t in qt) { if (kw.any { matches(t, it) }) score += 2 else if (words.any { matches(t, it) }) score += 1 }
            if (score > 0) item to score + importance(item) * 0.05 else null
        }.sortedByDescending { it.second }.take(limit).map { it.first }
    }
}

// MARK: - Notlar

data class Note(val id: String = newID(), val title: String, val content: String, val createdAt: Double = nowSwift(), val updatedAt: Double = nowSwift()) {
    fun toJson() = buildJsonObject { put("id", id); put("title", title); put("content", content); put("createdAt", createdAt); put("updatedAt", updatedAt) }
    val checklistProgress: Pair<Int, Int>? get() {
        val items = content.lines().mapNotNull { NoteLine.checkItem(it.trim()) }
        return if (items.isEmpty()) null else items.count { it.first } to items.size
    }
    val summary: String get() {
        val isEn = com.pufy.app.core.AppLocales.isEnglish()
        val p = checklistProgress
        if (p != null) return if (isEn) "${p.first}/${p.second} completed" else "${p.first}/${p.second} tamamlandı"
        return content.lines().firstOrNull { it.isNotBlank() }?.trim()?.removePrefix("- ")?.take(60) ?: if (isEn) "Empty note" else "Boş not"
    }
    companion object {
        fun fromJson(o: JsonObject): Note? = Note(o.str("id") ?: return null, o.str("title") ?: "", o.str("content") ?: "",
            o.num("createdAt") ?: nowSwift(), o.num("updatedAt") ?: nowSwift())
    }
}

object NoteLine {
    /** "- [ ] Süt" / "- [x] Süt" → (tamam mı, metin) */
    fun checkItem(line: String): Pair<Boolean, String>? {
        val m = Regex("""^[-*•]\s*\[( |x|X)]\s*(.*)$""").find(line) ?: return null
        return (m.groupValues[1].lowercase() == "x") to m.groupValues[2]
    }
}

object NoteStore {
    private val _notes = MutableStateFlow<List<Note>>(emptyList())
    val notes: StateFlow<List<Note>> = _notes.asStateFlow()
    private val saver = Debouncer { AppFiles.writeArray("pufy-notes.json", _notes.value.map { it.toJson() }) }
    var onChange: (() -> Unit)? = null

    fun load() { _notes.value = AppFiles.readArray("pufy-notes.json").mapNotNull(Note::fromJson) }
    val sorted get() = _notes.value.sortedByDescending { it.updatedAt }
    fun note(id: String?) = _notes.value.firstOrNull { it.id == id }

    fun upsert(note: Note, notify: Boolean = true) {
        _notes.update { list -> if (list.any { it.id == note.id }) list.map { if (it.id == note.id) note else it } else list + note }
        saver.schedule(); if (notify) onChange?.invoke()
    }
    fun delete(id: String) { _notes.update { it.filter { n -> n.id != id } }; saver.schedule(); onChange?.invoke() }
    fun toggle(id: String, lineIndex: Int) {
        val note = note(id) ?: return
        val lines = note.content.lines().toMutableList()
        if (lineIndex !in lines.indices) return
        val item = NoteLine.checkItem(lines[lineIndex].trim()) ?: return
        lines[lineIndex] = "- [${if (item.first) " " else "x"}] ${item.second}"
        upsert(note.copy(content = lines.joinToString("\n"), updatedAt = nowSwift()))
    }
    fun applyRemote(note: Note) = upsert(note, notify = false)
    fun applyRemoteDeletion(id: String) { _notes.update { it.filter { n -> n.id != id } }; saver.schedule() }
    fun clearAll() { _notes.value = emptyList(); AppFiles.writeArray("pufy-notes.json", emptyList()); saver.now() }

    /** Yapay zekaya verilen notlar (içerikleriyle) — iOS NoteStore.promptText */
    fun promptText(): String {
        if (_notes.value.isEmpty()) return "Henüz not yok."
        var budget = 9000
        return sorted.joinToString("\n") { n ->
            val body = if (n.content.length > 1500) n.content.take(1500) + "\n…(devamı var)" else n.content
            val entry = "- ID: ${n.id} | Başlık: \"${n.title}\"\n" + body.lines().joinToString("\n") { "    $it" }
            budget -= entry.length
            if (budget < 0) "- ID: ${n.id} | Başlık: \"${n.title}\" (içerik uzun, gösterilmedi)" else entry
        }
    }
    fun titlesText(): String = if (_notes.value.isEmpty()) "henüz not yok." else sorted.take(30).joinToString(", ") { "\"${it.title}\" (ID: ${it.id})" }
}

// MARK: - Hatırlatıcılar ve görevler

data class Reminder(
    val id: String = newID(),
    val title: String,
    val note: String = "",
    val dateMillis: Long,
    val repeat: String = "none",
    val isActive: Boolean = true,
    val aiTaskPrompt: String = "",
    val timerSeconds: Int? = null,
    val taskDone: Boolean? = null,
    val taskSessionID: String? = null,
    val taskIntervalMinutes: Int? = null,
    val taskUntilMillis: Long? = null,
    val taskInbox: List<String> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
) {
    val isAITask get() = aiTaskPrompt.isNotEmpty()
    val isTimer get() = timerSeconds != null
    val isRepeatingTask get() = isAITask && (repeat != "none" || taskIntervalMinutes != null)

    /** Süresi geçti mi? (iOS Reminder.isExpired) */
    fun isExpired(now: Long = System.currentTimeMillis()): Boolean {
        if (isAITask) {
            if (taskDone == true) return true
            if (taskUntilMillis != null && taskUntilMillis <= now) return true
            if (!isRepeatingTask) return dateMillis + 6 * 3600_000 <= now
            return false
        }
        return repeat == "none" && dateMillis <= now
    }

    fun toJson() = buildJsonObject {
        put("id", id); put("title", title); put("note", note); put("dateMillis", dateMillis); put("repeat", repeat)
        put("isActive", isActive); put("aiTaskPrompt", aiTaskPrompt); timerSeconds?.let { put("timerSeconds", it) }
        taskDone?.let { put("taskDone", it) }; taskSessionID?.let { put("taskSessionID", it) }
        taskIntervalMinutes?.let { put("taskIntervalMinutes", it) }; taskUntilMillis?.let { put("taskUntilMillis", it) }
        put("taskInbox", JsonArray(taskInbox.map(::JsonPrimitive))); put("createdAt", createdAt)
    }

    companion object {
        fun fromJson(o: JsonObject) = Reminder(
            id = o.str("id") ?: newID(), title = o.str("title") ?: "", note = o.str("note") ?: "",
            dateMillis = o.num("dateMillis")?.toLong() ?: 0, repeat = o.str("repeat") ?: "none", isActive = o.bool("isActive") ?: true,
            aiTaskPrompt = o.str("aiTaskPrompt") ?: "", timerSeconds = o.int("timerSeconds"), taskDone = o.bool("taskDone"),
            taskSessionID = o.str("taskSessionID"), taskIntervalMinutes = o.int("taskIntervalMinutes"),
            taskUntilMillis = o.num("taskUntilMillis")?.toLong(), taskInbox = o.strings("taskInbox"),
            createdAt = o.num("createdAt")?.toLong() ?: System.currentTimeMillis(),
        )
    }
}

object ReminderStore {
    private val _reminders = MutableStateFlow<List<Reminder>>(emptyList())
    val reminders: StateFlow<List<Reminder>> = _reminders.asStateFlow()
    private val saver = Debouncer { AppFiles.writeArray("reminders.json", _reminders.value.map { it.toJson() }) }
    var onChange: (() -> Unit)? = null
    /** Bildirim kurma / kaldırma (Android tarafı: ReminderScheduler) */
    var scheduler: ((Reminder?, String) -> Unit)? = null

    fun load() { _reminders.value = AppFiles.readArray("reminders.json").map(Reminder::fromJson) }
    val visible get() = _reminders.value.filter { !it.isExpired() }.sortedBy { it.dateMillis }
    fun reminder(id: String) = _reminders.value.firstOrNull { it.id == id }

    fun upsert(r: Reminder, notify: Boolean = true) {
        _reminders.update { list -> if (list.any { it.id == r.id }) list.map { if (it.id == r.id) r else it } else list + r }
        saver.schedule(); scheduler?.invoke(r, r.id); if (notify) onChange?.invoke()
    }
    fun delete(id: String, notify: Boolean = true) {
        _reminders.update { it.filter { r -> r.id != id } }
        saver.schedule(); scheduler?.invoke(null, id); if (notify) onChange?.invoke()
    }
    fun update(id: String, block: (Reminder) -> Reminder) { reminder(id)?.let { upsert(block(it)) } }
    fun cleanExpired() { val expired = _reminders.value.filter { it.isExpired() }; if (expired.isNotEmpty()) { expired.forEach { delete(it.id, notify = false) }; onChange?.invoke() } }

    fun applyRemoteReminder(id: String, o: JsonObject) {
        val date = o.num("date") ?: return
        val r = (reminder(id) ?: Reminder(id = id, title = "", dateMillis = 0)).copy(
            title = o.str("title") ?: "", note = o.str("note") ?: "", dateMillis = (date * 1000).toLong(),
            repeat = o.str("repeat") ?: "none", isActive = o.bool("active") ?: true)
        if (r.isExpired()) return
        upsert(r, notify = false)
    }

    fun applyRemoteTask(id: String, o: JsonObject) {
        val existing = reminder(id)
        val r = (existing ?: Reminder(id = id, title = "", dateMillis = 0)).copy(
            title = o.str("title") ?: "", aiTaskPrompt = o.str("prompt") ?: "", dateMillis = ((o.num("date") ?: 0.0) * 1000).toLong(),
            repeat = o.str("repeat") ?: "none", isActive = o.bool("active") ?: true, taskIntervalMinutes = o.int("everyMinutes"),
            taskUntilMillis = o.num("until")?.let { (it * 1000).toLong() })
        upsert(r, notify = false)
    }

    fun applyRemoteDeletion(id: String) = delete(id, notify = false)

    fun clearAll() {
        _reminders.value.forEach { scheduler?.invoke(null, it.id) }
        _reminders.value = emptyList()
        AppFiles.writeArray("reminders.json", emptyList())
        saver.now()
    }

    /** Yapay zekaya verilen aktif hatırlatıcı listesi */
    fun promptText(): String {
        val list = visible.filter { !it.isTimer }
        if (list.isEmpty()) return "Şu an aktif bekleyen hatırlatıcı yok."
        return list.joinToString("\n") { r ->
            "- ID: ${r.id} | Başlık: \"${r.title}\" | Tarih: ${com.pufy.app.core.turkeyISO(r.dateMillis)} | Tekrar: ${r.repeat} | Not: \"${if (r.isAITask) "AI görevi: " + r.aiTaskPrompt else r.note}\""
        }
    }
}

// MARK: - Mini uygulamalar

object MiniAppStore {
    private val _apps = MutableStateFlow<List<MiniApp>>(emptyList())
    val apps: StateFlow<List<MiniApp>> = _apps.asStateFlow()
    private val saver = Debouncer { AppFiles.writeArray("miniapps.json", _apps.value.map { it.raw }) }
    var onChange: (() -> Unit)? = null

    fun load() { _apps.value = AppFiles.readArray("miniapps.json").map(::MiniApp) }
    fun app(id: String) = _apps.value.firstOrNull { it.id == id }
    fun folder(app: MiniApp) = app.folderName?.let { File(AppFiles.miniApps, it) }
    fun hasFiles(app: MiniApp) = folder(app)?.let { File(it, "index.html").exists() } == true

    /** pufy.storage değişti → uygulama verisi de eşitlensin */
    fun dataChanged(@Suppress("UNUSED_PARAMETER") folder: String) { onChange?.invoke() }

    fun upsert(app: MiniApp, notify: Boolean = true) {
        _apps.update { list -> if (list.any { it.id == app.id }) list.map { if (it.id == app.id) app else it } else list + app }
        saver.schedule(); if (notify) onChange?.invoke()
    }
    fun delete(id: String, notify: Boolean = true) {
        val app = app(id)
        _apps.update { it.filter { a -> a.id != id } }
        app?.folderName?.let { f ->
            com.pufy.app.apps.MiniAppFiles.deleteAll(f)          // dosyalar + sürümler + kaydettiği veriler
            com.pufy.app.notify.Notifier.cancelApp("pufyapp.$f.", null)
        }
        saver.schedule(); if (notify) onChange?.invoke()
    }
}

/** Uygulama açılışında tüm depoları yükler */
object Stores {
    fun load() { ChatStore.load(); MemoryStore.load(); NoteStore.load(); ReminderStore.load(); MiniAppStore.load() }
    fun millis(swift: Double) = swiftToEpochMillis(swift)
}
