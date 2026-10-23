package com.pufy.app.ai

import com.pufy.app.core.TR
import com.pufy.app.core.Settings
import com.pufy.app.core.nowSwift
import com.pufy.app.core.swiftToEpochMillis
import com.pufy.app.core.turkeyFormat
import com.pufy.app.core.turkeyISO
import com.pufy.app.data.AppFiles
import com.pufy.app.data.ChatSession
import com.pufy.app.data.ChatStore
import com.pufy.app.data.FileAttachment
import com.pufy.app.data.MemoryStore
import com.pufy.app.data.Message
import com.pufy.app.data.NoteStore
import com.pufy.app.data.Profile
import com.pufy.app.data.ReminderStore
import com.pufy.app.data.WebSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import java.io.File
import java.time.ZoneId

/**
 * Sohbet beyni — iOS ChatViewModel'in karşılığı: yönergeyi kurar, cevabı akışla yazar, etiketleri uygular
 * (not, hatırlatıcı, zamanlayıcı, görev, kartlar, butonlar), sohbete başlık verir.
 */
object ChatEngine {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + com.pufy.app.core.SafeErrors)

    private val _current = MutableStateFlow<String?>(null)
    val currentSessionID: StateFlow<String?> = _current.asStateFlow()
    private val _generating = MutableStateFlow<String?>(null)
    /** Cevabı yazılan mesajın kimliği (yoksa null) */
    val generatingMessageID: StateFlow<String?> = _generating.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    /** Seçenekli sorular (yazma çubuğunun üstünde) — mesaj kimliği */
    val pendingChoicesFor = MutableStateFlow<String?>(null)

    private var job: Job? = null
    private var generatingSessionID: String? = null

    val isGenerating get() = _generating.value != null

    fun clearError() { _error.value = null }
    fun reportError(message: String) { _error.value = message }

    // MARK: Oturumlar

    fun newSession() {
        stopIfOtherSession(null)
        val empty = ChatStore.sessions.value.firstOrNull { it.messages.isEmpty() && !it.isSpaceChat }
        if (empty != null) { _current.value = empty.id; return }
        val session = ChatSession(title = ChatSession.DEFAULT_TITLE)
        ChatStore.upsert(session, notify = false)
        _current.value = session.id
    }

    fun open(sessionID: String) { _current.value = sessionID; pendingChoicesFor.value = null }

    private fun stopIfOtherSession(id: String?) { if (generatingSessionID != null && generatingSessionID != id) Unit }

    val currentSession: ChatSession? get() = ChatStore.session(_current.value)

    // MARK: Gönder

    fun formatPromptWithFiles(text: String, files: List<FileAttachment>): String {
        if (files.isEmpty()) return text
        val parts = mutableListOf<String>()
        for (file in files) {
            var header = "DOSYA: ${file.name}"
            val tags = mutableListOf<String>()
            if (file.kind == "pdf" && file.pageCount != null && file.pageCount > 0) {
                tags.add("${file.pageCount} sayfa")
            }
            if (file.truncated) {
                tags.add("metin kısaltıldı")
            }
            if (tags.isNotEmpty()) {
                header += " — " + tags.joinToString(", ")
            }
            parts.add("[$header]\n${file.text}\n[/DOSYA]")
        }
        return if (text.isEmpty()) {
            parts.joinToString("\n\n")
        } else {
            parts.joinToString("\n\n") + "\n\n" + text
        }
    }

    fun send(
        text: String,
        images: List<ByteArray> = emptyList(),
        files: List<FileAttachment> = emptyList(),
        forceSearch: Boolean = false,
        reminderMode: Boolean = false,
        isVoice: Boolean = false,
        forceDeep: Boolean = false,
    ) {
        var prompt = text.trim()
        if (prompt.isEmpty() && files.isNotEmpty()) {
            prompt = if (com.pufy.app.core.AppLocales.isEnglish()) "Summarize this file." else "Bu dosyayı özetle."
        }
        if (prompt.isEmpty() && images.isEmpty() && files.isEmpty()) return
        if (isGenerating) return
        if (_current.value == null || ChatStore.session(_current.value) == null) newSession()
        val sessionID = _current.value ?: return
        val names = images.map { saveImage(it) }
        val user = Message(content = prompt, role = "user", syncImages = names, isVoiceInitiated = isVoice, files = files.takeIf { it.isNotEmpty() })
        // Geçmiş, yeni mesaj eklenmeden önceki hâlden: yeni mesaj istekte ayrıca (dosyalarıyla) gidiyor
        val history = apiHistory(ChatStore.session(sessionID)?.messages ?: emptyList())
        ChatStore.mutate(sessionID) { it.copy(messages = it.messages + user) }
        ChatStore.moveToTop(sessionID)
        pendingChoicesFor.value = null
        val fullPrompt = formatPromptWithFiles(prompt, files)
        run(sessionID, fullPrompt, userPrompt = prompt, images, history, reminderMode, forceSearch, isVoice, forceDeep, hasFiles = files.isNotEmpty())
    }

    /** Son cevabı aynı soruyla yeniden üret (↻) */
    fun regenerate() {
        if (isGenerating) return
        val session = currentSession ?: return
        val lastUserIndex = session.messages.indexOfLast { it.isUser }
        if (lastUserIndex < 0) return
        val user = session.messages[lastUserIndex]
        val files = user.files ?: emptyList()
        val history = apiHistory(session.messages.subList(0, lastUserIndex))
        ChatStore.mutate(session.id) { it.copy(messages = it.messages.subList(0, lastUserIndex + 1)) }
        val images = user.syncImages.mapNotNull { File(AppFiles.syncImages, it).takeIf { f -> f.exists() }?.readBytes() }
        val fullPrompt = formatPromptWithFiles(user.content, files)
        run(session.id, fullPrompt, userPrompt = user.content, images, history, false, false, false, false, hasFiles = files.isNotEmpty())
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private fun saveImage(data: ByteArray): String {
        val name = com.pufy.app.core.sha256Hex(data).take(32) + ".jpg"
        File(AppFiles.syncImages, name).takeIf { !it.exists() }?.writeBytes(data)
        return name
    }

    private fun apiTurnContent(m: Message, isLastUserMessage: Boolean): String {
        val base = Tags.displayText(m.content).ifEmpty { m.content }
        val files = m.files ?: return base
        if (files.isEmpty()) return base
        val effectiveFiles = if (isLastUserMessage) files else files.map { f ->
            if (f.text.length > 8000) {
                f.copy(text = f.text.take(8000), truncated = true)
            } else f
        }
        return formatPromptWithFiles(base, effectiveFiles)
    }

    /** API'ye gidecek geçmiş: hata/iptal mesajları ve boş balonlar ayıklanır, son 7 mesaj */
    private fun apiHistory(messages: List<Message>): List<AiTurn> {
        val filtered = messages.filter {
            it.content.isNotEmpty() && !it.content.startsWith("Hata oluştu:") && !it.content.startsWith("İptal edildi.")
        }.takeLast(7)
        val lastUserIdx = filtered.indexOfLast { it.isUser }
        return filtered.mapIndexed { idx, m ->
            val isLastUser = (idx == lastUserIdx)
            AiTurn(
                role = if (m.isUser) "user" else "model",
                text = apiTurnContent(m, isLastUser),
                images = m.syncImages.mapNotNull { File(AppFiles.syncImages, it).takeIf { f -> f.exists() }?.readBytes() }
            )
        }
    }

    private fun run(
        sessionID: String,
        prompt: String,
        userPrompt: String,
        images: List<ByteArray>,
        history: List<AiTurn>,
        reminderMode: Boolean,
        forceSearch: Boolean,
        isVoice: Boolean,
        forceDeep: Boolean = false,
        hasFiles: Boolean = false,
    ) {
        val model = Message(content = "", role = "model", isVoiceInitiated = isVoice, isSearching = true)
        ChatStore.mutate(sessionID, notify = false) { it.copy(messages = it.messages + model) }
        generatingSessionID = sessionID
        _generating.value = model.id
        val isSpaceChat = ChatStore.session(sessionID)?.isSpaceChat ?: false
        ResearchEngine.lastAnswerWasSearched = !(ChatStore.session(sessionID)?.messages?.lastOrNull { !it.isUser && it.id != model.id }?.sources.isNullOrEmpty())

        job = scope.launch {
            try {
                val lastUser = history.lastOrNull { it.role == "user" }?.text ?: ""
                val recent = history.takeLast(2).joinToString(" ") { it.text }
                val system = withContext(Dispatchers.Default) {
                    buildSystemPrompt(reminderMode, isSpaceChat, userPrompt + " " + recent.takeLast(600), sessionID, userPrompt + " " + lastUser.take(300))
                }
                val response = ResearchEngine.execute(prompt, history, images, system, forceSearch, ResearchEngine.Callbacks(
                    progress = { step -> ChatStore.mutateMessage(sessionID, model.id) { m -> m.copy(thinkingSteps = m.thinkingSteps + step) } },
                    partial = { text, reasoning ->
                        ChatStore.mutateMessage(sessionID, model.id) { m ->
                            m.copy(content = text, reasoning = reasoning.ifEmpty { m.reasoning }, isSearching = false)
                        }
                    },
                    sources = { list -> ChatStore.mutateMessage(sessionID, model.id) { m -> m.copy(sources = list.map { WebSource(it.first, it.second) }) } },
                ), forceDeep = forceDeep, hasFiles = hasFiles)
                val final = applyAgentActions(response, sessionID, model.id)
                ChatStore.mutate(sessionID) { s -> s.copy(messages = s.messages.map { if (it.id == model.id) it.copy(content = final, isSearching = false) else it }) }
                titleIfNeeded(sessionID, userPrompt, images.isNotEmpty())
                ChatStore.session(sessionID)?.messages?.firstOrNull { it.id == model.id }?.takeIf { it.choices != null }?.let { pendingChoicesFor.value = it.id }
                MemoryLearner.learn(userPrompt, history.lastOrNull { it.role != "user" }?.text)
            } catch (e: CancellationException) {
                ChatStore.mutate(sessionID) { s ->
                    s.copy(messages = s.messages.map { m ->
                        if (m.id != model.id) m else m.copy(content = Tags.cleanLeftovers(m.content).ifEmpty { "İptal edildi." }, isSearching = false)
                    })
                }
            } catch (e: Throwable) {
                // Error dahil her şey yakalanır: bir hata asla uygulamayı kapatmaz, mesajda gösterilir
                android.util.Log.e("Pufy", "Cevap hatası", e)
                val message = (if (e is Exception) AiClient.friendly(e).message else null) ?: "Beklenmeyen hata (${e.javaClass.simpleName})"
                ChatStore.mutate(sessionID) { s ->
                    s.copy(messages = s.messages.map { m -> if (m.id != model.id) m else m.copy(content = "Hata oluştu: $message", isSearching = false) })
                }
                _error.value = message
            } finally {
                _generating.value = null
                generatingSessionID = null
                job = null
                ChatStore.flush()
            }
        }
    }

    // MARK: Etiketler

    private fun applyAgentActions(response: String, sessionID: String, messageID: String): String {
        var text = response
        val notes = Tags.applyNotes(text)
        text = notes.text
        val actions = Tags.applyReminders(text) { task -> ensureTaskSession(task.id, task.title, task.aiTaskPrompt) }
        text = actions.text
        val rich = Tags.extractRich(text)
        text = rich.text

        // Sunum son ve tam cevapta: soru soran (CHOICES) cevapta ertelenir (iOS ile aynı kural)
        var slidesTitle = rich.slidesTitle
        var pendingDeck: String? = null
        val previousPending = ChatStore.session(sessionID)?.messages?.let { msgs ->
            val i = msgs.indexOfFirst { it.id == messageID }
            msgs.take(maxOf(i, 0)).lastOrNull { !it.isUser }?.pendingDeckTitle
        }
        if (rich.choices != null) { pendingDeck = slidesTitle ?: previousPending; slidesTitle = null }
        else if (slidesTitle == null && previousPending != null) { if (text.length >= 900) slidesTitle = previousPending else pendingDeck = previousPending }

        ChatStore.mutateMessage(sessionID, messageID, notify = true) { m ->
            m.copy(
                noteTitle = notes.badges.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: m.noteTitle,
                noteID = notes.noteID ?: m.noteID,
                reminderTitle = actions.badges.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: m.reminderTitle,
                thinkingSteps = m.thinkingSteps + actions.steps,
                choices = rich.choices ?: m.choices,
                widgets = rich.widgets.takeIf { it.isNotEmpty() }?.let { JsonArray(it.take(3)) } ?: m.widgets,
                imageTopics = rich.imageTopics.takeIf { it.isNotEmpty() }?.take(4) ?: m.imageTopics,
                sources = if (rich.sources.isNotEmpty() && m.sources.isNullOrEmpty()) rich.sources else m.sources,
                compare = rich.compare ?: m.compare,
                quiz = rich.quiz ?: m.quiz,
                actions = rich.actions.takeIf { it.isNotEmpty() } ?: m.actions,
                deck = slidesTitle?.let { Slides.pending(it) } ?: m.deck,
                pendingDeckTitle = pendingDeck,
                appRequest = rich.appRequest ?: m.appRequest,
            )
        }
        rich.followUp?.let { next -> ChatStore.mutate(sessionID, notify = false) { it.copy(followUp = next) } }
        if (slidesTitle != null) Slides.start(sessionID, messageID, text)

        val clean = Tags.cleanLeftovers(text)
        if (clean.isEmpty()) return if (actions.badges.isEmpty() && notes.badges.isEmpty())
            "Üzgünüm, bu konuda yeterli bilgiye ulaşamadım. Başka bir şekilde yardımcı olmamı ister misin?" else "Tamamdır, ayarladım."
        return clean
    }

    /** Zamanlanmış görevin sohbeti (yoksa görevin isteğiyle başlayan yeni sohbet) */
    fun ensureTaskSession(taskID: String, title: String, prompt: String): String {
        ReminderStore.reminder(taskID)?.taskSessionID?.let { id -> if (ChatStore.session(id) != null) return id }
        val session = ChatSession(title = title, messages = listOf(Message(content = prompt, role = "user")), isSpaceChat = true)
        ChatStore.upsert(session)
        ReminderStore.update(taskID) { it.copy(taskSessionID = session.id) }
        return session.id
    }

    /** Sunucuda çalışan görevin sonucu → görevin sohbetine */
    fun importTaskResult(taskID: String, text: String) {
        val task = ReminderStore.reminder(taskID) ?: return
        val sessionID = ensureTaskSession(taskID, task.title, task.aiTaskPrompt)
        val rich = Tags.extractRich(text)
        ChatStore.mutate(sessionID) { it.copy(messages = it.messages + Message(content = rich.text, role = "model", sources = rich.sources.takeIf { s -> s.isNotEmpty() })) }
        ReminderStore.upsert(task.copy(taskInbox = emptyList()), notify = false)
    }

    /** Görevi hemen çalıştır (iOS viewModel.runTaskNow karşılığı) */
    fun runTaskNow(taskID: String) {
        val task = ReminderStore.reminder(taskID) ?: return
        val prompt = task.aiTaskPrompt.ifBlank { task.title }
        val sessionID = ensureTaskSession(taskID, task.title, prompt)
        open(sessionID)
        // Görev isteği her çalıştırmada ayrıca gidiyor; sondaki aynı kullanıcı mesajı geçmişte tekrar etmesin
        val past = (ChatStore.session(sessionID)?.messages ?: emptyList()).let { m -> if (m.lastOrNull()?.let { it.isUser && it.content == prompt } == true) m.dropLast(1) else m }
        val history = apiHistory(past)
        run(sessionID, prompt, userPrompt = prompt, emptyList(), history, reminderMode = false, forceSearch = false, isVoice = false)
    }

    // MARK: Başlık

    private fun titleIfNeeded(sessionID: String, prompt: String, hasImages: Boolean) {
        val session = ChatStore.session(sessionID) ?: return
        if (session.title != ChatSession.DEFAULT_TITLE || session.isSpaceChat) return
        val quick = prompt.split(" ").take(4).joinToString(" ")
        ChatStore.mutate(sessionID) { it.copy(title = quick.ifEmpty { if (hasImages) "Görsel Analizi" else ChatSession.DEFAULT_TITLE }) }
        if (prompt.isEmpty()) return
        scope.launch {
            val generated = runCatching {
                AiClient.generate("Mesaj: \"${prompt.take(300)}\"",
                    system = "Bu mesajla başlayan sohbet için en fazla 4 kelimelik, emojisiz, tırnaksız, Türkçe bir başlık yaz. Sadece başlığı yaz.",
                    maxOutputTokens = 300, thinking = "low")
            }.getOrNull() ?: return@launch
            val title = generated.trim().trim('"', '\'', '*', '#', '.')
            if (title.isNotEmpty() && title.length <= 48 && !title.contains("\n")) ChatStore.mutate(sessionID) { it.copy(title = title) }
        }
    }

    // MARK: Yönerge

    fun timeZoneGuide(): String {
        val now = java.time.Instant.now()
        fun offset(id: String) = ZoneId.of(id).rules.getOffset(now).totalSeconds
        val turkey = offset("Europe/Istanbul")
        fun rule(name: String, id: String): String { val h = (turkey - offset(id)) / 3600; return "  • $name: TSİ = yerel saat ${if (h >= 0) "+" else "−"} ${kotlin.math.abs(h)} saat" }
        val ce = (turkey - offset("Europe/Berlin")) / 3600
        return listOf(
            rule("Orta Avrupa (İspanya, İtalya, Almanya, Fransa, Hollanda; UEFA maç saatleri)", "Europe/Berlin"),
            rule("İngiltere ve Portekiz", "Europe/London"),
            rule("ABD Doğu (New York)", "America/New_York"),
            rule("ABD Batı (Los Angeles)", "America/Los_Angeles"),
            "  • UTC / GMT: TSİ = UTC + 3 saat",
            "  • Örnek: UEFA'nın akşam maçı yerel 21:00 = ${21 + ce}:00 TSİ; erken maçı 18:45 = ${18 + ce}:45 TSİ.",
        ).joinToString("\n")
    }

    fun buildSystemPrompt(reminderMode: Boolean, isSpaceChat: Boolean, memoryQuery: String, currentSessionID: String?, focus: String?): String {
        val now = System.currentTimeMillis()
        val focusText = focus ?: memoryQuery
        val scheduling = reminderMode || isSpaceChat || QueryRouter.isSchedulingRequest(focusText) || QueryRouter.mentionsScheduling(focusText)
        val noteRelated = QueryRouter.isNoteRequest(focusText) || NoteMentions.isMentioned(focusText)
        val base = Prompts.agent(Prompts.Params(
            turkishNow = turkeyFormat(now, "d MMMM yyyy EEEE, 'saat' HH:mm"),
            iso = turkeyISO(now),
            userName = Profile.name,
            memory = MemoryStore.promptText(memoryQuery),
            reminders = ReminderStore.promptText(),
            past = pastConversationsText(memoryQuery, currentSessionID),
            taskRules = if (scheduling) Prompts.TASK_RULES_FULL else Prompts.TASK_RULES_SHORT,
            notesSection = if (noteRelated) Prompts.notesFull(NoteStore.promptText()) else Prompts.notesShort(NoteStore.titlesText()),
            reminderMode = reminderMode, isSpaceChat = isSpaceChat,
        )) { timeZoneGuide() }
        // Cevap dili ve dosya kuralı yönergenin içinde (Prompts.agent, iOS ile aynı kaynaktan)
        return base
    }

    private fun tokens(text: String) = text.lowercase(TR).split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 3 }
    private fun matches(a: String, b: String): Boolean { val p = maxOf(3, minOf(a.length, b.length) - 2); return a.take(p) == b.take(p) || a.startsWith(b) || b.startsWith(a) }

    fun pastConversationsText(query: String, excluding: String?): String {
        val past = ChatStore.sessions.value.filter { it.id != excluding && it.messages.isNotEmpty() && !it.isSpaceChat }.sortedByDescending { it.lastActivity }
        if (past.isEmpty()) return "Başka sohbet yok."
        fun date(swift: Double) = turkeyFormat(swiftToEpochMillis(swift), "d MMMM HH:mm")
        fun flat(t: String, n: Int) = t.replace("\n", " ").take(n)
        val lines = mutableListOf("Son sohbetler (yeniden eskiye):")
        for (s in past.take(10)) lines.add("- ${date(s.lastActivity)} · ${s.title} — \"${flat(s.messages.firstOrNull { it.isUser }?.content ?: "", 70)}\"")
        val lowered = query.lowercase(TR)
        val pastCue = listOf("dün", "geçen", "daha önce", "önceki", "hatırlıyor", "hatırla", "konuşmuştuk", "demiştim", "söylemiştim",
            "sormuştum", "bahsetmiştim", "anlatmıştım", "geçenlerde", "kaldığımız", "o sohbet", "en son").any { lowered.contains(it) }
        val qt = tokens(query).toSet()
        val hits = mutableListOf<Pair<Int, String>>()
        for (s in past.take(80)) s.messages.forEachIndexed { i, m ->
            if (!m.isUser) return@forEachIndexed
            val words = tokens(m.content + " " + s.title)
            val score = qt.count { t -> words.any { matches(t, it) } }
            if (score < (if (pastCue) 1 else 3)) return@forEachIndexed
            val reply = s.messages.drop(i + 1).firstOrNull { !it.isUser }?.content ?: ""
            hits.add(score to "[${date(m.timestamp)} · ${s.title}] Kullanıcı: \"${flat(m.content, 200)}\" → Pufy: \"${flat(reply, 350)}\"")
        }
        val top = hits.sortedByDescending { it.first }.take(if (pastCue) 4 else 2)
        if (top.isNotEmpty()) { lines.add("Bu mesajla ilgili geçmiş konuşmalar:"); top.forEach { lines.add("- " + it.second) } }
        return lines.joinToString("\n")
    }

    /** Yeni sohbet ekranındaki "kaldığın yerden" önerileri (son 3 sohbetin devam sorusu) */
    fun recentFollowUps(): List<Pair<String, String>> = ChatStore.sessions.value
        .filter { !it.followUp.isNullOrBlank() && !it.isSpaceChat && it.messages.isNotEmpty() }
        .sortedByDescending { it.lastActivity }.take(3).map { it.title to it.followUp!! }

    @Suppress("unused") private fun swiftNow() = nowSwift()
    @Suppress("unused") private val settings = Settings
}

/** Mesaj bir notun başlığına ya da maddesine değiniyor mu? (iOS NoteStore.isMentioned) */
object NoteMentions {
    fun isMentioned(query: String): Boolean {
        val words = query.lowercase(TR).split(Regex("[^\\p{L}]+")).filter { it.length >= 3 }
        if (words.isEmpty()) return false
        fun hit(text: String): Boolean {
            val key = text.lowercase(TR).split(Regex("[^\\p{L}]+")).firstOrNull { it.length >= 3 } ?: return false
            return words.any { it.startsWith(key) }
        }
        for (note in NoteStore.notes.value) {
            if (note.title.lowercase(TR).split(Regex("[^\\p{L}]+")).any { it.length >= 4 && it in words }) return true
            for (raw in note.content.lines().take(80)) {
                val item = com.pufy.app.data.NoteLine.checkItem(raw.trim())?.second ?: raw.trim().takeIf { it.startsWith("- ") || it.startsWith("• ") }?.drop(2)
                if (item != null && hit(item)) return true
            }
        }
        return false
    }
}
