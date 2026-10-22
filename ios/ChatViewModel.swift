import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
class ChatViewModel: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: UUID?
    @Published var searchText: String = ""
    /// "Web'de Ara" modu: açıkken her mesajda planlayıcı beklenmeden web araması yapılır
    @Published var isSearchingWeb: Bool = false
    @Published var isReminderMode: Bool = false
    @Published var selectedImages: [Data] = []  // Çoklu görsel desteği (küçültülmüş JPEG)
    @Published var selectedFiles: [FileAttachment] = [] // Eklenen dosyalar (en fazla 3)
    @Published var isExtractingFiles: Bool = false // Dosyadan metin çıkarılıyor mu
    /// Hangi sohbet şu an cevap üretiyor (nil = boşta)
    @Published private(set) var generatingSessionID: UUID?
    @Published var userMemory: String = ""
    @Published var errorMessage: String?
    @Published var userName: String = ""
    @Published var userProfileImageData: Data?
    @Published var lastResponseID: UUID?
    /// Son mesaj sesli mi gönderildi? ChatView tarafından set edilir.
    @Published var isVoiceInput: Bool = false

    /// Aktif sohbet. Artık `sessions` içindeki kaydın kendisi — eskiden ayrı bir kopya tutuluyordu
    /// ve iki kopya senkron tutulmaya çalışılıyordu (cevap gelirken sohbet değiştirilince
    /// yanıtın kaybolması / yanlış sohbetin başlığının değişmesi buradan çıkıyordu).
    var currentSession: ChatSession? {
        get { sessions.first { $0.id == currentSessionID } }
        set {
            guard let newValue else { currentSessionID = nil; return }
            if let index = sessions.firstIndex(where: { $0.id == newValue.id }) {
                sessions[index] = newValue
            } else {
                sessions.insert(newValue, at: 0)
            }
            currentSessionID = newValue.id
        }
    }

    /// Yeni sohbet ekranı için: son sohbetlerin sonunda kaydedilen devam soruları (en fazla 3)
    var recentFollowUps: [(title: String, question: String)] {
        sessions
            .filter { $0.id != currentSessionID && !$0.isSpaceChatValue }
            .compactMap { session in session.followUp.map { (session.title, $0) } }
            .prefix(3)
            .map { $0 }
    }

    /// Aktif sohbet şu an cevap mı bekliyor?
    var isLoading: Bool {
        generatingSessionID != nil && generatingSessionID == currentSessionID
    }

    private var currentTask: Task<Void, Never>?
    private var currentRevealer: TextRevealer?
    private var generationToken: UUID?

    // Etiket temizleme regex'leri (önbellekte)
    private static let cleanTagsRegex: [NSRegularExpression] = [
        "\\[THINK\\s*:[^\\]]*(?:\\]|$)",
        "\\[SEARCH\\s*:[^\\]]*(?:\\]|$)",
        "\\[REMINDER\\s*:[^\\]]*(?:\\]|$)",
        "\\[DELETE_REMINDER\\s*:[^\\]]*(?:\\]|$)",
        "\\[UPDATE_REMINDER\\s*:[^\\]]*(?:\\]|$)",
        "\\[AI_TASK\\s*:[^\\]]*(?:\\]|$)",
        "\\[TIMER\\s*:[^\\]]*(?:\\]|$)",
        "\\[(?:NOTE|DELETE_NOTE)\\s*:\\s*\\{[\\s\\S]*?\\}\\s*\\]",
        "\\[(?:NEXT|SOURCES|IMAGES|DRAW|SLIDES|ACTIONS)\\s*:[^\\]]*(?:\\]|$)",
        "\\[UYGULAMA_YAP\\s*:[^\\]]*(?:\\]|$)",
        "(?i)\\[ARAY[UÜ]Z[\\s\\S]*?(?:\\[/ARAY[UÜ]Z\\]|$)"
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators]) }


    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let reminderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private let memoryKey = "pufy_agent_user_memory"
    private let nameKey = "pufy_agent_user_name"
    private let imageKey = "pufy_agent_user_image"
    private let defaultTitle = "Yeni Sohbet"
    static let emptyMemoryText = "Kullanıcı hakkında henüz bir bilgi kaydedilmedi."

    init() {
        sessions = ChatStore.shared.load()
        userMemory = UserDefaults.standard.string(forKey: memoryKey) ?? Self.emptyMemoryText
        userName = UserDefaults.standard.string(forKey: nameKey) ?? ""
        userProfileImageData = UserDefaults.standard.data(forKey: imageKey)

        // Kişisel harita henüz oluşmadıysa mevcut notlardan oluştur
        // Eski sürümden kalan düz metin notlar varsa yeni hafıza motoruna bir kez öğret
        if MemoryStore.shared.items.isEmpty && userMemory != Self.emptyMemoryText {
            MemoryStore.shared.learn(from: userMemory)
        }
        // Önceki sürümde kaydedilmiş bilgilere bir kez anahtar kelime ekletir (ilgili bilgiyi bulabilmek için)
        MemoryStore.shared.backfillKeywordsIfNeeded()
        SyncService.shared.chat = self
        // Kapalıyken çalışmış zamanlanmış görevlerin sonuçları sohbetlerine yazılır
        importTaskResults()
        NotificationCenter.default.addObserver(forName: ScheduledTaskRunner.resultReady, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.importTaskResults() }
        }
        // Görevin sohbetine bakılıyorsa sonuç ekrana düşer; ayrıca bildirim gerekmez
        ScheduledTaskRunner.shared.isViewingTask = { [weak self] task in
            guard let self, let sessionID = task.taskSessionID else { return false }
            return UIApplication.shared.applicationState == .active
                && self.currentSessionID == sessionID
                && TabManager.shared.activeTab.isChatTab
                && !TabManager.shared.isTabSwitcherVisible
        }
        // Hafızaya işlenmemiş mesajlar (ör. cevabı hata veren) açılıştan biraz sonra öğrenilir
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            await MemoryStore.shared.catchUp(from: self.sessions)
        }

        // 15 dakikadan uzun süre sonra açıldıysa yeni sohbetle başla
        let lastExit = UserDefaults.standard.double(forKey: "pufy_agent_last_exit")
        let isTimeout = lastExit > 0 && Date().timeIntervalSince1970 - lastExit > 15 * 60

        if sessions.isEmpty || (isTimeout && !(sessions.first?.messages.isEmpty ?? true)) {
            startNewSession()
        } else {
            currentSessionID = sessions.first?.id
        }
    }

    // MARK: - Session Management

    func startNewSession() {
        // Listenin başında zaten boş bir sohbet varsa ona geç
        if let first = sessions.first, first.messages.isEmpty, !first.isSpaceChatValue {
            currentSessionID = first.id
            return
        }
        let newSession = ChatSession(title: defaultTitle, messages: [])
        sessions.insert(newSession, at: 0)
        currentSessionID = newSession.id
        persist()
    }

    func startNewSpaceSession(title: String) -> ChatSession {
        let newSession = ChatSession(title: title, messages: [], isSpaceChat: true)
        sessions.insert(newSession, at: 0)
        currentSessionID = newSession.id
        persist()
        return newSession
    }

    func selectSession(_ session: ChatSession) {
        currentSessionID = session.id
    }

    func deleteSession(_ session: ChatSession) {
        if generatingSessionID == session.id { cancelMessage() }
        sessions.removeAll { $0.id == session.id }
        if currentSessionID == session.id {
            currentSessionID = sessions.first?.id
        }
        if sessions.isEmpty {
            startNewSession()
        } else {
            persist()
        }
    }

    func clearAllSessions() {
        cancelMessage()
        sessions.removeAll()
        startNewSession()
    }

    /// Uygulama arka plana geçince çağrılır — veriyi beklemeden diske yazar.
    func forceSaveSessions() {
        persist(immediately: true)
    }

    func updateSessionInList(_ updatedSession: ChatSession, saveNow: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == updatedSession.id }) else { return }
        sessions[index] = updatedSession
        if saveNow { persist() }
    }

    func togglePinSession(_ session: ChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].isPinned.toggle()
        persist()
    }

    private func persist(immediately: Bool = false) {
        ChatStore.shared.save(sessions, immediately: immediately)
        SyncService.shared.scheduleSync()
    }

    // MARK: - Eşitleme (diğer cihazdan gelen)

    /// Sunucudan gelen sohbet: varsa güncelle (bu cihazdaki fotoğraflar korunur), yoksa ekle
    func applyRemoteSession(_ remote: ChatSession) {
        guard generatingSessionID != remote.id else { return }   // şu an yazılan sohbete dokunma
        if let index = sessions.firstIndex(where: { $0.id == remote.id }) {
            let localImages = Dictionary(uniqueKeysWithValues: sessions[index].messages.map { ($0.id, $0.imageDatas) })
            var merged = remote
            merged.messages = remote.messages.map { var m = $0; if m.imageDatas.isEmpty { m.imageDatas = localImages[m.id] ?? [] }; return m }
            sessions[index] = merged
        } else {
            sessions.append(remote)
            sessions.sort { ($0.messages.last?.timestamp ?? $0.createdAt) > ($1.messages.last?.timestamp ?? $1.createdAt) }
        }
        ChatStore.shared.save(sessions, immediately: false)
    }

    func applyRemoteSessionDeletion(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }), generatingSessionID != id else { return }
        sessions.removeAll { $0.id == id }
        if currentSessionID == id { currentSessionID = sessions.first?.id }
        if sessions.isEmpty { startNewSession() }
        ChatStore.shared.save(sessions, immediately: false)
    }

    func applyRemoteName(_ name: String) {
        guard name != userName else { return }
        userName = name
        UserDefaults.standard.set(name, forKey: nameKey)
    }

    private func mutateSession(_ id: UUID, _ body: (inout ChatSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        body(&sessions[index])
    }

    private func mutateMessage(session sessionID: UUID, message messageID: UUID, _ body: (inout Message) -> Void) {
        mutateSession(sessionID) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
            body(&session.messages[index])
        }
    }

    // MARK: - Dosya Formatlama & İşlemleri

    static func formatFileBlock(_ file: FileAttachment, maxChars: Int? = nil) -> String {
        var desc = file.name
        if let pages = file.pageCount, pages > 0 {
            desc += " — \(pages) sayfa"
        }
        let isTruncated: Bool
        let textToSend: String
        if let maxChars = maxChars, file.text.count > maxChars {
            textToSend = String(file.text.prefix(maxChars))
            isTruncated = true
        } else {
            textToSend = file.text
            isTruncated = file.truncated
        }
        if isTruncated {
            desc += ", metin kısaltıldı"
        }
        return "[DOSYA: \(desc)]\n\(textToSend)\n[/DOSYA]"
    }

    static func formatPromptWithFiles(prompt: String, files: [FileAttachment]?, maxCharsPerFile: Int? = nil) -> String {
        guard let files = files, !files.isEmpty else { return prompt }
        let blocks = files.map { formatFileBlock($0, maxChars: maxCharsPerFile) }.joined(separator: "\n\n")
        if prompt.isEmpty {
            return blocks
        } else {
            return blocks + "\n\n" + prompt
        }
    }

    func addFiles(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isExtractingFiles = true
        defer { isExtractingFiles = false }

        for url in urls {
            if selectedFiles.count >= 3 {
                errorMessage = NSLocalizedString("En fazla 3 dosya ekleyebilirsiniz.", comment: "")
                break
            }
            do {
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try FileTextExtractor.extract(from: url)
                }.value
                selectedFiles.append(attachment)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeFile(at index: Int) {
        guard index >= 0 && index < selectedFiles.count else { return }
        selectedFiles.remove(at: index)
    }

    /// API'ye gönderilecek geçmiş: hata/iptal mesajları ve boş balonlar ayıklanır, son 7 mesaj
    private func apiHistory(from messages: some Collection<Message>) -> [Message] {
        let valid = messages.filter { msg in
            !msg.content.isEmpty
                && !msg.content.hasPrefix("Hata oluştu:")
                && !msg.content.hasPrefix("İptal edildi.")
        }
        return Array(valid.suffix(7)).map { msg in
            if let files = msg.files, !files.isEmpty {
                var copy = msg
                copy.content = Self.formatPromptWithFiles(prompt: msg.content, files: files, maxCharsPerFile: 8000)
                return copy
            }
            return msg
        }
    }

    // MARK: - Message Operations

    /// Tek sohbet örneği (uygulama genelinde)
    static let shared = ChatViewModel()

    func sendMessage() async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        var prompt = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = selectedFiles
        if prompt.isEmpty && !files.isEmpty {
            prompt = AppLanguage.isEnglish ? "Summarize this file." : "Bu dosyayı özetle."
        }
        // Güvenlik ağı: her görsel küçültülmüş olsun (ör. 12MP kamera fotoğrafı)
        let images = selectedImages.map { ImageUtils.preparedJPEG(from: $0) }
        guard !prompt.isEmpty || !images.isEmpty || !files.isEmpty, let sessionID = currentSessionID else { return }

        let reminderMode = isReminderMode
        let forceSearch = isSearchingWeb
        let isVoice = isVoiceInput

        searchText = ""
        selectedImages = []
        selectedFiles = []
        errorMessage = nil
        isVoiceInput = false
        if reminderMode { isReminderMode = false }

        let history = apiHistory(from: currentSession?.messages ?? [])
        let userMsg = Message(content: prompt, role: .user, imageDatas: images, isVoiceInitiated: isVoice, files: files.isEmpty ? nil : files)

        mutateSession(sessionID) { $0.messages.append(userMsg) }
        // Mesaj atılan sohbet listenin en üstüne çıkar (ChatGPT gibi)
        if let index = sessions.firstIndex(where: { $0.id == sessionID }), index > 0, !sessions[index].isPinned {
            sessions.insert(sessions.remove(at: index), at: 0)
        }
        persist()

        await runGeneration(sessionID: sessionID, prompt: prompt, images: images, files: files, history: history,
                            reminderMode: reminderMode, forceSearch: forceSearch, isVoice: isVoice)
    }

    /// Son asistan cevabını aynı soruyla yeniden ürettirir (ChatGPT'deki ↻)
    func regenerateLastResponse() {
        guard generatingSessionID == nil,
              let sessionID = currentSessionID,
              let session = currentSession,
              let lastUserIndex = session.messages.lastIndex(where: { $0.role == .user }) else { return }

        let userMsg = session.messages[lastUserIndex]
        let history = apiHistory(from: session.messages[..<lastUserIndex])
        mutateSession(sessionID) { s in
            if lastUserIndex + 1 < s.messages.count {
                s.messages.removeSubrange((lastUserIndex + 1)...)
            }
        }
        Task {
            await runGeneration(sessionID: sessionID, prompt: userMsg.content, images: userMsg.imageDatas,
                                files: userMsg.files ?? [], history: history, reminderMode: false, forceSearch: isSearchingWeb,
                                isVoice: false)
        }
    }

    func cancelMessage() {
        currentRevealer?.cancel()   // Durdur'a basınca yazım anında dursun
        currentRevealer = nil
        currentTask?.cancel()
        currentTask = nil
        generationToken = nil
        generatingSessionID = nil
    }

    private func runGeneration(sessionID: UUID, prompt: String, images: [Data], files: [FileAttachment] = [], history: [Message],
                               reminderMode: Bool, forceSearch: Bool, isVoice: Bool) async {
        // Aynı anda tek üretim: önceki varsa durdur
        currentTask?.cancel()
        let token = UUID()
        generationToken = token
        generatingSessionID = sessionID

        let modelMsg = Message(content: "", role: .model, isVoiceInitiated: isVoice)
        let messageID = modelMsg.id
        mutateSession(sessionID) { $0.messages.append(modelMsg) }
        let isSpaceChat = sessions.first { $0.id == sessionID }?.isSpaceChatValue ?? false

        // Gelen metni ekrana akıcı şekilde döken motor (bkz. TextRevealer)
        let revealer = TextRevealer { [weak self] shown in
            self?.mutateMessage(session: sessionID, message: messageID) {
                $0.content = shown
                $0.isSearching = false
            }
        }
        currentRevealer?.cancel()
        currentRevealer = revealer
        revealer.start()

        let task = Task { [weak self] in
            guard let self else { return }
            // Uygulama arka plana atılsa da cevap tamamlansın
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "PufyMessageTask") {}
            defer { UIApplication.shared.endBackgroundTask(bgTask) }

            do {
                // Hafızadan sadece bu mesajla (ve sohbetin son birkaç mesajıyla) ilgili bilgiler okunur
                let recentContext = history.suffix(2).map(\.content).joined(separator: " ")
                let lastUser = history.last { $0.role == .user }?.content ?? ""
                let systemPrompt = self.buildAgentSystemPrompt(reminderMode: reminderMode, isSpaceChat: isSpaceChat,
                                                               memoryQuery: prompt + " " + recentContext.suffix(600),
                                                               currentSessionID: sessionID,
                                                               focus: prompt + " " + lastUser.prefix(300))

                let payloadPrompt = Self.formatPromptWithFiles(prompt: prompt, files: files.isEmpty ? nil : files)
                let response = try await DeepResearchManager.shared.executeDeepResearch(
                    query: payloadPrompt,
                    history: history,
                    imageDatas: images,
                    hasFiles: !files.isEmpty,
                    systemPrompt: systemPrompt,
                    forceSearch: forceSearch,
                    progress: { [weak self] step in
                        self?.applyProgress(step, session: sessionID, message: messageID)
                    },
                    onPartialText: { [weak self] partial, reasoning in
                        revealer.target = partial
                        if !reasoning.isEmpty {
                            self?.mutateMessage(session: sessionID, message: messageID) {
                                $0.reasoning = reasoning
                                $0.isSearching = false
                            }
                        }
                    },
                    onSources: { [weak self] sources in
                        self?.mutateMessage(session: sessionID, message: messageID) { $0.sources = sources }
                    }
                )
                try Task.checkCancellation()

                let finalText = self.applyAgentActions(to: response, session: sessionID, message: messageID)
                // Görev kuracağını söyleyip etiketi unuttuysa: etiketi ayrıca iste (eskiden görev hiç eklenmiyordu)
                let scheduledSomething = self.sessions.first { $0.id == sessionID }?
                    .messages.first { $0.id == messageID }?.reminderTitle != nil
                if !scheduledSomething, DeepResearchManager.isSchedulingRequest(prompt), Self.promisesSchedule(finalText) {
                    self.repairMissingTask(prompt: prompt, reply: finalText, sessionID: sessionID,
                                           messageID: messageID, isSpaceChat: isSpaceChat)
                }
                if finalText.contains("![") {
                    // Üretilen görsel: markdown'ı harf harf yazmak anlamsız, direkt göster
                    revealer.cancel()
                } else {
                    revealer.target = finalText
                    await revealer.finish()
                }
                try Task.checkCancellation()
                self.mutateMessage(session: sessionID, message: messageID) {
                    $0.content = finalText
                    $0.isSearching = false
                }
                self.lastResponseID = messageID
                self.titleSessionIfNeeded(sessionID, prompt: prompt, hasImages: !images.isEmpty)
                PremiumHaptics.success()

                if UIApplication.shared.applicationState != .active {
                    self.sendResponseNotification(finalText)
                }
                // Kişisel ağ: mesajın TAMAMI kuyruğa girer (bkz. MemoryStore)
                // Asistanın bir önceki sorusu bağlam olur: "Nerede yaşıyorsun?" → "İstanbul" de öğrenilir
                let askedBefore = history.last(where: { $0.role == .model })?.content
                let userMessageID = self.sessions.first { $0.id == sessionID }?.messages.last { $0.role == .user }?.id
                MemoryStore.shared.learn(from: prompt, context: askedBefore, messageID: userMessageID)
            } catch {
                revealer.cancel()
                let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError
                self.mutateMessage(session: sessionID, message: messageID) { msg in
                    msg.isSearching = false
                    if cancelled {
                        // Akışla gelen kısım varsa korunur (ChatGPT'deki "durdur" davranışı)
                        if msg.content.isEmpty { msg.content = "İptal edildi." }
                    } else if msg.content.isEmpty {
                        msg.content = "Hata oluştu: \(error.localizedDescription)"
                    }
                }
                if !cancelled { self.errorMessage = error.localizedDescription }
            }

            // Yalnızca hâlâ bu üretim aktifse durumu sıfırla (iptal + hızlı yeni mesaj yarışı)
            if self.generationToken == token {
                self.generatingSessionID = nil
                self.generationToken = nil
                self.currentTask = nil
            }
            self.persist()
        }
        currentTask = task
        await task.value
    }

    private func applyProgress(_ step: ResearchProgress, session: UUID, message: UUID) {
        mutateMessage(session: session, message: message) { msg in
            msg.thinkingSteps.append(step.displayText)
            if case .searching(let queries) = step {
                msg.isSearching = true
                msg.searchQuery = queries.joined(separator: ", ")
            } else if case .writing = step {
                msg.isSearching = false
            }
        }
    }

    /// Cevaptaki [REMINDER:…], [AI_TASK:…], [DELETE_REMINDER:…], [UPDATE_REMINDER:…] etiketlerini işler.
    /// Bir cevapta birden fazla hatırlatıcı olabilir (eskiden sadece ilki kuruluyor, diğerleri sessizce siliniyordu).
    private func applyAgentActions(to response: String, session: UUID, message: UUID) -> String {
        let manager = ReminderManager.shared
        var text = response

        // Notlar (önce: içeriğindeki "- [ ] madde" köşeli parantezleri diğer etiket ayıklayıcılarını şaşırtmasın)
        let notes = NoteStore.shared.applyTags(in: text)
        text = notes.text
        if !notes.badges.isEmpty {
            PremiumHaptics.success()
            mutateMessage(session: session, message: message) {
                $0.noteTitle = notes.badges.joined(separator: ", ")
                $0.noteID = notes.noteID
            }
        }
        var badges: [String] = []
        var steps: [String] = []

        while true {
            let (reminder, clean) = manager.parseAndExtract(from: text)
            guard let reminder, clean != text else { break }
            manager.add(reminder)
            text = clean
            badges.append(reminder.title)
            steps.append("Hatırlatıcı kuruldu: \(reminder.title) (\(formatReminderDate(reminder.date)))")
        }
        // [TIMER: {"seconds":300,"title":"Çay demleme"}]
        if let regex = try? NSRegularExpression(pattern: "\\[TIMER\\s*:\\s*(\\{[^\\]]*\\})\\s*\\]", options: [.caseInsensitive]) {
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(match.range, in: text), let json = Range(match.range(at: 1), in: text) {
                if let data = String(text[json]).data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let seconds = (obj["seconds"] as? Int) ?? Int(obj["seconds"] as? Double ?? 0)
                    if seconds >= 5 && seconds <= 24 * 3600 {
                        let timer = manager.addTimer(seconds: seconds, title: obj["title"] as? String ?? "Zamanlayıcı")
                        badges.append(ReminderManager.timerTitle(timer))
                        steps.append("Zamanlayıcı kuruldu: \(ReminderManager.timerTitle(timer))")
                    }
                }
                text.removeSubrange(whole)
            }
        }
        while true {
            let (task, clean) = manager.parseAndExtractAITask(from: text)
            guard let task, clean != text else { break }
            manager.add(task)
            text = clean
            badges.append(task.title)
            steps.append("AI görevi planlandı: \(task.title) (\(formatReminderDate(task.date)))")
        }
        while true {
            let (clean, deletedTitle) = manager.parseAndDelete(from: text)
            guard clean != text else { break }
            text = clean
            if let deletedTitle { badges.append("Silindi: \(deletedTitle)") }
        }
        while true {
            let (clean, updatedTitle) = manager.parseAndUpdate(from: text)
            guard clean != text else { break }
            text = clean
            if let updatedTitle { badges.append("Güncellendi: \(updatedTitle)") }
        }

        if !badges.isEmpty {
            PremiumHaptics.success()
            mutateMessage(session: session, message: message) {
                $0.reminderTitle = badges.joined(separator: ", ")
                $0.thinkingSteps.append(contentsOf: steps)
            }
        }

        // Zengin cevap etiketleri (cevabın sonunda): devam sorusu, kaynaklar, görseller, seçenekli sorular
        let rich = Self.extractRichTags(from: text)
        text = rich.text
        // Sunum SON cevapta. Kullanıcı (15 Ekim 2026): "Japonya rotası istedim; ilk cevapta soru sorup yalandan boş bir
        // sunum verdi, sorulara cevap verince asıl rotayı yazdı ama sunum yoktu." Soru soran ([CHOICES]) cevapta sunum
        // hazırlanmaz, ertelenir; kullanıcı cevaplayınca gelen tam cevapta (model unutsa da) hazırlanır.
        var slidesTitle = rich.slidesTitle
        var pendingDeck: String?
        let previousPending = sessions.first { $0.id == session }.flatMap { s -> String? in
            guard let index = s.messages.firstIndex(where: { $0.id == message }) else { return nil }
            return s.messages[..<index].last { $0.role == .model }?.pendingDeckTitle
        }
        var canvas = rich.canvas
        if rich.choices != nil {
            pendingDeck = slidesTitle ?? previousPending
            slidesTitle = nil
            // [CHOICES] içeren bir cevapta (model soru soruyorsa) [ARAYUZ] yok sayılsın, metinden silinsin
            canvas = nil
        } else if slidesTitle == nil, let pending = previousPending {
            if text.count >= 900 { slidesTitle = pending } else { pendingDeck = pending }
        }
        mutateMessage(session: session, message: message) { msg in
            if let canvas { msg.canvas = canvas }
            if let choices = rich.choices { msg.choices = choices }
            if !rich.widgets.isEmpty { msg.widgets = Array(rich.widgets.prefix(3)) }
            if let compare = rich.compare { msg.compare = compare }
            if let quiz = rich.quiz { msg.quiz = quiz }
            if !rich.actions.isEmpty { msg.actions = rich.actions }
            if let title = slidesTitle { msg.deck = SlideDeck(title: title) }
            msg.pendingDeckTitle = pendingDeck
            if !rich.imageTopics.isEmpty { msg.imageTopics = Array(rich.imageTopics.prefix(4)) }
            if !rich.sources.isEmpty && (msg.sources ?? []).isEmpty { msg.sources = rich.sources }
            if let appReq = rich.appRequest { msg.appRequest = appReq }
        }
        if let next = rich.followUp {
            mutateSession(session) { $0.followUp = next }
        }
        if slidesTitle != nil {
            startDeck(session: session, message: message, answer: text)
        }

        // Kalan (bozuk/yarım) etiketleri temizle
        let mutable = NSMutableString(string: text)
        for regex in Self.cleanTagsRegex {
            regex.replaceMatches(in: mutable, options: [], range: NSRange(location: 0, length: mutable.length), withTemplate: "")
        }
        let clean = (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return badges.isEmpty
                ? "Üzgünüm, bu konuda yeterli bilgiye ulaşamadım. Başka bir şekilde yardımcı olmamı ister misin?"
                : "Tamamdır, ayarladım."
        }
        return clean
    }

    struct RichTags {
        var text: String
        var followUp: String?
        var sources: [WebSource] = []
        var imageTopics: [String] = []
        var choices: ChoicePrompt?
        var widgets: [ChatWidget] = []
        var compare: CompareData?
        var quiz: QuizData?
        var actions: [String] = []
        /// [SLIDES: başlık] → cevaptan sonra sunum hazırlanır
        var slidesTitle: String?
        /// [ARAYUZ] ... [/ARAYUZ] → dinamik HTML arayüz alanı
        var canvas: String?
        /// [UYGULAMA_YAP: ...] → sohbetten mini uygulama oluşturma isteği
        var appRequest: AppRequestData? = nil
    }

    /// [ARAYUZ]...[/ARAYUZ] bloğunu ayıklar.
    /// - Bir cevapta en fazla bir blok kullanılır (yalnızca ilki), diğerleri metinden silinir.
    /// - Markdown çitleri (```html ... ```) temizlenir.
    /// - Maksimum 12.000 karakter sınırı. Aşarsa bloğu kullanma ve metinden sil.
    /// - Kapanışı olmayan bloklar metinden silinir.
    static func extractCanvas(from input: String) -> (canvas: String?, text: String) {
        var text = input
        var foundCanvas: String? = nil

        // Türkçe "Ü" ile yazılmış etiket de kabul edilir
        let pattern = "(?i)\\[ARAY[UÜ]Z\\]([\\s\\S]*?)\\[/ARAY[UÜ]Z\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for (idx, match) in matches.enumerated().reversed() {
                if let wholeRange = Range(match.range, in: text),
                   let contentRange = Range(match.range(at: 1), in: text) {
                    let rawContent = String(text[contentRange])
                    text.removeSubrange(wholeRange)

                    if idx == 0 {
                        var cleaned = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.hasPrefix("```") {
                            if let firstNewline = cleaned.firstIndex(of: "\n") {
                                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
                            } else {
                                cleaned = ""
                            }
                            if cleaned.hasSuffix("```") {
                                cleaned = String(cleaned.dropLast(3))
                            }
                            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        if !cleaned.isEmpty && cleaned.count <= 12_000 {
                            foundCanvas = cleaned
                        }
                    }
                }
            }
        }

        // Güvenlik ağı: açılış etiketi kaybolmuş ama kapanış duruyorsa, kapanışa kadar olan HTML arayüzdür
        // (sohbete asla çıplak HTML düşmesin)
        if foundCanvas == nil, let close = text.range(of: "[/ARAY", options: .caseInsensitive),
           let end = text[close.lowerBound...].firstIndex(of: "]") {
            let before = String(text[..<close.lowerBound])
            if let start = before.firstIndex(of: "<") {
                let html = before[start...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !html.isEmpty && html.count <= 12_000 { foundCanvas = html }
                text.removeSubrange(start...end)
            } else {
                text.removeSubrange(close.lowerBound...end)
            }
        }

        // Kapanış etiketi hiç gelmemiş yarım [ARAYUZ]... bloğu varsa metinden sil
        let unclosedPattern = "(?i)\\[ARAY[UÜ]Z\\][\\s\\S]*$"
        if let unclosedRegex = try? NSRegularExpression(pattern: unclosedPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = unclosedRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        return (foundCanvas, text)
    }

    /// [NEXT: …] [SOURCES: a | b] [IMAGES: a | b] [CHOICES: {json}] etiketlerini ayıklar
    static func extractRichTags(from input: String) -> RichTags {
        var result = RichTags(text: input)

        // Dinamik arayüz alanı ([ARAYUZ]...[/ARAYUZ])
        let canvasPass = extractCanvas(from: input)
        result.canvas = canvasPass.canvas
        var text = canvasPass.text

        // Kartlar ([WIDGET: {json}]) — cevabın başında olur, JSON içinde köşeli parantez olabilir
        let widgetPass = JSONTag.widgets(in: text)
        result.widgets = widgetPass.widgets
        text = widgetPass.text
        // Karşılaştırma kartı ve test (bkz. InteractiveCards.swift)
        if text.range(of: "[COMPARE", options: .caseInsensitive) != nil {
            let pass = JSONTag.decode("COMPARE", as: CompareData.self, from: text)
            text = pass.text
            if let compare = pass.value, compare.isValid { result.compare = compare }
        }
        if text.range(of: "[QUIZ", options: .caseInsensitive) != nil {
            let pass = JSONTag.decode("QUIZ", as: QuizData.self, from: text)
            text = pass.text
            if let quiz = pass.value, quiz.isValid { result.quiz = quiz }
        }
        if text.range(of: "[UYGULAMA_YAP", options: .caseInsensitive) != nil {
            let pass = JSONTag.decode("UYGULAMA_YAP", as: AppRequestData.self, from: text)
            text = pass.text
            if let req = pass.value, !req.name.isEmpty || !req.prompt.isEmpty {
                result.appRequest = req
            }
        }

        func takeSimple(_ name: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\\[\(name)\\s*:\\s*([^\\]]*)\\]", options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { return nil }
            let value = String(text[inner]).trimmingCharacters(in: .whitespacesAndNewlines)
            text.removeSubrange(whole)
            return value
        }

        if let next = takeSimple("NEXT"), !next.isEmpty, next.count <= 90 {
            result.followUp = next.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        if let raw = takeSimple("SOURCES") {
            result.sources = raw.split(separator: "|").compactMap { part -> WebSource? in
                var item = part.trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { return nil }
                if !item.lowercased().hasPrefix("http") { item = "https://" + item }
                guard let url = URL(string: item), let host = url.host else { return nil }
                return WebSource(title: host.replacingOccurrences(of: "www.", with: ""), url: item)
            }
        }
        if let raw = takeSimple("ACTIONS") {
            result.actions = raw.split(separator: "|")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'"))) }
                .filter { !$0.isEmpty && $0.count <= 40 }
                .prefix(3).map { $0 }
        }
        if let raw = takeSimple("SLIDES") {
            let title = raw.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            result.slidesTitle = title.isEmpty ? "Sunum" : String(title.prefix(80))
        } else if let compare = result.compare, compare.rows.count >= 4 {
            // Kullanıcı (15 Ekim 2026): karşılaştırmada sonunda sunum da gelsin — model etiketi unutsa da
            result.slidesTitle = compare.items.map(\.name).joined(separator: " vs ")
        }
        if let raw = takeSimple("IMAGES") {
            result.imageTopics = raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        // CHOICES: JSON içinde köşeli parantez olabildiği için süslü parantez sayarak ayıkla
        if let start = text.range(of: "[CHOICES", options: .caseInsensitive),
           let brace = text[start.upperBound...].firstIndex(of: "{") {
            var depth = 0, inString = false, escaped = false
            var end: String.Index?
            var i = brace
            while i < text.endIndex {
                let c = text[i]
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString.toggle() }
                else if !inString {
                    if c == "{" { depth += 1 }
                    if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
                }
                i = text.index(after: i)
            }
            if let end, let data = String(text[brace...end]).data(using: .utf8) {
                if let prompt = try? JSONDecoder().decode(ChoicePrompt.self, from: data), !prompt.questions.isEmpty {
                    result.choices = prompt
                } else if let single = try? JSONDecoder().decode(ChoicePrompt.Question.self, from: data) {
                    result.choices = ChoicePrompt(questions: [single])
                }
                var tail = text.index(after: end)
                while tail < text.endIndex, text[tail] == " " || text[tail] == "]" { tail = text.index(after: tail) }
                text.removeSubrange(start.lowerBound..<tail)
            } else {
                text.removeSubrange(start.lowerBound...)   // yarım kalmış etiket
            }
        }
        result.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    /// İlk cevaptan sonra sohbete başlık verir: önce hızlı (ilk kelimeler), sonra arka planda yapay zekayla
    private func titleSessionIfNeeded(_ sessionID: UUID, prompt: String, hasImages: Bool) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              session.title == defaultTitle, !session.isSpaceChatValue else { return }

        let quick = prompt.split(separator: " ").prefix(4).joined(separator: " ")
        mutateSession(sessionID) { $0.title = quick.isEmpty ? (hasImages ? "Görsel Analizi" : self.defaultTitle) : quick }
        persist()

        guard !prompt.isEmpty else { return }
        Task { [weak self] in
            guard let generated = try? await GeminiService.shared.generateContent(
                prompt: "Mesaj: \"\(prompt.prefix(300))\"",
                systemPrompt: "Bu mesajla başlayan sohbet için en fazla 4 kelimelik, emojisiz, tırnaksız, Türkçe bir başlık yaz. Sadece başlığı yaz.",
                // Düşünme payı 40 token'lık sınırı yiyip başlığı boş bırakabiliyordu
                maxOutputTokens: 300,
                thinking: "low"
            ) else { return }
            let title = generated
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'*#."))
            guard let self, !title.isEmpty, title.count <= 48, !title.contains("\n") else { return }
            self.mutateSession(sessionID) { $0.title = title }
            self.persist()
        }
    }

    // MARK: - Unutulan görev etiketi

    private static func promisesSchedule(_ text: String) -> Bool {
        let t = text.lowercased(with: Locale(identifier: "tr_TR"))
        return ["bildirim", "haber vereceğim", "göndereceğim", "yazacağım", "bakacağım", "hatırlatacağım",
                "ileteceğim", "kontrol edeceğim", "kurdum", "ayarladım", "planladım", "kuruldu"].contains { t.contains($0) }
    }

    /// Model görevi kurduğunu söyledi ama [AI_TASK]/[REMINDER]/[TIMER] etiketini yazmadı → sadece etiketi iste
    private func repairMissingTask(prompt: String, reply: String, sessionID: UUID, messageID: UUID, isSpaceChat: Bool) {
        Task { [weak self] in
            guard let self else { return }
            let system = self.buildAgentSystemPrompt(reminderMode: false, isSpaceChat: isSpaceChat, memoryQuery: prompt)
            let ask = """
            Kullanıcının isteği: "\(prompt)"
            Senin cevabın: "\(reply.prefix(1200))"
            Cevabında görev/hatırlatıcı kuracağını söyledin ama gerekli etiketi yazmadın. Cevabındaki saat ve bilgilerle \
            ŞİMDİ SADECE gerekli etiketi ([AI_TASK:…], [REMINDER:…] ya da [TIMER:…]) yaz; başka hiçbir şey yazma.
            """
            guard let raw = try? await GeminiService.shared.generateContent(prompt: ask, systemPrompt: system, maxOutputTokens: 1024),
                  raw.contains("[") else { return }
            _ = self.applyAgentActions(to: raw, session: sessionID, message: messageID)
            self.persist()
        }
    }

    // MARK: - Sohbet kartları

    /// Kart yenilenince (canlı skor, güncel fiyat) sohbete kaydet
    // MARK: - Sunum ([SLIDES])

    /// Cevap ekrana geldikten SONRA sunum hazırlanır: cevap hiç gecikmez, kart "hazırlanıyor"dan "aç"a döner.
    /// "Sunum hazırla" gibi kısa isteklerde içerik önceki cevaplardan gelir.
    private func startDeck(session sessionID: UUID, message messageID: UUID, answer: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let index = session.messages.firstIndex(where: { $0.id == messageID }),
              let title = session.messages[index].deck?.title else { return }
        let earlier = session.messages[..<index].suffix(5).filter { !$0.content.isEmpty }
        var parts = earlier.map { m in
            (m.role == .user ? "KULLANICI: " : "ASİSTAN: ") + String(m.content.prefix(m.role == .user ? 800 : 7000))
        }
        let cleanAnswer = Self.extractRichTags(from: answer).text
        if !cleanAnswer.isEmpty { parts.append("ASİSTAN (son cevap): " + String(cleanAnswer.prefix(9000))) }
        if let sources = session.messages[index].sources, !sources.isEmpty {
            parts.append("Kaynaklar: " + sources.prefix(6).map(\.host).joined(separator: ", "))
        }
        let conversation = parts.joined(separator: "\n\n")
        // "Sunum hazırla" gibi kısa isteklerde içerik önceki cevaptadır
        let contentLength = max(cleanAnswer.count, earlier.filter { $0.role == .model }.map(\.content.count).max() ?? 0)

        Task { [weak self] in
            let deck: SlideDeck
            do {
                deck = try await SlideMaker.make(title: title, conversation: conversation, contentLength: contentLength)
            } catch {
                print("📽️ Sunum hazırlanamadı: \(error.localizedDescription)")
                await MainActor.run {
                    self?.mutateMessage(session: sessionID, message: messageID) { $0.deck?.status = .failed }
                    self?.persist()
                }
                return
            }
            await MainActor.run {
                guard let self else { return }
                self.mutateMessage(session: sessionID, message: messageID) { $0.deck = deck }
                self.persist()
                PremiumHaptics.success()
                // Kapak görselini önceden indir (kart açılınca hazır olsun)
                if let topic = deck.slides.first?.image { Task { _ = await TopicImageCache.shared.load(topic) } }
            }
        }
    }

    /// Sunum kartındaki "tekrar dene"
    func retryDeck(messageID: UUID) {
        guard let session = sessions.first(where: { $0.messages.contains { $0.id == messageID } }),
              let message = session.messages.first(where: { $0.id == messageID }), message.deck != nil else { return }
        mutateMessage(session: session.id, message: messageID) { $0.deck?.status = .generating; $0.deck?.startedAt = Date() }
        startDeck(session: session.id, message: messageID, answer: message.content)
    }

    func updateWidget(messageID: UUID, index: Int, widget: ChatWidget) {
        guard let sessionID = sessions.first(where: { $0.messages.contains { $0.id == messageID } })?.id else { return }
        mutateMessage(session: sessionID, message: messageID) { message in
            guard var widgets = message.widgets, widgets.indices.contains(index) else { return }
            widgets[index] = widget
            message.widgets = widgets
        }
        persist()
    }

    // MARK: - Zamanlanmış görev sonuçları

    /// Arka planda çalışan görevlerin sonuçlarını görevin kendi sohbetine yazar
    func importTaskResults() {
        var changed = false
        for task in ReminderManager.shared.aiTasksWithResults {
            let sessionID = ensureTaskSession(task)
            for result in task.taskInbox ?? [] {
                let tags = Self.extractRichTags(from: result)
                var message = Message(content: tags.text, role: .model)
                if !tags.sources.isEmpty { message.sources = tags.sources }
                if !tags.widgets.isEmpty { message.widgets = tags.widgets }
                mutateSession(sessionID) { $0.messages.append(message) }
            }
            ReminderManager.shared.updateTask(task.id) { $0.taskInbox = [] }
            changed = true
        }
        if changed { persist() }
        retireFinishedTaskChats()
    }

    /// Kullanıcı (15 Ekim 2026): "Görev yapıldı, bitti ama hâlâ Görevler kısmında duruyor; belli bir süre sonra kalksın."
    /// Bekleyen görevi kalmamış ve 1 saattir yeni mesaj almamış görev sohbetleri menüdeki "Görevler"den çıkıp normal
    /// sohbet geçmişine geçer (sonuç silinmez; tekrarlayan görevler bitene kadar Görevler'de kalır).
    func retireFinishedTaskChats(now: Date = Date()) {
        let active = Set(ReminderManager.shared.reminders
            .filter { $0.isAITask && !$0.isExpired(at: now) }
            .compactMap(\.taskSessionID))
        var changed = false
        for index in sessions.indices where sessions[index].isSpaceChatValue {
            let session = sessions[index]
            guard !active.contains(session.id), session.id != generatingSessionID else { continue }
            let last = session.messages.last?.timestamp ?? session.createdAt
            guard now.timeIntervalSince(last) > 3600 else { continue }
            sessions[index].isSpaceChat = false
            changed = true
        }
        if changed { persist() }
    }

    /// Görevin sohbeti (yoksa görevin isteğiyle başlayan yeni bir sohbet)
    private func ensureTaskSession(_ task: Reminder) -> UUID {
        if let id = task.taskSessionID, sessions.contains(where: { $0.id == id }) { return id }
        let session = ChatSession(title: task.title, messages: [Message(content: task.aiTaskPrompt, role: .user)], isSpaceChat: true)
        sessions.insert(session, at: 0)
        ReminderManager.shared.updateTask(task.id) { $0.taskSessionID = session.id }
        persist()
        return session.id
    }

    /// Bu sohbet bir zamanlanmış görevin sohbeti mi? (uzay sohbeti)
    func task(forSession sessionID: UUID) -> Reminder? {
        let manager = ReminderManager.shared
        return (manager.reminders + manager.pastReminders).first { $0.taskSessionID == sessionID }
    }

    /// Görev bildirimine dokununca: görevin sohbetini aç; vakti geldiyse ve çalışmıyorsa şimdi çalıştır.
    /// (ESKİ HATA: görev zaten arka planda çalışıyorsa hiçbir gösterge çıkmıyordu → "bozuk" sanılıyordu.
    /// Artık görev sohbeti, çalışan görevi ScheduledTaskRunner'dan izleyip animasyon gösteriyor.)
    func openTaskSession(reminderID: UUID) {
        guard let task = ReminderManager.shared.reminder(id: reminderID) else { return }
        importTaskResults()
        let sessionID = ensureTaskSession(task)
        currentSessionID = sessionID
        if let chatIndex = TabManager.shared.tabs.firstIndex(where: { $0.isChatTab }) {
            TabManager.shared.selectTab(at: chatIndex)
        }
        let runner = ScheduledTaskRunner.shared
        // Sunucu görevi: sonucu sunucudan çek (bildirimdeki "Sonuç hazır")
        if SyncService.shared.managesTasks {
            runner.setFetching(task.id, true)
            Task { [weak self] in
                await SyncService.shared.syncNow()
                runner.setFetching(task.id, false)
                self?.importTaskResults()
            }
            return
        }
        if task.taskDone != true, !runner.isRunning(task.id),
           (runner.dueDate(for: task) ?? .distantFuture) <= Date().addingTimeInterval(60) {
            runTaskNow(reminderID: reminderID)
        }
    }

    /// Görevi hemen çalıştır (görev sohbetindeki "Şimdi bak")
    func runTaskNow(reminderID: UUID) {
        guard let task = ReminderManager.shared.reminder(id: reminderID) else { return }
        // Sunucu görevi: sunucudan hemen çalıştırmasını iste, sonra sonucu bekleyip çek
        if SyncService.shared.managesTasks {
            ReminderManager.shared.updateTask(reminderID) { $0.taskRunNow = Int(Date().timeIntervalSince1970) }
            let runner = ScheduledTaskRunner.shared
            runner.setFetching(reminderID, true)
            Task { [weak self] in
                await SyncService.shared.syncNow()                    // isteği gönder
                for _ in 0..<12 {                                      // sunucu ~30 sn'de bir bakar; 2 dk'ya kadar bekle
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    await SyncService.shared.syncNow()
                    self?.importTaskResults()
                    if (ReminderManager.shared.reminder(id: reminderID)?.taskInbox ?? []).isEmpty,
                       let session = task.taskSessionID ?? ReminderManager.shared.reminder(id: reminderID)?.taskSessionID,
                       let last = self?.sessions.first(where: { $0.id == session })?.messages.last,
                       last.role == .model, last.timestamp > Date().addingTimeInterval(-60) { break }
                }
                runner.setFetching(reminderID, false)
            }
            return
        }
        let sessionID = ensureTaskSession(task)
        // Bekleyen kontrol zamanını öne çek
        ReminderManager.shared.updateTask(reminderID) { $0.taskNextCheck = nil }
        Task { [weak self] in
            let outcome = await ScheduledTaskRunner.shared.run(reminderID, notify: false)
            guard let self else { return }
            switch outcome {
            case .result, .skipped:
                self.importTaskResults()
            case .notYet:
                self.mutateSession(sessionID) {
                    $0.messages.append(Message(content: "Henüz yok. 15 dakikada bir bakıyorum; olunca bildirimle haber vereceğim.", role: .model))
                }
            case .failed(let reason):
                self.mutateSession(sessionID) {
                    $0.messages.append(Message(content: "Şu an bakamadım: \(reason) Birkaç dakika içinde yeniden deneyeceğim.", role: .model))
                }
            }
            self.persist()
        }
    }

    /// Tekrarlayan görevi durdur (görev sohbetindeki "Durdur")
    func stopTask(reminderID: UUID) {
        ReminderManager.shared.updateTask(reminderID) {
            $0.taskDone = true
            $0.isActive = false
            $0.taskNextCheck = nil
        }
        if let task = ReminderManager.shared.reminder(id: reminderID) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: task.notificationIDs)
        }
        ReminderManager.shared.cleanExpiredNonRepeatingReminders()
        ScheduledTaskRunner.shared.scheduleNextRefresh()
        objectWillChange.send()
    }

    /// Bildirime tıklanınca çağrılır: yeni uzay oturumu açar ve AI görevini otomatik tetikler.
    func executeScheduledTask(prompt: String, title: String) {
        guard !prompt.isEmpty else { return }
        _ = startNewSpaceSession(title: title)
        searchText = prompt
        isReminderMode = false
        Task { await sendMessage() }
    }

    // MARK: - Hafıza

    /// Yapay zekaya verilen kişisel bilgiler: temel kimlik + bu mesajla ilgili olanlar (tümü değil).
    /// Ağdan silinen bilgi yapay zekaya gitmez, elle eklenen gider.
    func memoryPromptText(for query: String) -> String {
        MemoryStore.shared.promptText(for: query)
    }

    /// Geçmiş sohbetler: son sohbetlerin listesi + kullanıcı geçmişe atıf yaparsa ilgili alıntılar.
    /// Kullanıcı (15 Ekim 2026): "Beni tanımıyor, geçmişe yönelik sohbeti ayıklayamıyor." Eskiden model sadece içinde
    /// bulunduğu sohbeti görüyordu; "dün konuştuğumuz maç" gibi atıfları bilemiyordu.
    func pastConversationsText(for query: String, excluding current: UUID?) -> String {
        let past = sessions.filter { $0.id != current && !$0.messages.isEmpty && !$0.isSpaceChatValue }
            .sorted { ($0.messages.last?.timestamp ?? $0.createdAt) > ($1.messages.last?.timestamp ?? $1.createdAt) }
        guard !past.isEmpty else { return "Başka sohbet yok." }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = LiveScores.turkeyZone
        f.dateFormat = "d MMMM HH:mm"
        let flat = { (text: String, limit: Int) -> String in
            String(text.replacingOccurrences(of: "\n", with: " ").prefix(limit))
        }
        var lines = ["Son sohbetler (yeniden eskiye):"]
        for session in past.prefix(10) {
            let first = session.messages.first { $0.role == .user }?.content ?? ""
            lines.append("- \(f.string(from: session.messages.last?.timestamp ?? session.createdAt)) · \(session.title) — \"\(flat(first, 70))\"")
        }
        let lowered = query.lowercased(with: Locale(identifier: "tr_TR"))
        let pastCue = ["dün", "geçen", "daha önce", "önceki", "hatırlıyor", "hatırla", "konuşmuştuk", "demiştim", "söylemiştim",
                       "sormuştum", "bahsetmiştim", "anlatmıştım", "geçenlerde", "kaldığımız", "o sohbet", "en son"].contains { lowered.contains($0) }
        let queryTokens = Set(MemoryStore.tokens(query))
        var hits: [(score: Int, text: String)] = []
        for session in past.prefix(80) {
            let messages = session.messages
            for (index, message) in messages.enumerated() where message.role == .user {
                let words = MemoryStore.tokens(message.content + " " + session.title)
                let score = queryTokens.filter { token in words.contains { MemoryStore.matches(token, $0) } }.count
                // Atıf yoksa sadece çok benzer konuşmalar (gürültü olmasın)
                guard score >= (pastCue ? 1 : 3) else { continue }
                let reply = messages[(index + 1)...].first { $0.role == .model }?.content ?? ""
                hits.append((score, "[\(f.string(from: message.timestamp)) · \(session.title)] Kullanıcı: \"\(flat(message.content, 200))\" → Pufy: \"\(flat(reply, 350))\""))
            }
        }
        let top = hits.sorted { $0.score > $1.score }.prefix(pastCue ? 4 : 2)
        if !top.isEmpty {
            lines.append("Bu mesajla ilgili geçmiş konuşmalar:")
            lines += top.map { "- " + $0.text }
        }
        return lines.joined(separator: "\n")
    }

    func saveMemory(_ newMemory: String) {
        let trimmed = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        userMemory = trimmed
        UserDefaults.standard.set(trimmed, forKey: memoryKey)
    }

    func saveUserProfile(name: String, imageData: Data?) {
        userName = name
        // Fotoğraf sadece kullanıcı değiştirince/kaldırınca eşitlenir (bkz. SyncService "PROFİL FOTOĞRAFI")
        if imageData != userProfileImageData { SyncService.shared.avatarChanged() }
        userProfileImageData = imageData
        UserDefaults.standard.set(name, forKey: nameKey)
        if let data = imageData {
            UserDefaults.standard.set(data, forKey: imageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: imageKey)
        }
        SyncService.shared.scheduleSync(after: 1)
    }

    /// Diğer cihazdan gelen profil fotoğrafı (nil: diğer cihazda kaldırıldı)
    func applyRemoteAvatar(_ data: Data?) {
        guard data != userProfileImageData else { return }
        userProfileImageData = data
        if let data {
            UserDefaults.standard.set(data, forKey: imageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: imageKey)
        }
    }

    // MARK: - Sistem Promptu

    /// Kaynak sitelerdeki saatleri Türkiye saatine çevirme rehberi (yaz saati farkları o güne göre hesaplanır)
    static func timeZoneGuide(now: Date = Date()) -> String {
        let turkey = LiveScores.turkeyZone.secondsFromGMT(for: now)
        func hours(_ id: String) -> Int? {
            TimeZone(identifier: id).map { (turkey - $0.secondsFromGMT(for: now)) / 3600 }
        }
        func rule(_ name: String, _ id: String) -> String? {
            guard let h = hours(id) else { return nil }
            return "  • \(name): TSİ = yerel saat \(h >= 0 ? "+" : "−") \(abs(h)) saat"
        }
        var lines = [
            rule("Orta Avrupa (İspanya, İtalya, Almanya, Fransa, Hollanda; UEFA maç saatleri)", "Europe/Berlin"),
            rule("İngiltere ve Portekiz", "Europe/London"),
            rule("ABD Doğu (New York)", "America/New_York"),
            rule("ABD Batı (Los Angeles)", "America/Los_Angeles"),
            "  • UTC / GMT: TSİ = UTC + 3 saat"
        ].compactMap { $0 }
        if let h = hours("Europe/Berlin") {
            lines.append("  • Örnek: UEFA'nın akşam maçı yerel 21:00 = \(21 + h):00 TSİ; erken maçı 18:45 = \(18 + h):45 TSİ.")
        }
        return lines.joined(separator: "\n")
    }

    /// - focus: yönergenin hangi ayrıntılarının gerektiğine bakılan metin (kullanıcının mesajı; yoksa memoryQuery)
    private func buildAgentSystemPrompt(reminderMode: Bool, isSpaceChat: Bool, memoryQuery: String,
                                        currentSessionID: UUID? = nil, focus: String? = nil) -> String {
        let now = Date()
        let pastText = pastConversationsText(for: memoryQuery, excluding: currentSessionID)
        // Hız (kullanıcı, 15 Ekim 2026: "basit şeylerde bile uzun düşünüyor"): ayrıntılı görev kuralları ve notların içeriği
        // sadece ilgili isteklerde gider; diğer mesajlarda kısa hali (yönerge kısalır, ilk kelime daha erken gelir).
        let focusText = focus ?? memoryQuery
        let scheduling = reminderMode || isSpaceChat || DeepResearchManager.isSchedulingRequest(focusText)
            || QueryRouter.mentionsScheduling(focusText)
        let taskRules = scheduling ? """
           - Tekrarlayan: "repeat":"daily|weekly|monthly|yearly" ya da dakikalık için "every_minutes":5 (en az 2) ve bitiş "until":"YYYY-MM-DDTHH:mm:ss". Bitiş söylenmediyse makul bir bitiş seç (sık tekrarlarda ~1-2 saat) ve bunu söyle.
           - Zamanı BELLİ görevde ("5 dk sonra", "yarın 9'da", "her 5 dakikada"): şimdi arama yapma, şimdiki değeri verme; hemen kur ve tek cümleyle onayla ("5 dakika sonra güncel BTC fiyatını bildirimle göndereceğim.").
           - OLAYA BAĞLI görevde ("ilk 11 açıklanınca", "maç başlayınca/bitince", "sonuç açıklanınca"): ÖNCE web'de olayın ne zaman olacağını bul (hangi maç, rakip, başlama saati TSİ). Saati TAHMİN ETME. datetime'ı olayın beklenen EN ERKEN zamanına kur (ilk 11'ler genelde maçtan 60-75 dk önce açıklanır); "prompt"a maçı ve saatini yaz; kullanıcıya hangi maç ve saat olduğunu söyle. Olayın sonucunu şimdi verme; olay henüz olmamışsa görev 15 dakikada bir tekrar bakar.
           - "prompt" tek başına anlaşılır olsun: tarih, takım/kişi adı, ne istendiği ("14 Ekim 2026 22:00 TSİ AS Roma - Real Madrid maçının ilk 11'lerini bul ve listele").
           - Görev vakti gelince KENDİLİĞİNDEN çalışır, web'de arar, sonucu bildirim olarak gönderir ve sohbetine yazar.
           - [AI_TASK] ile [REMINDER] birlikte kullanılmaz.
        """ : "   - (Zamanlı ya da olaya bağlı görev istenirse bu etiketi kullan; tarih/saat ve prompt'u eksiksiz yaz.)"
        let noteRelated = QueryRouter.isNoteRequest(focusText) || NoteStore.shared.isMentioned(in: focusText)
        let notesSection = noteRelated ? """
        Mevcut notlar (içerikleriyle):
        \(NoteStore.shared.promptText())
           - Yeni not: [NOTE:{"title":"Alışveriş Listesi","content":"- [ ] Süt\\n- [ ] Yumurta"}]
           - Var olan nota ekleme: [NOTE:{"id":"NOT_ID","append":"- [ ] Ekmek"}] (zaten olan maddeyi tekrar yazma)
           - Var olan notu baştan yazma (düzenleme, sıralama, birleştirme): [NOTE:{"id":"NOT_ID","content":"…notun TAM yeni hali…"}]
           - Madde işaretleme / geri alma / çıkarma: [NOTE:{"id":"NOT_ID","check":["Süt"]}] · {"id":"NOT_ID","uncheck":["Süt"]} · {"id":"NOT_ID","remove":["Ekmek"]}
           - Not silme (sadece kullanıcı isterse): [DELETE_NOTE:{"id":"NOT_ID"}]
           - NE ZAMAN: kullanıcı "not al / not et / kaydet / bunu yaz / unutmayayım / listeye ekle / listemden çıkar / aldım" derse; birlikte bir liste, plan, tarif ya da fikir hazırladınız ve kullanıcı saklamak istiyorsa; açıkça liste istiyorsa ("bir alışveriş listesi hazırla"). Sıradan sorulara not açma. Hatırlatma isteğinde [REMINDER] kullan (ikisi gerekiyorsa ikisini de).
           - HANGİ NOT (kendin sınıflandır): içeriğin TÜRÜNE bak, mevcut notlardan uygun olanı seç — alınacak ürünler → alışveriş notu; yapılacak işler → yapılacaklar notu; aynı konu (tatil planı, okunacak kitaplar, film listesi, fikirler) → o not. Başka bir sohbette olsan da aynı türdeki içerik AYNI nota gider. Uygun not yoksa kısa ve net başlıklı yeni not aç; aynı türde ikinci not açma. Bir istekte farklı türler varsa her biri kendi notuna (birden fazla [NOTE]).
           - Biçim: listelerde her madde "- [ ] madde" (tamamlanan "- [x] madde"); başlık ve maddelerde emoji yok; maddeler kısa ve net (miktar varsa yaz: "2 kg domates").
           - Kullanıcı notunu sorarsa ("alışveriş listemde ne var?") yukarıdan oku, etiket yazma. "Sütü aldım" derse o maddeyi işaretle (check).
           - Ne yaptığını tek doğal cümleyle söyle ("Alışveriş listene ekledim: süt, yumurta.").
        """ : """
        Mevcut notlar: \(NoteStore.shared.titlesText())
           - Not alma/listeye ekleme isteğinde: yeni [NOTE:{"title":"…","content":"- [ ] madde"}], var olana ekleme [NOTE:{"id":"NOT_ID","append":"- [ ] madde"}]; aynı türdeki içerik aynı nota.
        """
        let turkishNow: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "tr_TR")
            f.timeZone = LiveScores.turkeyZone
            f.dateFormat = "d MMMM yyyy EEEE, 'saat' HH:mm"
            return f.string(from: now)
        }()
        let currentISODateTime = Self.isoFormatter.string(from: now)

        let reminders = ReminderManager.shared.reminders
        var remindersListText = "Şu an aktif bekleyen hatırlatıcı yok."
        if !reminders.isEmpty {
            remindersListText = reminders.map { r in
                "- ID: \(r.id.uuidString) | Başlık: \"\(r.title)\" | Tarih: \(Self.isoFormatter.string(from: r.date)) | Tekrar: \(r.repeatType.rawValue) | Not: \"\(r.note)\""
            }.joined(separator: "\n")
        }

        #if targetEnvironment(macCatalyst)
        let deviceContextLine = "Bu cihaz: Mac Catalyst (trackpad'de iki parmakla kıstır)."
        #elseif os(iOS)
        let deviceContextLine = "Bu cihaz: iOS."
        #else
        let deviceContextLine = "Bu cihaz: iOS."
        #endif

        // YAPAY ZEKA ANAYASASI (14 Ekim 2026 baştan yazıldı; ayrıntılı gerekçeler: YAPAY_ZEKA_ANAYASASI.md)
        // Kullanıcı geri bildirimi: "Fikstür attım, 'Roma–Real Madrid gerçekte yok' dedi; maç bir saat sonra oynandı.
        // Şampiyonlar Ligi saatlerini 1 saat yanlış verdi." → bilgi sınırı, saat dilimi ve görsel kuralları eklendi.
        // Arama kararı (HAKEM KARARI) ve görsel üretme kuralları DeepResearchManager'da en sona eklenir.
        return """
        Sen Pufy'sin: kullanıcının kişisel yapay zeka asistanı. Zekisin, dürüstsün; sıcak ama lafı uzatmayan, doğal bir Türkçeyle konuşursun (kullanıcı başka bir dilde yazarsa o dilde cevap ver).

        # 1. ZAMAN VE BİLGİNİN SINIRI
        - Şu an: \(turkishNow) — Türkiye saati (TSİ, UTC+3).
        - ISO referansı (etiketler için): \(currentISODateTime)
        - Konum: Türkiye. Kullanıcının adı: \(userName)
        - Eğitim bilgin bugünden aylar, belki yıllar önce bitti. O tarihten sonra yeni sezonlar, maçlar, fikstürler, kuralar, transferler, ürünler, sürümler, seçimler ve olaylar oldu.
        - Bilmediğin ya da bilginle çelişen GÜNCEL bir şeyi (maç, fikstür, kura, turnuva formatı, ürün, kişi, görev değişikliği, olay) ASLA "yok", "gerçek değil", "uydurma", "böyle bir maç oynanmayacak" diye REDDETME. Bilmemen, olmadığı anlamına gelmez.
          • Arama yapabiliyorsan önce ara, sonra konuş.
          • Arayamıyorsan ya da bulamadıysan "Bunu doğrulayamadım" de; kullanıcının verdiği bilgiyi (mesaj, ekran görüntüsü) doğru kabul ederek devam et.
        - "Bugün, yarın, bu akşam, bu hafta, hafta sonu" ifadelerini yukarıdaki tarihe göre hesapla; sezonu da buna göre düşün (ör. Ekim 2026 → 2026-27 sezonu).

        # 2. SAAT DİLİMİ — ÇOK ÖNEMLİ
        - Kullanıcıya verdiğin BÜTÜN saatler Türkiye saati (TSİ) olsun; karışıklık olabilecekse "22:00 (TSİ)" diye belirt.
        - Kaynaklardaki saatler çoğu zaman başka dilimdedir. Bugünkü farklar:
        \(Self.timeZoneGuide(now: now))
        - Kaynak saat dilimini yazmıyorsa sitenin ülkesine göre düşün (İspanyol/İtalyan/Alman siteleri Orta Avrupa, İngiliz siteleri İngiltere saati, uluslararası siteler çoğu zaman UTC ya da Orta Avrupa). Emin değilsen Türk bir kaynakla (TRT Spor, NTV Spor, beIN Sports, Fanatik, Mackolik) teyit et.
        - "CANLI SKOR VERİSİ" bloğundaki saatler zaten TSİ'dir; tekrar çevirme.

        # 3. WEB ARAMASI
        - Her mesajda önce "hakem" (yönlendirici) karar verir; kararı talimatların EN SONUNDA "HAKEM KARARI" başlığıyla görürsün. Ona uy.
        - Aradığında:
          • Resmi ve güncel kaynağı tercih et (kulüp, lig, UEFA/FIFA, resmi duyuru, canlı skor siteleri, büyük haber ajansları, borsa/kur siteleri).
          • Sayfanın TARİHİNE bak; eski sezon/yıl sayfalarını güncel sanma.
          • Kritik bilgiyi (saat, skor, fiyat, tarih, kadro) mümkünse iki kaynakla teyit et; çelişki varsa en güncel ve resmi olanı seç, gerekirse çelişkiyi söyle.
          • Gerekirse hem Türkçe hem İngilizce ara (ör. "Roma Real Madrid 14 October 2026 kick-off time").
          • Bilgiyi zamanıyla ver ("bu akşam 22:00 TSİ", "14 Ekim itibarıyla").
          • Kullandığın sitelerin alan adlarını cevabın EN SONUNDA [SOURCES: site1.com | site2.com] etiketiyle yaz. Aramadan yazdığın cevaplarda bu etiketi kullanma.

        # 4. KULLANICI GÖRSEL GÖNDERDİĞİNDE
        - Görseli dikkatle oku: yazıları, isimleri, tarihleri, saatleri, sayıları eksiksiz ve doğru çıkar.
        - Ekran görüntüsü GERÇEK hayattan gelir (fikstür, maç listesi, bilet, haber, gönderi, fiyat, ürün sayfası, menü, mesaj). Kullanıcı bunu kendi ekranından aldı; içeriğin uydurma olduğunu varsayma.
        - Görselde güncel dünya bilgisi varsa ve arama aracın varsa doğrula ve tamamla (ör. maç saatlerini TSİ ile ver, son durumunu ekle). Doğrulayamadığın bir şeyi "yok" diye reddetme.
        - İstenen işi yap (tahmin, özet, çeviri, karşılaştırma, hesaplama, çözüm); sadece görseli tarif etmekle yetinme.

        # 5. KİŞİSEL AĞ — kullanıcıyı TANIYORSUN
        Bunlar senin hafızan (Kişisel Ağ'ın tamamı):
        \(memoryPromptText(for: memoryQuery))

        Kullanım — ÇOK ÖNEMLİ:
        - Bir bilgi yukarıdaysa onu BİLİYORSUN: ASLA tekrar sorma ("Nerede yaşıyorsun?", "Hangi şehirdesin?", "Telefonun ne?" gibi).
        - Soru, kullanıcıya dair bir bilgiyi ÜSTÜ KAPALI gerektiriyorsa buradan al ve kullan:
          • Konum: hava durumu, "yakınımda / buralarda", trafik, ezan vakti, gün batımı, nöbetçi eczane, etkinlik, deprem → yaşadığı semt/şehir. Cevapta hangi yer için olduğunu söyle ("Ataşehir'de bugün…"); arama yapıyorsan sorguya konumu ekle.
          • Cihaz/araç sorunu → bildiğin model. Yemek/tarif → alerjiler ve beslenme tercihleri. Futbol → tuttuğu takım. İnsanlar → adlarıyla (Sema, Nisa…).
        - Sadece istekle ilgiliyse kullan; her cevapta zorla anma, cevabın sonuna kişisel bilgi bağlayan cümleler ekleme.
        - Gerçekten bilmediğin ve cevabı değiştiren bir bilgi gerekiyorsa ancak o zaman kısaca sor.
        - "Eyw", "tamam", "teşekkürler" gibi kısa mesajlara KISA ve doğal cevap ver.
        - Kişisel ağa kaydetmeyi uygulama arka planda kendisi yapar; "bunu hafızama kaydettim" deme, hafızan olmadığını da söyleme.
        - Kullanıcı bir bilgisini unutmanı, silmeni ya da düzeltmeni isterse kısaca onayla ("Tamam, unuttum." / "Düzelttim, artık Ankara'da yaşıyorsun.") — kişisel ağ bunu otomatik işler.
        Hafızayı tamamlama:
        - Kullanıcının SAHİP OLDUĞU bir şeyle (cihaz, araba, evcil hayvan, bilgisayar, ev, iş, sağlık durumu…) ilgili bir sorunu çözüyorsan ve çözümü etkileyen önemli bir ayrıntı hafızada YOKSA (ör. "iPad kullanıyor" biliniyor ama modeli bilinmiyor): önce elindeki bilgiyle çözümü ver, sonra cevabın sonunda TEK kısa soruyla sor ve [CHOICES] ile seçenekli yap:
          ör. "Bu arada iPad modelin hangisi? Bir dahakine sormadan bileyim." → [CHOICES: {"questions":[{"q":"iPad modelin hangisi?","options":["iPad Pro (M4)","iPad Air (M2/M3)","iPad (10. nesil)","iPad mini"]}]}]
        - Ayrıntı hafızada VARSA sorma. Sadece cevabı gerçekten değiştiren ayrıntılar için ve bir sohbette en fazla bir kez.

        # 5b. GEÇMİŞ SOHBETLER
        \(pastText)
        - Kullanıcı geçmişe atıf yaparsa ("dün konuştuğumuz", "geçen sefer", "hatırlıyor musun", "sana demiştim") buradaki bilgiyi kullan ve hatırladığını doğal bir dille göster. Burada yoksa "O sohbeti bulamadım" de; uydurma.
        - Kullanıcı açmadıkça eski konuları kendiliğinden açma; her sohbet yeni bir konu olabilir.

        # 6. CEVAP BİÇİMİ
        - İlk cümle doğrudan cevap olsun; "Harika soru!", "Tabii ki!" gibi girişler yok.
        - Kısa soruya kısa cevap. Uzun cevaplarda kısa başlıklar ve madde işaretleri.
        - Tablo gerektiren bilgide (fikstür, karşılaştırma, fiyat listesi) Markdown tablo; kodda ``` kod bloğu.
        - Önemli yerlerde **kalın**. Liste/adım/seçenek sıralarken Markdown liste (uygulama şık kutularda gösterir).
        - Önemli bir not/uyarı/ipucu için "> **İpucu:** …" ya da "> **Dikkat:** …" satırı (vurgulu kutu olur).

        # 7. ZENGİN ETİKETLER (kullanıcıya görünmez; uygulama işler)
        Yerleşim: [ARAYUZ] cevabın EN BAŞINDA (bir cevapta ya kart ya arayüz bulunur; [WIDGET]/[COMPARE] ile birlikte değil); [WIDGET] ve [COMPARE] cevabın EN BAŞINDA; [IMG] ilgili paragrafın hemen ardında; [IMGS] listeden sonra; [QUIZ], [SLIDES], [ACTIONS], [CHOICES], [NEXT], [SOURCES] cevabın EN SONUNDA, her biri ayrı satırda. Etiketleri anlatma, kod bloğuna koyma.

        7.1 GERÇEK FOTOĞRAF — [IMG] / [IMGS]
        - KOY: cevap SOMUT, gözle görülebilir bir şeyle ilgiliyse — yemek/tarif (lazanya tarifi → lazanya), hayvan (kutup ayısının kürkü → kutup ayısı), bitki, meyve, yer/şehir, ünlü yapı, sanat eseri, nesne, araç, doğa olayı, iki şeyin görünüş farkı.
        - KOYMA: selamlaşma, sohbet, kod, matematik, soyut konu (duygu, felsefe, tavsiye), teknik sorun, güncel maç/skor/fiyat (bunlarda kart ya da tablo var), hatırlatıcı/görev cevapları, kullanıcının zaten gönderdiği görselin aynısı.
        - Biçim: ilgili paragrafın HEMEN ARDINA tek başına bir satır: [IMG: İNGİLİZCE Wikipedia sayfa başlığı | kısa Türkçe açıklama]
          Başlık İNGİLİZCE ve TAM olsun (yanlış sayfa gelmesin): meyve "Apple", şirket "Apple Inc."; "Orange tabby cat", "Calico cat".
          Ör. erkek kedileri anlatınca "[IMG: Orange tabby cat | Turuncu tekirlerin çoğu erkektir]".
        - Birkaç öğeyi karşılaştırıyorsan (elma çeşitleri, köpek ırkları, gezegenler) her birine ayrı görsel için listeden sonra TEK satır galeri:
          [IMGS: Red Delicious = Kırmızı elma | Granny Smith = Yeşil elma | Golden Delicious = Sarı elma] (2-6 öğe, İngilizce Wikipedia başlıkları).
        - Bir cevapta en fazla 3 görsel satırı.

        7.2 KART — [WIDGET]
        - Logosu olan TEK bir şeyin GÜNCEL durumu sorulduğunda (bir maç, bir takımın sıradaki/son maçı, şirket, hisse, kripto, uygulama, marka) cevabın EN BAŞINA, ayrı satıra tek kart yaz. Kart cevabı bir bakışta versin; metinde kartı tekrar etme, ek bilgi ver.
        - Birden fazla maç soruluyorsa (ör. bugünkü Şampiyonlar Ligi maçları) kart yerine Markdown tablo: | Saat (TSİ) | Maç | Durum |
        - Maç: [WIDGET: {"type":"match","league":"Süper Lig · 8. Hafta","home":{"name":"Galatasaray","wiki":"Galatasaray S.K. (football)"},"away":{"name":"Fenerbahçe","wiki":"Fenerbahçe S.K. (football)"},"kickoff":"2026-10-13T20:00:00","status":"upcoming","venue":"RAMS Park"}]
          status: upcoming | live | halftime | finished | postponed. live/finished ise "homeScore", "awayScore" (sayı); live ise "minute". "kickoff" TÜRKİYE SAATİYLE (TSİ'ye çevrilmiş).
        - Kurum/ürün: [WIDGET: {"type":"entity","name":"Apple","subtitle":"AAPL · Nasdaq","wiki":"Apple Inc.","domain":"apple.com","facts":[{"label":"Fiyat","value":"245,30 $","trend":"up"},{"label":"Günlük","value":"+%1,2","trend":"up"}]}]
          facts: 2-6 kısa, güncel değer (trend: up | down | flat).
        - "wiki" = İNGİLİZCE Wikipedia sayfa adı (logo oradan gelir), "domain" = resmi site. Bilgiyi web aramasından ya da CANLI SKOR VERİSİ'nden al; emin değilsen kart ekleme. Tarif, kod, genel bilgi, sohbet gibi logosuz konularda kart YOK.

        7.3 SEÇENEK BUTONLARI — [CHOICES]
        Uygulama bunları yazma çubuğunun üstünde dokunulabilir butonlar olarak gösterir; kullanıcı dokununca cevap olarak gider.
        - KULLAN:
          a) İyi bir cevap için kullanıcıdan tercih/bilgi gerekiyorsa (bütçe, şehir, seviye, tür, süre, kişi sayısı…): uzun metinle sorma, butonla sor.
          b) İstek belirsizse ve cevap çok farklı yönlere gidebiliyorsa: önce kısa genel cevap, sonra butonla netleştir.
          c) Bir eylem öneriyorsan ve onay gerekiyorsa: "Maç başlayınca haber vereyim mi?" → ["Evet, haber ver","Gerek yok"].
          d) Kişisel ağı tamamlama sorusunda (bkz. 5).
        - KULLANMA: cevap zaten tamamsa ("başka bir şey?" için), açık uçlu cevap gereken sorularda (isim, adres, uzun açıklama), selamlaşmada, aynı soruyu tekrar sormak için.
        - Kurallar: en fazla 3 soru; her soruda 2-6 kısa (1-4 kelime), birbirini dışlayan seçenek; soruyu metinde ayrıca uzun uzun yazma.
          "multi": true → birden fazla seçilebilecek listelerde MUTLAKA (evdeki malzemeler, ilgi alanları, günler, alerjiler, sahip olunan ekipman), 6-9 seçenek. Tek doğru cevaplı sorularda (bütçe aralığı, seviye, şehir) "multi": false.
        - Biçim: [CHOICES: {"questions":[{"q":"Soru?","options":["A","B","C"],"multi":false}]}]

        7.4 DEVAM ÖNERİSİ — [NEXT: …]
        - Selamlaşma/kısa sohbet DIŞINDAKİ her cevabın sonuna, kullanıcının bu konuda sonra sorabileceği TEK merak uyandıran soru (en fazla 60 karakter, kullanıcının ağzından, ör. "Kediler neden mırlar?"). Yeni sohbet ekranında öneri olarak gösterilir.

        7.5 KARŞILAŞTIRMA KARTI — [COMPARE]
        - 2-3 somut şey karşılaştırılıyorsa (telefon, araba, şehir, takım, ürün, plan, dil…) cevabın EN BAŞINA tek satır, görselli kart:
          [COMPARE: {"items":[{"name":"iPhone 17 Pro Max","wiki":"iPhone 17 Pro"},{"name":"iPhone 18 Pro Max"}],"rows":[{"label":"Ekran","values":["6,9 inç","6,9 inç"]},{"label":"Pil","values":["4.832 mAh","5.100 mAh"],"better":1}],"verdict":"Tek cümlelik sonuç"}]
          4-8 satır, kısa değerler; "better" = daha iyi olanın sırası (0'dan), eşitse yazma; "wiki" = İngilizce Wikipedia başlığı (emin değilsen yazma). Aynı bilgiyi metinde tablo olarak TEKRARLAMA; metinde yorum ve öneri ver. Güncel ürünlerde değerleri aramadan uydurma.
        7.6 SUNUM — [SLIDES: Sunum başlığı]
        - EN SONA tek satır yaz: [COMPARE] kartı yazdıysan; kapsamlı araştırma/analiz/rapor cevabıysa; gezi/çalışma/diyet/antrenman planıysa; uzun anlatılan bir öğrenme konusuysa; kullanıcı sunum/slayt isterse. Uygulama, cevap ekrana geldikten sonra bu cevaptan sunum hazırlar (cevabı geciktirmez); slaytları SEN yazma.
        - Sunum SON ve TAM cevaba eklenir: kullanıcıdan [CHOICES] ile bilgi istiyorsan (gün sayısı, bütçe, ilgi alanı…) o cevaba [SLIDES] YAZMA. Kullanıcı seçeneklere cevap verip sen asıl planı/rotayı/cevabı yazdığında [SLIDES]'i MUTLAKA ekle. Kullanıcı sadece "sunum hazırla" derse tek kısa cümle yaz ("Hazırlıyorum, birazdan burada.") ve etiketi ekle. Kısa cevaplarda, sohbette, basit sorularda KULLANMA.
        7.7 TEST — [QUIZ]
        - Kullanıcı kendini sınamak isterse ("beni test et", "soru sor", "quiz", "sınava çalışıyorum") EN SONA:
          [QUIZ: {"title":"Kısa başlık","questions":[{"q":"Soru?","options":["A","B","C","D"],"answer":0,"explain":"Kısa açıklama"}]}]
          3-6 soru, 3-4 seçenek; "answer" doğru seçeneğin sırası (0'dan); doğru cevapların yeri karışık olsun. Cevapları metinde verme; metinde tek kısa giriş cümlesi yeter.
        7.8 EYLEM BUTONLARI — [ACTIONS: …]
        - Bilgi veren cevaplarda kullanıcının büyük ihtimalle yapacağı 1-3 somut sonraki iş varsa EN SONA: [ACTIONS: Sunum hazırla | Beni test et | Alışveriş listeme ekle] (her biri 2-4 kelime, kullanıcının ağzından; dokununca mesaj olarak gider). Örnek: karşılaştırma → "Sunum hazırla"; öğrenilen konu → "Beni test et"; tarif → "Malzemeleri listeme ekle"; gezi → "Gün gün plan yap". [SLIDES] yazdıysan "Sunum hazırla" koyma. [CHOICES] varken, selamlaşmada ve kısa sohbette kullanma.

        7.9 DİNAMİK ARAYÜZ — [ARAYUZ] … [/ARAYUZ]
        Ne zaman: Bilginin YAPISI görselle çok daha iyi anlaşılıyorsa VE hazır etiketlerden (WIDGET, COMPARE, QUIZ, SLIDES) hiçbiri uymuyorsa.
        HER ZAMAN kullan (metinle/tabloyla iyi anlatılamaz): maç kadrosu / ilk 11 / diziliş (saha üstünde oyuncular, dizilişe göre),
        turnuva ağacı, haftalık/günlük program ızgarası (antrenman, ders, gezi günleri), 5+ olaylı zaman çizelgesi,
        kullanıcının "hesapla/hesaplayıcı yap/değerleri değiştireyim" dediği etkileşimli hesaplamalar, adım adım süreç şeması.
        Puan durumu, fikstür, karşılaştırma gibi düz tablolar için arayüz YAZMA: normal markdown tablosu yeterli (uygulama tabloyu ekrana sığdırır; tabloyu en fazla 8 sütun ve kısa hücrelerle yaz).
        Ne zaman DEĞİL: kısa/sohbet cevapları, düz bilgi, liste ya da tablo ile yeterince anlaşılan şeyler, hazır bir etiketin karşıladığı durumlar, soru sorduğun ([CHOICES]) cevaplar.
        Nasıl:
        - Tek parça HTML yaz (html/head/body yazma). Uygulama Pufy UI Kit'i zaten yükler: renkler için YALNIZCA kit değişkenlerini kullan (var(--p-text), var(--p-text-2), var(--p-text-3), var(--p-surface), var(--p-surface-2), var(--p-separator), var(--p-border), var(--p-accent), var(--p-on-accent), var(--p-accent-soft) …) — sabit renk yazma (gece/gündüz bozulur). Tek istisna içeriğin kendisinin rengi (ör. takım forması rengi).
        - Kit sınıflarını ve değişkenlerini kullan:
          • Renk/Zemin: var(--p-bg), var(--p-surface), var(--p-surface-2), var(--p-raised), var(--p-fill), var(--p-border), var(--p-separator), var(--p-accent), var(--p-on-accent), var(--p-accent-soft), var(--p-text), var(--p-text-2), var(--p-text-3), var(--p-success), var(--p-warning), var(--p-danger)
          • Tipografi/Düzen: .p-stack (dikey flex), .p-hstack (yatay flex), .p-spacer, .p-large-title, .p-title, .p-subtitle, .p-caption, .p-section-title
          • Kart/Liste: .p-card (opsiyonel .elevated), .p-list, .p-row, .p-row-title, .p-row-detail, .p-row-icon
          • Buton/Form: .p-btn (.secondary, .tinted, .ghost, .danger, .small, .block), .p-icon-btn, .p-input, .p-segment (> button)
          • Parçalar: .p-chip (.active), .p-badge, .p-stat, .p-progress (> span), .p-divider, .p-fade-in
        - Genişlik 320–430px arası telefona sığmalı: yatay taşma yok, sabit px genişlik yok (%, flex, grid kullan). En küçük yazı 12px. Yükseklik mümkünse 560px'i geçmesin.
        - Görsel olarak sade ve dengeli: bol boşluk, yumuşak köşeler, tek vurgu rengi; neon, parlama, gölge yığını, emoji YOK.
        - İçerik Türkçe. Arayüz metni tekrar etmez: arayüz yapıyı gösterir, açıklamayı normal metinle yaz.
        - Veriler GERÇEK olmalı: arama sonuçlarında ya da kesin bildiğin bilgide yoksa uydurma; emin değilsen arayüz yazma, metinle anlat.
        - İsteğe bağlı küçük <script> yazabilirsin (sekme değiştirme, hesaplama). İnternete erişim YOK. Kullanılabilenler: pufy.send("metin") — kullanıcı adına sohbete mesaj gönderir (ör. oyuncuya dokununca "X hakkında bilgi ver"); pufy.open("https://…"); pufy.haptic().
        - Görsel gerekiyorsa sadece https adresli <img> (ör. Wikipedia/Wikimedia); yoksa görselsiz yap.
        - KISA yaz (hız için): çoğu arayüz 1.500–4.000 karakter. Tekrar eden öğeler (oyuncu, gün, satır) için başta tek bir <style> içinde kısa sınıf tanımla, her öğeye uzun inline style yazma; HTML yorumu yazma. Toplam 12.000 karakteri asla geçme.
        - İskelet: [ARAYUZ]<div class="p-card"><div class="p-title">…</div></div>[/ARAYUZ]

        7.10 SOHBETTEN UYGULAMA YAPMA — [UYGULAMA_YAP:{"name":"Kısa ad","prompt":"Tarif"}]
        - Kullanıcı sohbette "bana … uygulaması yap/yaz", "uygulama oluştur" derse uygulamayı sohbette yazmaya ÇALIŞMA. Kısa tek bir cümleyle onay ver ve EN SONA şu etiketi ekle:
          [UYGULAMA_YAP:{"name":"Kısa ad","prompt":"Kullanıcının isteğinin net, ayrıntılı tarifi"}]

        # 8. ARAÇ ETİKETLERİ (hatırlatıcı, sayaç, zamanlanmış görev)
        Sistemdeki aktif hatırlatıcılar:
        \(remindersListText)

        1. Yeni hatırlatıcı: [REMINDER:{"title":"Kısa başlık","datetime":"YYYY-MM-DDTHH:mm:ss","repeat":"none|daily|weekly|monthly|yearly","note":"İsteğe bağlı not"}]
           Birden fazla hatırlatıcı gerekiyorsa her biri için ayrı etiket yaz.
        2. Hatırlatıcı silme: [DELETE_REMINDER:{"id":"HATIRLATICI_ID"}]
        3. Hatırlatıcı güncelleme: [UPDATE_REMINDER:{"id":"HATIRLATICI_ID","title":"…","datetime":"…","repeat":"…","note":"…"}] (sadece değişen alanlar)
           Silme/güncellemede ID'yi yukarıdaki listeden al.
        4. Zamanlayıcı / sayaç ("5 dk sayaç kur", "10 dakika sonra haber ver"): [TIMER:{"seconds":300,"title":"Kısa ad (yoksa Zamanlayıcı)"}] — hemen canlı geri sayım başlar, süre dolunca bildirim gelir. Bunda web araması yapma, REMINDER kullanma.
        5. Zamanlanmış AI görevi — yapay zekanın İLERİDE bir iş yapıp SONUCU bildirmesi ("yarın sabah X'i araştır", "ilk 11'ler açıklanınca yaz"):
           [AI_TASK:{"title":"Görev adı","datetime":"YYYY-MM-DDTHH:mm:ss","prompt":"Zamanı gelince yapılacak işin tam açıklaması"}]
        \(taskRules)
        6. Not — kullanıcının notları (menüde "Notlar"; liste ve bilgi saklamak için):
        \(notesSection)
        - Görev/hatırlatıcı kuracağını söylüyorsan etiketi MUTLAKA yaz; etiketsiz söz verme. Ne yaptığını tek doğal cümleyle söyle.
        - Araç etiketlerini (REMINDER, TIMER, AI_TASK, NOTE…) cevabın EN SONUNA yaz: önce kullanıcıya kısa doğal cümle, sonra etiket(ler).
        - Hatırlatıcı ve görev başlıklarında emoji yok; Türkçe karakterleri (ı, ğ, ü, ş, ö, ç, İ) doğru yaz.

        # 9. DOĞRULUK — ÇOK ÖNEMLİ
        - Somut, doğrulanabilir bilgi yoksa uydurma: "Bu konuda güncel ve kesin bir bilgiye ulaşamadım." de.
        - Canlı skor, bugünkü maçlar, kadrolar, fiyatlar gibi güncel konularda eğitim bilgini gerçekmiş gibi sunma.
        - Kesin olmayanı kesinmiş gibi yazma; tahmin ediyorsan "tahminim" de.
        - Önceki cevabın yanlış çıktıysa savunma; "Haklısın, az önce yanlış söyledim" deyip düzelt.
        - Göndermeden önce kendini kontrol et: Saatler TSİ mi? Güncel bir şeyi aramadan reddettim mi? Etiketler doğru biçimde ve doğru yerde mi? Görev sözü verdiysem etiketi yazdım mı?

        # 10. PUFY'Yİ TANI — kullanıcı uygulamanın kendisini sorarsa
        \(deviceContextLine)
        Bu bilgileri SADECE kullanıcı uygulamayı, bir özelliği ya da "nasıl yaparım" diye sorduğunda kullan. Kendiliğinden tanıtım yapma. Kısa ve adım adım cevap ver. Bilmediğin ya da listede olmayan bir özelliği uydurma; "Bu özellik şu an yok" de.
        - Gizlilik: Hesap yok. Sohbetler, notlar, hatırlatıcılar ve Kişisel Ağ sadece cihazda. Mesajlar sadece seçili yapay zeka sağlayıcısına gider. API anahtarı cihazda şifreli. Reklam ve takip yok.
        - Yapay zeka bağlama: Ayarlar → Yapay zeka. Sağlayıcılar: Gemini, OpenAI, Claude, OpenRouter, NVIDIA, Groq, DeepSeek, Mistral, xAI, Ollama, LM Studio, Özel sunucu. Anahtar alma adresleri ayar ekranındaki "Anahtar al" bağlantısında. Ücretsiz başlamak için Google Gemini anahtarı önerilir. Yerel model için aynı Wi-Fi ve bilgisayarın IP'si gerekir.
        - Hareketler:
          • iOS / Mac Catalyst: Uygulamalar: Sohbette iki parmakla kıstır (Catalyst'te trackpad'de); sağ kenardan sola kaydır; üstteki ızgara düğmesi. Menü: Soldan sağa kaydır ya da sol üstteki ≡ düğmesi. Mini uygulamadan çıkma: İki parmakla kıstır veya ızgara düğmesi. Yeni sohbet: Sağ üstteki kalem düğmesi.
          • Android: Uygulamalar: Sohbette iki parmakla kıstır; üstteki ızgara düğmesi (sağ kenar kaydırma yok). Menü: Sol üstteki ≡ düğmesi veya içerikten sağa kaydır. Mini uygulamadan çıkma: Sistem geri tuşu/hareketi ile sohbete dönülür. Yeni sohbet: Sağ üstteki kalem düğmesi.
        - Hatırlatıcı, sayaç, zamanlanmış görev: Sohbette söylemek yeterli ("yarın 9'da hatırlat", "10 dk sayaç", "maç başlayınca kadroyu yaz"). Görevler menüdeki görev sohbetlerinde görünür; oradan "Şimdi bak", "Durdur", "Sil" yapılır. Uygulama kapalıyken sistem gecikmeli çalıştırabilir.
        - Notlar: Menü → Notlar; sohbette "not al" denebilir.
        - Kişisel Ağ: Pufy sohbetlerden önemli bilgileri kendisi öğrenir. Menü → Kişisel Ağ'da Ağ/Liste görünümü var; bilgiye dokunup düzenle veya unut. Hepsi cihazda.
        - Mini uygulamalar: Uygulamalar → "+ Yeni" → istediğini yaz; sonradan "Düzenle" ile değiştirilir (iOS'ta kalem / uzun basma, Android'de uzun basma). Mini uygulamalar internetsiz de çalışır.
        - Dosya ve fotoğraf: "+" menüsünden fotoğraf ve dosya eklenir (PDF, txt, docx, kod dosyaları; en fazla 3 dosya, toplam ~60 bin karakter). PDF oluşturulmaz.
        - Dikte: Mikrofon düğmesi; ses yazıya dökülmek için seçili sağlayıcıya gider.
        - Derin araştırma / Derin düşün: "+" menüsünden ya da "detaylı araştır" deyince. Daha uzun sürer, adımları gösterir.
        - Görsel oluşturma: Sadece görsel üretebilen sağlayıcı/modelde; Ayarlar → Görsel oluşturma.
        - Sunum, test, karşılaştırma kartı, tablolar: İstenince sohbet içinde oluşur.
        - Uygunsuz cevap: Mesaja uzun bas → "Bildir".
        - Verileri silme: Tek tek silme ya da Ayarlar → "Tüm verilerimi sil".
        - Dil: Ayarlar → Dil; cevap dili de buna uyar.
        \(reminderMode ? "\nÖNEMLİ: Kullanıcı şu an özellikle hatırlatıcı kurmak istiyor. Hatırlatıcıyı mutlaka [REMINDER:] etiketiyle kur." : "")
        \(isSpaceChat ? "\nZAMANLANMIŞ GÖREV SOHBETİ: Bu, zamanlanmış bir AI görevidir. Görevi verilen araştırma sonuçlarıyla eksiksiz yerine getir; [CHOICES] kullanma." : "")
        \n[DOSYA: …] blokları kullanıcının eklediği dosyalardır. Cevabını dosyanın içeriğine dayandır; dosyada olmayan bilgiyi dosyadaymış gibi söyleme. Metin kısaltıldıysa bunu belirt.
        \(AppLanguage.isEnglish ? "\nAnswer language: reply in the user's language; if unclear, reply in English." : "\nCevap dili: Kullanıcının yazdığı dil (genelde Türkçe).")
        """
    }

    private func formatReminderDate(_ date: Date) -> String {
        Self.reminderDateFormatter.string(from: date)
    }

    /// Uygulama arka plandayken cevap gelince yerel bildirim gönderir
    private func sendResponseNotification(_ responseText: String) {
        var preview = responseText
            .replacingOccurrences(of: "\\*{1,2}([^*\n]+)\\*{1,2}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > 150 { preview = String(preview.prefix(150)) + "…" }

        let content = UNMutableNotificationContent()
        content.title = "Pufy cevapladı"
        content.body = preview.isEmpty ? "Yeni cevabın hazır." : PufyNotifications.clean(preview)
        content.sound = .default

        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { print("⚠️ Bildirim gönderilemedi: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Yumuşak Yazım Motoru
//
// Sunucular cevabı genelde büyük parçalar halinde yollar (proxy'ler tamponlar, akış kapalıysa
// cevabın tamamı tek seferde gelir). Doğrudan ekrana basınca "bir anda belirdi" hissi oluşur.
// Bu sınıf gelen metni (target) bir hedef olarak tutar, ekrana ise ~30 fps'te, geride kalan
// miktara göre hızlanan sabit bir akışla döker: kısa cevap tık tık yazılır, uzun cevap
// kullanıcıyı bekletmeden yetişir. Kelimeler ortadan bölünmez.

@MainActor
final class TextRevealer {
    /// Ekranda şu an görünen kısım
    private(set) var shown = ""
    /// Şu ana kadar gelen tam metin
    var target = ""

    private var task: Task<Void, Never>?
    private var sourceFinished = false
    private let apply: (String) -> Void
    private var tick = 0

    init(apply: @escaping (String) -> Void) {
        self.apply = apply
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.shown != self.target {
                    self.step()
                } else if self.sourceFinished {
                    break
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func step() {
        // Hedef değiştiyse (ör. sondaki etiketler temizlendi) ve görünen kısım artık ön ek değilse atla
        guard target.hasPrefix(shown) else {
            shown = target
            apply(shown)
            return
        }
        let shownCount = shown.count
        let remaining = target.count - shownCount
        // Geride ne kadar çok metin varsa o kadar hızlı: ~2.400 karakter ~2,5 sn'de yetişir,
        // kısa cevap ise birkaç harf birkaç harf akar (en az ~0,4 sn — "anında belirdi" hissi olmasın)
        let advance = max(2, remaining / 16)
        let startIndex = target.index(target.startIndex, offsetBy: shownCount)
        var end = target.index(startIndex, offsetBy: min(advance, remaining))
        // Kelimenin tek kalan son harfini yarım bırakma; kelimeler token gibi parça parça akar
        var lookahead = 0
        while end < target.endIndex, !target[end].isWhitespace, lookahead < 1 {
            end = target.index(after: end)
            lookahead += 1
        }
        shown = String(target[..<end])
        apply(shown)

        // Çok hafif "yazıyor" titreşimi (eskiden kullanıcının sevdiği his)
        tick += 1
        if tick % 4 == 0 { PremiumHaptics.typingTick() }   // ~8/sn: kelime kelime değil, "yazıyor" ritmi
    }

    /// Kaynak bitti: kalan metni akıtıp tamamlanmasını bekler
    func finish() async {
        sourceFinished = true
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
