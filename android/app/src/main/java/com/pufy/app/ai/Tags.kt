package com.pufy.app.ai

import com.pufy.app.core.PufyJson
import com.pufy.app.core.TR
import com.pufy.app.core.arr
import com.pufy.app.core.bool
import com.pufy.app.core.newID
import com.pufy.app.core.nowSwift
import com.pufy.app.core.num
import com.pufy.app.core.obj
import com.pufy.app.core.parseJsonObject
import com.pufy.app.core.parseTurkeyISO
import com.pufy.app.core.str
import com.pufy.app.core.strings
import com.pufy.app.core.turkeyFormat
import com.pufy.app.data.Note
import com.pufy.app.data.NoteLine
import com.pufy.app.data.NoteStore
import com.pufy.app.data.Reminder
import com.pufy.app.data.ReminderStore
import com.pufy.app.data.WebSource
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import java.text.Normalizer

/** Cevaptaki etiketler (iOS ChatViewModel.applyAgentActions + extractRichTags + NoteStore.applyTags + ChatWidgets.JSONTag) */
object Tags {

    // MARK: [NAME: {json}] — süslü parantez sayarak (içerikte "- [ ] madde" gibi köşeli parantezler olabilir)

    /** Etiketleri çıkarır; yarım kalan (akış sırasında) etiket sona kadar silinir */
    fun extractJson(name: String, input: String): Pair<String, List<JsonObject>> {
        var text = input
        val found = mutableListOf<JsonObject>()
        val pattern = Regex("\\[" + Regex.escape(name) + "\\s*:\\s*", RegexOption.IGNORE_CASE)
        while (true) {
            val start = pattern.find(text) ?: break
            // "[NOTE:" kalıbı "[DELETE_NOTE:" ile eşleşmesin
            if (name == "NOTE" && start.range.first > 0 && text[start.range.first - 1].isLetter()) break
            val brace = text.indexOf('{', start.range.last + 1)
            if (brace < 0) { text = text.substring(0, start.range.first); break }
            var depth = 0; var inString = false; var escaped = false; var end = -1
            var i = brace
            while (i < text.length) {
                val c = text[i]
                if (inString) { if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') inString = false }
                else if (c == '"') inString = true
                else if (c == '{') depth++
                else if (c == '}') { depth--; if (depth == 0) { end = i; break } }
                i++
            }
            if (end < 0) { text = text.substring(0, start.range.first); break }
            parseJsonObject(text.substring(brace, end + 1))?.let(found::add)
            var tail = end + 1
            while (tail < text.length && (text[tail] == ' ' || text[tail] == ']')) tail++
            text = text.removeRange(start.range.first, tail)
        }
        return text to found
    }

    // MARK: Zengin etiketler

    class Rich(
        val text: String,
        val followUp: String? = null,
        val sources: List<WebSource> = emptyList(),
        val imageTopics: List<String> = emptyList(),
        val choices: JsonObject? = null,
        val widgets: List<JsonObject> = emptyList(),
        val compare: JsonObject? = null,
        val quiz: JsonObject? = null,
        val actions: List<String> = emptyList(),
        val slidesTitle: String? = null,
        val appRequest: com.pufy.app.data.AppRequestData? = null,
    )

    fun extractRich(input: String): Rich {
        var (text, widgets) = extractJson("WIDGET", input)
        widgets = widgets.filter { (it.str("type") == "match" && it.obj("home") != null && it.obj("away") != null) || it.str("name") != null }
        var compare: JsonObject? = null
        if (text.contains("[COMPARE", true)) {
            val (t, list) = extractJson("COMPARE", text); text = t
            compare = list.firstOrNull()?.takeIf { (it.arr("items")?.size ?: 0) in 2..4 && !(it.arr("rows").isNullOrEmpty()) }
        }
        var quiz: JsonObject? = null
        if (text.contains("[QUIZ", true)) {
            val (t, list) = extractJson("QUIZ", text); text = t
            quiz = list.firstOrNull()?.takeIf { q -> q.arr("questions")?.all { (it as? JsonObject)?.arr("options")?.size?.let { s -> s >= 2 } == true } == true }
        }
        var appRequest: com.pufy.app.data.AppRequestData? = null
        if (text.contains("[UYGULAMA_YAP", true)) {
            val (t, list) = extractJson("UYGULAMA_YAP", text); text = t
            list.firstOrNull()?.let {
                val n = it.str("name") ?: ""
                val p = it.str("prompt") ?: ""
                if (n.isNotEmpty() || p.isNotEmpty()) appRequest = com.pufy.app.data.AppRequestData(n, p)
            }
        }
        fun takeSimple(name: String): String? {
            val m = Regex("\\[$name\\s*:\\s*([^\\]]*)]", RegexOption.IGNORE_CASE).find(text) ?: return null
            text = text.removeRange(m.range)
            return m.groupValues[1].trim()
        }
        val next = takeSimple("NEXT")?.trim('"', '\'')?.takeIf { it.isNotEmpty() && it.length <= 90 }
        val sources = takeSimple("SOURCES")?.split("|")?.mapNotNull { raw ->
            var item = raw.trim()
            if (item.isEmpty()) return@mapNotNull null
            if (!item.lowercase().startsWith("http")) item = "https://$item"
            val host = runCatching { java.net.URI(item).host }.getOrNull() ?: return@mapNotNull null
            WebSource(host.removePrefix("www."), item)
        } ?: emptyList()
        val actions = takeSimple("ACTIONS")?.split("|")?.map { it.trim().trim('"', '\'') }?.filter { it.isNotEmpty() && it.length <= 40 }?.take(3) ?: emptyList()
        var slides = takeSimple("SLIDES")?.trim('"', '\'')?.let { if (it.isEmpty()) "Sunum" else it.take(80) }
        if (slides == null && compare != null && (compare.arr("rows")?.size ?: 0) >= 4) {
            slides = compare.arr("items")?.mapNotNull { (it as? JsonObject)?.str("name") }?.joinToString(" vs ")
        }
        val images = takeSimple("IMAGES")?.split("|")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
        var choices: JsonObject? = null
        if (text.contains("[CHOICES", true)) {
            val (t, list) = extractJson("CHOICES", text); text = t
            choices = list.firstOrNull()?.let { c ->
                if (c.arr("questions") != null) c.takeIf { !it.arr("questions").isNullOrEmpty() }
                else if (c.str("q") != null) JsonObject(mapOf("questions" to JsonArray(listOf(c)))) else null
            }
        }
        return Rich(text.trim(), next, sources, images, choices, widgets, compare, quiz, actions, slides, appRequest)
    }

    // MARK: Notlar

    data class NoteResult(val text: String, val badges: List<String>, val noteID: String?)

    private fun normalize(s: String) = Normalizer.normalize(s.lowercase(TR), Normalizer.Form.NFD).replace(Regex("\\p{M}"), "")
        .split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString(" ")
    private fun plain(line: String) = NoteLine.checkItem(line.trim())?.second ?: line.trim().removePrefix("- ").removePrefix("* ").removePrefix("• ")

    fun applyNotes(input: String): NoteResult {
        var (text, deletes) = extractJson("DELETE_NOTE", input)
        val badges = mutableListOf<String>()
        var lastID: String? = null
        for (o in deletes) {
            val note = NoteStore.note(o.str("id")) ?: continue
            NoteStore.delete(note.id); badges.add("Not silindi: ${note.title}")
        }
        val (rest, notes) = extractJson("NOTE", text); text = rest
        for (o in notes) applyNote(o)?.let { (id, badge) -> lastID = id; badges.add(badge) }
        return NoteResult(text, badges, lastID)
    }

    private fun applyNote(o: JsonObject): Pair<String, String>? {
        val title = o.str("title")?.trim()
        var note = NoteStore.note(o.str("id"))
        if (note == null && !title.isNullOrEmpty()) note = NoteStore.notes.value.firstOrNull { normalize(it.title) == normalize(title) }
        if (note == null) {
            if (title.isNullOrEmpty()) return null
            val created = Note(title = title, content = (o.str("content") ?: o.str("append") ?: "").trim('\n'))
            NoteStore.upsert(created)
            return created.id to "Not alındı: ${created.title}"
        }
        var n: Note = note
        if (!title.isNullOrEmpty() && (o.bool("rename") == true || o.str("content") != null)) n = n.copy(title = title)
        o.str("content")?.let { n = n.copy(content = it.trim('\n')) }
        o.str("append")?.let { append ->
            val existing = n.content.lines().map { normalize(plain(it)) }.toSet()
            val fresh = append.lines().filter { val k = normalize(plain(it)); k.isNotEmpty() && k !in existing }
            if (fresh.isNotEmpty()) n = n.copy(content = n.content.trim('\n') + (if (n.content.isEmpty()) "" else "\n") + fresh.joinToString("\n"))
        }
        fun matches(line: String, targets: List<String>): Boolean {
            val key = normalize(plain(line))
            return targets.any { val t = normalize(it); t.isNotEmpty() && (key == t || key.contains(t)) }
        }
        o.arr("check")?.let { o.strings("check") }?.let { targets ->
            n = n.copy(content = n.content.lines().joinToString("\n") { line ->
                val item = NoteLine.checkItem(line.trim()); if (item != null && !item.first && matches(line, targets)) "- [x] ${item.second}" else line })
        }
        o.arr("uncheck")?.let { o.strings("uncheck") }?.let { targets ->
            n = n.copy(content = n.content.lines().joinToString("\n") { line ->
                val item = NoteLine.checkItem(line.trim()); if (item != null && item.first && matches(line, targets)) "- [ ] ${item.second}" else line })
        }
        o.arr("remove")?.let { o.strings("remove") }?.let { targets -> n = n.copy(content = n.content.lines().filterNot { matches(it, targets) }.joinToString("\n")) }
        NoteStore.upsert(n.copy(updatedAt = nowSwift()))
        return n.id to "Not güncellendi: ${n.title}"
    }

    // MARK: Hatırlatıcı, zamanlayıcı, görev

    data class ActionResult(val text: String, val badges: List<String>, val steps: List<String>)

    private fun regexTag(name: String) = Regex("\\[$name\\s*:\\s*(\\{.+?\\})\\s*]", RegexOption.DOT_MATCHES_ALL)

    fun parseDate(text: String?): Long? = text?.let { parseTurkeyISO(it) }

    fun dateText(millis: Long) = turkeyFormat(millis, "d MMM HH:mm")

    fun timerTitle(r: Reminder): String {
        val s = r.timerSeconds ?: 0
        val dur = if (s >= 3600) "${s / 3600} sa ${(s % 3600) / 60} dk".replace(" 0 dk", "") else if (s >= 60) "${s / 60} dk" + (if (s % 60 > 0) " ${s % 60} sn" else "") else "$s sn"
        return if (r.title.isBlank() || r.title == "Zamanlayıcı") "Zamanlayıcı · $dur" else "${r.title} · $dur"
    }

    fun applyReminders(input: String, onTaskSession: (Reminder) -> Unit = {}): ActionResult {
        var text = input
        val badges = mutableListOf<String>(); val steps = mutableListOf<String>()
        while (true) {
            val m = regexTag("REMINDER").find(text) ?: break
            text = text.removeRange(m.range).trim()
            val o = parseJsonObject(m.groupValues[1]) ?: continue
            val date = parseDate(o.str("datetime")) ?: continue
            val r = Reminder(title = o.str("title") ?: "Hatırlatıcı", note = o.str("note") ?: "", dateMillis = date, repeat = o.str("repeat") ?: "none")
            ReminderStore.upsert(r); badges.add(r.title); steps.add("Hatırlatıcı kuruldu: ${r.title} (${dateText(r.dateMillis)})")
        }
        while (true) {
            val m = Regex("\\[TIMER\\s*:\\s*(\\{[^\\]]*\\})\\s*]", RegexOption.IGNORE_CASE).find(text) ?: break
            text = text.removeRange(m.range)
            val o = parseJsonObject(m.groupValues[1]) ?: continue
            val seconds = (o["seconds"] as? JsonPrimitive)?.let { it.intOrNull ?: it.content.toDoubleOrNull()?.toInt() } ?: continue
            if (seconds !in 5..86400) continue
            val r = Reminder(title = o.str("title") ?: "Zamanlayıcı", dateMillis = System.currentTimeMillis() + seconds * 1000L, timerSeconds = seconds)
            ReminderStore.upsert(r); badges.add(timerTitle(r)); steps.add("Zamanlayıcı kuruldu: ${timerTitle(r)}")
        }
        while (true) {
            val m = regexTag("AI_TASK").find(text) ?: break
            text = text.removeRange(m.range).trim()
            val o = parseJsonObject(m.groupValues[1]) ?: continue
            val date = parseDate(o.str("datetime")) ?: (System.currentTimeMillis() + 3600_000)
            val every = (o["every_minutes"] as? JsonPrimitive)?.intOrNull?.coerceAtLeast(2)
            val r = Reminder(title = o.str("title") ?: "AI Görevi", dateMillis = date, repeat = o.str("repeat") ?: "none",
                aiTaskPrompt = o.str("prompt") ?: "", taskIntervalMinutes = every, taskUntilMillis = parseDate(o.str("until")))
            ReminderStore.upsert(r); onTaskSession(r); badges.add(r.title); steps.add("AI görevi planlandı: ${r.title} (${dateText(r.dateMillis)})")
        }
        while (true) {
            val m = regexTag("DELETE_REMINDER").find(text) ?: break
            text = text.removeRange(m.range).trim()
            val id = parseJsonObject(m.groupValues[1])?.str("id") ?: continue
            ReminderStore.reminder(id)?.let { ReminderStore.delete(id); badges.add("Silindi: ${it.title}") }
        }
        while (true) {
            val m = regexTag("UPDATE_REMINDER").find(text) ?: break
            text = text.removeRange(m.range).trim()
            val o = parseJsonObject(m.groupValues[1]) ?: continue
            val r = ReminderStore.reminder(o.str("id") ?: continue) ?: continue
            val updated = r.copy(title = o.str("title") ?: r.title, note = o.str("note") ?: r.note,
                dateMillis = parseDate(o.str("datetime")) ?: r.dateMillis, repeat = o.str("repeat") ?: r.repeat)
            ReminderStore.upsert(updated); badges.add("Güncellendi: ${updated.title}")
        }
        return ActionResult(text, badges, steps)
    }

    /** Kalan (bozuk/yarım) etiketler */
    private val cleanRegexes = listOf(
        "\\[THINK\\s*:[^\\]]*(?:]|$)", "\\[SEARCH\\s*:[^\\]]*(?:]|$)", "\\[REMINDER\\s*:[^\\]]*(?:]|$)",
        "\\[DELETE_REMINDER\\s*:[^\\]]*(?:]|$)", "\\[UPDATE_REMINDER\\s*:[^\\]]*(?:]|$)", "\\[AI_TASK\\s*:[^\\]]*(?:]|$)",
        "\\[TIMER\\s*:[^\\]]*(?:]|$)", "\\[(?:NOTE|DELETE_NOTE)\\s*:\\s*\\{[\\s\\S]*?\\}\\s*]",
        "\\[(?:NEXT|SOURCES|IMAGES|DRAW|SLIDES|ACTIONS|UYGULAMA_YAP)\\s*:[^\\]]*(?:]|$)",
    ).map { Regex(it, RegexOption.DOT_MATCHES_ALL) }

    fun cleanLeftovers(text: String): String = cleanRegexes.fold(text) { t, r -> r.replace(t, "") }.trim()

    /** Akış sırasında ekranda gösterilecek metin: yarım etiketler gizlenir (iOS MessageRowView.cleanContent) */
    private val streamHide = listOf(
        "!\\[[^\\]]*]\\([^)]*\\)",
        "\\[(?:THINK|SEARCH|REMINDER|DELETE_REMINDER|UPDATE_REMINDER|AI_TASK|TIMER|NEXT|SOURCES|IMAGES|DRAW|SLIDES|ACTIONS|UYGULAMA_YAP)\\s*:[^\\]]*(?:]|$)",
        "\\[(?:NOTE|DELETE_NOTE)\\s*:\\s*\\{[\\s\\S]*?\\}\\s*]", "\\[(?:NOTE|DELETE_NOTE)\\s*:[\\s\\S]*$", "\\[CHOICES[\\s\\S]*$",
    ).map { Regex(it) }

    fun displayText(content: String): String {
        var source = content
        for (name in listOf("WIDGET", "COMPARE", "QUIZ", "UYGULAMA_YAP")) if (source.contains("[$name")) source = extractJson(name, source).first
        return streamHide.fold(source) { t, r -> r.replace(t, "") }.trim()
    }

    fun imageURLs(content: String): List<String> =
        if (!content.contains("![")) emptyList() else Regex("!\\[[^\\]]*]\\(([^)]*)\\)").findAll(content).map { it.groupValues[1] }.toList()

    @Suppress("unused") private val json = PufyJson
    @Suppress("unused") private fun JsonObject.n(k: String) = num(k)
    @Suppress("unused") private fun id() = newID()
    @Suppress("unused") private fun JsonPrimitive.i() = int
}
