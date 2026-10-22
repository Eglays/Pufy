import Foundation
import UIKit
import SwiftUI

// MARK: - Uygulama Oluşturma Motoru
//
// ESKİSİ: Uygulamanın tamamı tek dev JSON cevabında gelirdi (kod JSON içinde kaçış karakterli →
// bozulmaya açık), akış yoktu, dakikalarca üç nokta. Her düzenlemede tüm dosyalar baştan yazılırdı.
//
// YENİSİ: Akışa uygun düz metin protokolü:
//   <<<META {"name":"Tetris","icon":"square.grid.3x3.fill","color":"#111111"}>>>
//   <<<FILE js/app.js>>> …tam içerik… <<<END>>>
//   <<<PATCH js/app.js>>> <<<<<<< SEARCH …eski… ======= …yeni… >>>>>>> REPLACE <<<END>>>
//   <<<DELETE eski.js>>>
// Bloklar geldikçe ekranda dosya dosya ilerleme görünür. Düzenlemeler sadece değişen kısmı yamar;
// yama tutmazsa motor o dosyanın tam halini otomatik ister. Her değişiklikten önce sürüm alınır.

struct BuildMeta {
    var name: String?
    var icon: String?
    var color: String?
    /// Kapak kartındaki kısa slogan
    var tagline: String? = nil
}

struct BuildResult {
    var reply: String
    var meta: BuildMeta?
    var changedFiles: [String]
    var failedPatches: [String]
    /// Ajanın kalite kontrolü özeti ("Kalite kontrolü: 9/10 · 1 tur düzeltildi")
    var qualityNote: String? = nil
    var didChangeFiles: Bool { !changedFiles.isEmpty }
}

@MainActor
final class AppBuilder: ObservableObject {
    enum FileState: Equatable { case writing, written, patched, deleted, failed }

    struct FileProgress: Identifiable, Equatable {
        var id: String { path }
        let path: String
        var state: FileState
        /// Eklenen / silinen satır sayısı (GitHub tarzı +12 −3)
        var added: Int
        var removed: Int
    }

    /// Oluşturma başlamadan önceki dosya içerikleri (satır farkı hesaplamak için)
    private var originals: [String: [String]] = [:]
    /// Kapanmış blokların fark sonucu — her ekran güncellemesinde yeniden hesaplanmasın
    private var diffCache: [String: (Int, Int)] = [:]

    @Published private(set) var isBuilding = false
    @Published private(set) var files: [FileProgress] = []
    @Published private(set) var status = "" {
        didSet { reportBackground() }
    }
    @Published private(set) var reasoning = ""
    @Published private(set) var liveReply = ""
    /// Tahmini ilerleme 0…1 (arka plan ilerleme arayüzü için): gelen kod miktarına göre yavaşça dolar
    @Published private(set) var progressEstimate: Double = 0 {
        didSet { reportBackground() }
    }
    /// Arka planda sürerken sistemin ilerleme arayüzü (bkz. BackgroundWork). İlerlemeyi EKRAN değil iş kendisi bildirir:
    /// arka planda ekran güncellenmediği için eskiden iOS işi "durmuş" sayıp kesiyordu.
    var backgroundWork: (id: String, title: String)?
    private var lastBackgroundReport = Date.distantPast
    /// Akış sırasında gelen metin (bağlantı koparsa kaldığı yerden devam etmek için)
    private var partialOutput = ""
    /// Uygulama askıya alınıp döndü: ölü bağlantıyı beklemeden (150 sn) isteği yenile
    private var suspendedRestart = false

    private func reportBackground() {
        guard let work = backgroundWork else { return }
        // Akışta saniyede onlarca güncelleme gelir; sisteme en fazla saniyede iki kez
        guard Date().timeIntervalSince(lastBackgroundReport) > 0.5 else { return }
        lastBackgroundReport = Date()
        BackgroundWork.update(id: work.id, progress: progressEstimate, title: work.title,
                              subtitle: status.isEmpty ? "Pufy kodu yazıyor…" : status)
    }
    /// Ajanın adımları (plan, görseller, kod, deneme, düzeltme) — ekranda yapılacaklar listesi gibi görünür
    @Published private(set) var steps: [AgentStep] = []
    /// Kod yazımının ilerleme çubuğunda kapladığı aralık
    private var phase: (lo: Double, hi: Double) = (0.05, 0.95)

    private func setStep(_ id: String, _ title: String, _ state: AgentStep.State, detail: String? = nil) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            steps[index].title = title
            steps[index].state = state
            if let detail { steps[index].detail = detail }
        } else {
            steps.append(AgentStep(id: id, title: title, state: state, detail: detail))
        }
    }

    private var task: Task<BuildResult, Error>?

    func cancel() {
        task?.cancel()
    }

    /// - Parameters:
    ///   - request: Kullanıcının isteği
    ///   - history: Önceki sohbet (sadece metin)
    ///   - folder: Uygulama klasörü
    func build(request: String, history: [Message], folder: String) async throws -> BuildResult {
        let job = Task { () throws -> BuildResult in
            isBuilding = true
            progressEstimate = 0.02
            files = []
            steps = []
            diffCache = [:]
            originals = Dictionary(MiniAppFiles.textFiles(folder).map { ($0.path, $0.content.components(separatedBy: "\n")) },
                                   uniquingKeysWith: { a, _ in a })
            reasoning = ""
            liveReply = ""
            status = "Plan çıkarılıyor…"
            defer { isBuilding = false }

            let hasApp = MiniAppFiles.hasFiles(folder)

            // 1) PLAN (zor işler modeli)
            setStep("plan", "Plan çıkarılıyor", .running)
            let plan = await AppAgent.plan(request: request, history: history, folder: folder, hasApp: hasApp)
            try Task.checkCancellation()
            if plan?.chat == true {
                // Sadece sohbet: kod yazılmaz, tek adımda cevap
                steps = []
                status = "Düşünüyor…"
                phase = (0.05, 0.95)
                let raw = try await stream(prompt: baseMessage(request: request, folder: folder, hasApp: hasApp), history: history)
                status = ""
                return try apply(raw, folder: folder, snapshotLabel: nil)
            }
            setStep("plan", plan?.summary.map { "Plan: \($0)" } ?? "Plan hazır", .done)
            for (index, item) in (plan?.todo ?? []).prefix(7).enumerated() {
                steps.append(AgentStep(id: "todo\(index)", title: item))
            }
            progressEstimate = 0.08

            // 2) GÖRSELLER (görsel modeli + arka plan temizleme), üçer üçer aynı anda
            var made: [(path: String, size: CGSize, note: String)] = []
            let wanted = Array((plan?.assets ?? []).prefix(8))
            if !wanted.isEmpty, GeminiService.shared.canGenerateImages {
                status = "Görseller çiziliyor…"
                setStep("assets", "Görseller çiziliyor (0/\(wanted.count))", .running)
                let style = plan?.style
                var done = 0
                for batch in stride(from: 0, to: wanted.count, by: 3).map({ Array(wanted[$0..<min($0 + 3, wanted.count)]) }) {
                    try Task.checkCancellation()
                    let results = await withTaskGroup(of: (path: String, size: CGSize, note: String)?.self) { group in
                        for asset in batch {
                            group.addTask {
                                guard let made = await AppAgent.makeAsset(asset, style: style, folder: folder) else { return nil }
                                return (made.path, made.size, asset.note ?? asset.prompt)
                            }
                        }
                        var out: [(path: String, size: CGSize, note: String)] = []
                        for await item in group { if let item { out.append(item) } }
                        return out
                    }
                    made += results
                    done += batch.count
                    setStep("assets", "Görseller çiziliyor (\(done)/\(wanted.count))", .running)
                    progressEstimate = 0.08 + 0.22 * Double(done) / Double(wanted.count)
                }
                setStep("assets", made.isEmpty ? "Görseller çizilemedi" : "\(made.count) görsel hazır", made.isEmpty ? .failed : .done)
            }
            let assetsText = Self.assetsText(folder: folder, fresh: made)

            // 3) KOD (zor işler modeli) — tasarım kiti klasörde hazır olsun (bkz. PufyUIKit)
            PufyUIKit.ensure(folder)
            setStep("code", "Kod yazılıyor", .running)
            phase = (max(progressEstimate, 0.1), 0.7)
            var userMessage = baseMessage(request: request, folder: folder, hasApp: hasApp)
            if let plan {
                userMessage += "\n\n[PLAN]\nÖzet: \(plan.summary ?? "")\nStil: \(plan.style ?? "-")\nYapılacaklar:\n"
                    + (plan.todo ?? []).map { "- \($0)" }.joined(separator: "\n")
            }
            if !assetsText.isEmpty { userMessage += "\n\n" + assetsText }
            let raw = try await stream(prompt: userMessage, history: history)
            try Task.checkCancellation()
            var result = try apply(raw, folder: folder, snapshotLabel: request)
            PufyUIKit.ensure(folder)     // model kiti değiştirdiyse geri al
            if !result.failedPatches.isEmpty {
                let retry = try await retryFailedPatches(result.failedPatches, request: request, folder: folder)
                result.changedFiles += retry.changedFiles
                result.failedPatches = retry.failedPatches
            }
            setStep("code", result.didChangeFiles ? "Kod yazıldı · \(Set(result.changedFiles).count) dosya" : "Kod değişmedi",
                    result.didChangeFiles ? .done : .failed)
            for index in steps.indices where steps[index].id.hasPrefix("todo") { steps[index].state = .done }

            // 4-6) DENE → BAK → DÜZELT (en fazla 3 deneme, 2 düzeltme)
            if result.didChangeFiles, MiniAppFiles.hasFiles(folder) {
                var lastScore: Double?
                var fixes = 0
                for round in 1...3 {
                    try Task.checkCancellation()
                    let testID = "test\(round)"
                    // Pufy arka plandayken WebKit ekran çizmez; ekran görüntüsü beklenirse iş takılıyordu
                    guard UIApplication.shared.applicationState == .active else {
                        setStep(testID, "Görsel deneme atlandı (Pufy arka plandaydı)", .done)
                        break
                    }
                    setStep(testID, round == 1 ? "Deneniyor" : "Yeniden deneniyor", .running)
                    status = "Uygulama deneniyor…"
                    progressEstimate = 0.72 + 0.09 * Double(round - 1)
                    let run = await AppAgent.test(folder: folder)
                    status = "Ekran görüntüsüne bakılıyor…"
                    guard let review = await AppAgent.review(request: request, plan: plan, run: run, round: round) else {
                        setStep(testID, run.errors.isEmpty ? "Denendi" : "Denendi · \(run.errors.count) hata", .done)
                        break
                    }
                    let score = review.score ?? 0
                    lastScore = score
                    let issues = review.issues ?? []
                    setStep(testID, "Deneme \(round): \(Self.format(score))/10" + (issues.isEmpty && run.errors.isEmpty ? "" : " · \(issues.count + run.errors.count) sorun"),
                            .done, detail: (run.errors.prefix(2) + issues.prefix(3)).joined(separator: "\n"))
                    let needsFix = (score < 8.5 || !run.errors.isEmpty) && (!issues.isEmpty || !run.errors.isEmpty)
                    guard needsFix, round < 3 else { break }

                    let fixID = "fix\(round)"
                    setStep(fixID, "Düzeltiliyor", .running)
                    status = "Sorunlar düzeltiliyor…"
                    phase = (progressEstimate, progressEstimate + 0.08)
                    files = []
                    let fixPrompt = """
                    [MEVCUT DOSYALAR]
                    \(MiniAppFiles.promptText(folder))

                    \(Self.assetsText(folder: folder, fresh: []))

                    [DENEME SONUCU — tur \(round)] Puan: \(Self.format(score))/10
                    Konsol hataları:
                    \(run.errors.isEmpty ? "yok" : run.errors.map { "- \($0)" }.joined(separator: "\n"))
                    Sorunlar:
                    \(issues.map { "- \($0)" }.joined(separator: "\n"))
                    Talimat: \(review.fix ?? "Sorunları gider.")

                    Bu sorunları KÖKÜNDEN düzelt (asıl istek: \(request)). Sadece gerekeni PATCH ile değiştir; dosyanın yarısından
                    fazlası değişecekse FILE ile tamamını yaz. Hazır görselleri kullanmaya devam et. En sonda tek cümleyle ne düzelttiğini yaz.
                    """
                    let fixRaw = try await stream(prompt: fixPrompt, history: [])
                    var fixed = try apply(fixRaw, folder: folder, snapshotLabel: nil)
                    PufyUIKit.ensure(folder)
                    if !fixed.failedPatches.isEmpty {
                        let retry = try await retryFailedPatches(fixed.failedPatches, request: review.fix ?? request, folder: folder)
                        fixed.changedFiles += retry.changedFiles
                    }
                    setStep(fixID, fixed.didChangeFiles ? "Düzeltildi" : "Düzeltilemedi", fixed.didChangeFiles ? .done : .failed)
                    guard fixed.didChangeFiles else { break }
                    fixes += 1
                    result.changedFiles += fixed.changedFiles.filter { !result.changedFiles.contains($0) }
                }
                if let lastScore {
                    result.qualityNote = "Kalite kontrolü: \(Self.format(lastScore))/10" + (fixes > 0 ? " · \(fixes) tur düzeltildi" : "")
                        + (made.isEmpty ? "" : " · \(made.count) görsel çizildi")
                }
            }
            progressEstimate = 0.98
            status = ""
            return result
        }
        task = job
        return try await job.value
    }

    private func baseMessage(request: String, folder: String, hasApp: Bool) -> String {
        guard hasApp else { return "[CİHAZ] \(Self.deviceDescription())\n\n" + request }
        return """
        [MEVCUT DOSYALAR]
        \(MiniAppFiles.promptText(folder))

        [CİHAZ]
        \(Self.deviceDescription())

        [İSTEK]
        \(request)
        """
    }

    /// Yama tutmadıysa: o dosyaların tam halini iste (tek sefer)
    private func retryFailedPatches(_ failed: [String], request: String, folder: String) async throws -> BuildResult {
        status = "Bazı değişiklikler eşleşmedi, dosyalar yeniden yazılıyor…"
        let retryPrompt = """
        [MEVCUT DOSYALAR]
        \(MiniAppFiles.promptText(folder))

        Önceki yamaların şu dosyalarda SEARCH kısmı eşleşmedi: \(failed.joined(separator: ", ")).
        Bu dosyaların istenen değişikliği içeren TAM halini <<<FILE>>> bloğuyla ver. Açıklama yazma.
        İstenen değişiklik: \(request)
        """
        let retryRaw = try await stream(prompt: retryPrompt, history: [])
        return try apply(retryRaw, folder: folder, snapshotLabel: nil)
    }

    /// Yazara verilen hazır görsel listesi
    static func assetsText(folder: String, fresh: [(path: String, size: CGSize, note: String)]) -> String {
        let all = AppAgent.existingAssets(folder)
        guard !all.isEmpty else { return "" }
        let notes = Dictionary(fresh.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let lines = all.map { path -> String in
            if let f = notes[path] {
                return "- \(path) (\(Int(f.size.width))×\(Int(f.size.height)), \(path.hasSuffix(".png") ? "şeffaf PNG" : "JPEG")): \(f.note)"
            }
            return "- \(path)"
        }
        return """
        [HAZIR GÖRSELLER — MUTLAKA KULLAN]
        \(lines.joined(separator: "\n"))
        Bu dosyalar uygulama klasöründe. <img src="assets/…"> ya da canvas'ta new Image() + drawImage ile kullan (yüklenmesini bekle,
        oranını koru). Bu nesneleri CSS daireleri, emoji ya da düz şekillerle ÇİZME; görselin yerine geçecek kod yazma.
        """
    }

    private static func format(_ score: Double) -> String {
        score.rounded() == score ? String(Int(score)) : String(format: "%.1f", score)
    }

    // MARK: Akış

    /// Geçici ağ sorunları (zaman aşımı, kopma, sunucu yoğun, uygulamanın askıya alınması) kullanıcıya hata göstermeden
    /// tekrar denenir. Kullanıcı (15 Ekim 2026): "Arka plana alınca 'yeniden deneniyor' diyor, yarım saat beklesen de
    /// bitmiyor, kapatıp baştan yazdırmam gerekiyor." Artık:
    ///  • Pufy askıya alındıysa (iOS arka plan iznini bitirdi) deneme hakkı harcanmaz; Pufy tekrar açılınca sürer.
    ///  • Kod yazımı yarıda koptuysa baştan yazılmaz: tamamlanan dosyalar saklanır, model kaldığı yerden devam eder.
    private func stream(prompt: String, history: [Message]) async throws -> String {
        var attempt = 0
        var done = ""            // önceki denemelerden kalan, kapanmış bloklar
        while true {
            partialOutput = ""
            suspendedRestart = false
            let currentPrompt = done.isEmpty ? prompt : Self.continuationPrompt(prompt, written: done)
            let prefix = done
            let attemptTask = Task { try await self.streamOnce(prompt: currentPrompt, history: history, prefix: prefix) }
            // Askıya alma dedektörü: saniyelik saat birden 8+ sn atladıysa iOS uygulamayı dondurmuştu → bağlantı ölü
            let watcher = Task { [weak self] in
                var last = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let now = Date()
                    if now.timeIntervalSince(last) > 8 {
                        self?.suspendedRestart = true
                        attemptTask.cancel()
                        return
                    }
                    last = now
                }
            }
            do {
                let text = try await withTaskCancellationHandler {
                    try await attemptTask.value
                } onCancel: {
                    attemptTask.cancel()
                }
                watcher.cancel()
                return done.isEmpty ? text : done + "\n" + text
            } catch {
                watcher.cancel()
                if Task.isCancelled { throw CancellationError() }
                let restart = suspendedRestart
                guard restart || (!(error is CancellationError) && Self.isTransient(error)) else {
                    if error is CancellationError { throw CancellationError() }
                    throw error
                }
                // Yarım kalan cevabın tamamlanmış kısmını sakla
                let kept = Self.closedPrefix(partialOutput)
                if !kept.isEmpty { done = done.isEmpty ? kept : done + "\n" + kept }

                // Uygulama askıda/arka plan izni yok: Pufy açılınca devam (hak harcanmaz)
                if UIApplication.shared.applicationState != .active,
                   backgroundWork.map({ !BackgroundWork.isAlive($0.id) }) ?? true {
                    status = "Bağlantı koptu · Pufy'yi açınca kaldığı yerden sürecek"
                    await Self.waitUntilActive()
                    try Task.checkCancellation()
                    status = "Kaldığı yerden devam ediliyor…"
                    continue
                }
                if restart {
                    status = "Kaldığı yerden devam ediliyor…"
                    continue
                }
                attempt += 1
                guard attempt <= 5 else { throw error }
                status = done.isEmpty ? "Bağlantı koptu, yeniden deneniyor…" : "Bağlantı koptu, kaldığı yerden devam ediliyor…"
                try await Task.sleep(nanoseconds: UInt64([2, 4, 8, 15, 30][attempt - 1]) * 1_000_000_000)
            }
        }
    }

    /// Kopma, zaman aşımı, sunucu yoğunluğu gibi geçici hatalar
    static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                    NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
                    NSURLErrorSecureConnectionFailed, NSURLErrorBadServerResponse, NSURLErrorCannotParseResponse,
                    NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive, NSURLErrorDataNotAllowed,
                    NSURLErrorBackgroundSessionWasDisconnected, NSURLErrorZeroByteResource].contains(ns.code)
        }
        if ns.domain == NSPOSIXErrorDomain { return [50, 51, 53, 54, 57, 60, 61, 64, 65].contains(ns.code) }
        if [429, 500, 502, 503, 504, 529].contains(ns.code) { return true }
        let text = ns.localizedDescription.lowercased()
        return ["connection", "bağlantı", "timed out", "zaman aşımı", "network", "socket", "overloaded", "quota",
                "unavailable", "yoğun", "abort"].contains { text.contains($0) }
    }

    /// Yarım cevabın son KAPANMIŞ bloğa kadar olan kısmı (META ve tamamlanan FILE/PATCH/DELETE blokları)
    static func closedPrefix(_ text: String) -> String {
        let ns = text as NSString
        guard let last = endRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return "" }
        return ns.substring(to: last.range.location + last.range.length)
    }

    static func continuationPrompt(_ prompt: String, written: String) -> String {
        """
        \(prompt)

        [YARIM KALAN CEVABIN — bağlantı koptu]
        Bu isteğe verdiğin cevabın aşağıdaki kısmı yazıldı ve UYGULANDI:
        \(written)

        Şimdi KALDIĞIN YERDEN DEVAM ET: yukarıdaki dosya ve yamaları TEKRAR YAZMA; kalan dosyaları/yamaları aynı biçimde \
        (<<<FILE …>>> / <<<PATCH …>>> … <<<END>>>) yaz, en sonda tek cümlelik özetini ekle. META'yı tekrar yazma.
        """
    }

    static func waitUntilActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) { break }
    }

    /// - prefix: önceki denemede yazılmış kısım (ekrandaki dosya ilerlemesi kaybolmasın)
    private func streamOnce(prompt: String, history: [Message], prefix: String = "") async throws -> String {
        let ai = GeminiService.shared
        var full = ""
        var thought = ""
        var lastUpdate = Date.distantPast

        if ai.streamingEnabled {
            do {
                for try await chunk in ai.streamContent(prompt: prompt, history: history,
                                                        systemPrompt: Self.systemPrompt, maxOutputTokens: 32000,
                                                        modelOverride: ai.deepModel, thinking: "high") {
                    switch chunk {
                    case .text(let t): full += t; partialOutput = full
                    case .thought(let t): thought += t
                    case .sources: break
                    }
                    if Date().timeIntervalSince(lastUpdate) > 0.08 {
                        lastUpdate = Date()
                        reasoning = thought
                        updateProgress(from: prefix.isEmpty ? full : prefix + "\n" + full)
                    }
                }
                reasoning = thought
                updateProgress(from: prefix.isEmpty ? full : prefix + "\n" + full)
                if !full.isEmpty { return full }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                guard full.isEmpty else { throw error }
                // akış desteklenmiyorsa normal isteğe düş
            }
        }
        status = "Kod yazılıyor…"
        full = try await ai.generateContent(prompt: prompt, history: history,
                                            systemPrompt: Self.systemPrompt, maxOutputTokens: 32000,
                                            modelOverride: ai.deepModel, thinking: "high")
        updateProgress(from: full)
        return full
    }

    /// Gelen metne bakıp hangi dosyanın yazıldığını ve kaç satır değiştiğini ekrana yansıtır
    private func updateProgress(from text: String) {
        var progress: [FileProgress] = []
        var openPath: String?
        for block in Self.scanBlocks(text) {
            let state: FileState = block.closed ? (block.kind == .patch ? .patched : .written) : .writing
            var (added, removed) = (0, 0)
            switch block.kind {
            case .delete:
                removed = originals[block.path]?.count ?? 0
                progress.removeAll { $0.path == block.path }
                progress.append(FileProgress(path: block.path, state: .deleted, added: 0, removed: removed))
                continue
            case .file:
                if block.closed {
                    (added, removed) = cachedDiff(key: "F|\(block.path)|\(block.body.count)") {
                        Self.lineDiff(old: self.originals[block.path] ?? [],
                                      new: Self.trimBlockBody(block.body).components(separatedBy: "\n"))
                    }
                } else {
                    // Yazılırken: şimdiye kadar gelen satır sayısı
                    added = block.body.components(separatedBy: "\n").count - 1
                }
            case .patch:
                (added, removed) = cachedDiff(key: "P|\(block.path)|\(block.body.count)") {
                    Self.parsePatch(block.body).reduce((0, 0)) { total, pair in
                        let d = Self.lineDiff(old: pair.0.components(separatedBy: "\n"),
                                              new: pair.1.components(separatedBy: "\n"))
                        return (total.0 + d.0, total.1 + d.1)
                    }
                }
            }
            if let index = progress.firstIndex(where: { $0.path == block.path }) {
                // Aynı dosyaya birden fazla blok: farkları topla
                progress[index].state = state
                progress[index].added += added
                progress[index].removed += removed
            } else {
                progress.append(FileProgress(path: block.path, state: state, added: added, removed: removed))
            }
            if !block.closed { openPath = block.path }
        }
        files = progress
        liveReply = Self.stripBlocks(text)
        // Büyüklüğü bilinmeyen iş: ~15 KB'da %63, asla %95'i geçmez
        let fraction = 1 - exp(-Double(text.utf8.count) / 15_000)
        progressEstimate = min(0.97, phase.lo + (phase.hi - phase.lo) * fraction)

        if let openPath {
            status = "\(openPath) yazılıyor…"
        } else if !progress.isEmpty {
            status = "Tamamlanıyor…"
        } else if !liveReply.isEmpty {
            status = "Yazıyor…"
        }
    }

    private func cachedDiff(key: String, compute: () -> (Int, Int)) -> (Int, Int) {
        if let hit = diffCache[key] { return hit }
        let value = compute()
        diffCache[key] = value
        return value
    }

    /// Satır bazında fark: (eklenen, silinen)
    static func lineDiff(old: [String], new: [String]) -> (Int, Int) {
        let diff = new.difference(from: old)
        return (diff.insertions.count, diff.removals.count)
    }

    // MARK: Uygulama

    private func apply(_ raw: String, folder: String, snapshotLabel: String?) throws -> BuildResult {
        let blocks = Self.scanBlocks(raw).filter { $0.closed || $0.kind == .delete }
        var meta = Self.parseMeta(raw)
        // Kullanıcının verdiği API anahtarları koda yazılmaz; uygulamaya özel Anahtar Zinciri'ne gider (pufy.secret)
        if let secrets = Self.parseSecrets(raw), !secrets.isEmpty {
            MiniAppSecrets.merge(secrets, folder: folder)
        }
        var changed: [String] = []
        var failed: [String] = []

        // Eski JSON formatıyla cevap veren modeller için yedek
        if blocks.isEmpty, let legacy = Self.parseLegacyJSON(raw) {
            if let label = snapshotLabel { MiniAppFiles.snapshot(folder, label: label) }
            for file in legacy.files where MiniAppFiles.write(file.path, content: file.content, folder: folder) {
                changed.append(file.path)
            }
            meta = meta ?? legacy.meta
            return BuildResult(reply: Self.cleanReply(raw), meta: meta, changedFiles: changed, failedPatches: [])
        }
        // Kod bloğu yok ama düz HTML verdiyse
        if blocks.isEmpty, let html = Self.fencedHTML(raw), !MiniAppFiles.hasFiles(folder) {
            MiniAppFiles.write("index.html", content: html, folder: folder)
            return BuildResult(reply: Self.cleanReply(raw), meta: meta, changedFiles: ["index.html"], failedPatches: [])
        }

        if !blocks.isEmpty, let label = snapshotLabel {
            MiniAppFiles.snapshot(folder, label: label)
        }

        for block in blocks {
            switch block.kind {
            case .file:
                if MiniAppFiles.write(block.path, content: Self.trimBlockBody(block.body), folder: folder) {
                    changed.append(block.path)
                }
            case .delete:
                MiniAppFiles.delete(block.path, folder: folder)
                changed.append(block.path)
            case .patch:
                guard var content = MiniAppFiles.read(block.path, folder: folder) else {
                    failed.append(block.path)
                    continue
                }
                var allApplied = true
                for (search, replace) in Self.parsePatch(block.body) {
                    if let updated = Self.replace(search, with: replace, in: content) {
                        content = updated
                    } else {
                        allApplied = false
                    }
                }
                if allApplied, MiniAppFiles.write(block.path, content: content, folder: folder) {
                    changed.append(block.path)
                } else {
                    // Kısmen uygulanmışsa bile yazmayalım: dosya tutarsız kalmasın, tam hali istenecek
                    failed.append(block.path)
                }
            }
        }
        return BuildResult(reply: Self.cleanReply(raw), meta: meta, changedFiles: changed, failedPatches: failed)
    }

    // MARK: Ayrıştırma

    enum BlockKind { case file, patch, delete }

    struct Block {
        let kind: BlockKind
        let path: String
        let body: String
        let closed: Bool
    }

    // Başlık: <<<FILE yol>>>, <<<FILE: yol>>> ya da ">>>" unutulmuş <<<FILE yol⏎ — hepsi kabul
    private static let headerRegex = try! NSRegularExpression(
        pattern: "<<<[ \\t]*(FILE|PATCH|DELETE)[ \\t:]+([^\\n>]+?)[ \\t]*(?:>>>|(?=\\n))",
        options: [.caseInsensitive])
    private static let endRegex = try! NSRegularExpression(
        pattern: "<<<[ \\t]*END[ \\t]*(?:>>>)?", options: [.caseInsensitive])

    static func scanBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let ns = text as NSString
        var location = 0
        while location < ns.length,
              let header = headerRegex.firstMatch(in: text, range: NSRange(location: location, length: ns.length - location)) {
            let keyword = ns.substring(with: header.range(at: 1)).uppercased()
            let rawPath = ns.substring(with: header.range(at: 2))
            let bodyStart = header.range.location + header.range.length
            guard let path = MiniAppFiles.sanitized(rawPath) else {
                location = bodyStart
                continue
            }
            if keyword == "DELETE" {
                blocks.append(Block(kind: .delete, path: path, body: "", closed: true))
                location = bodyStart
                continue
            }
            let kind: BlockKind = keyword == "FILE" ? .file : .patch
            if let end = endRegex.firstMatch(in: text, range: NSRange(location: bodyStart, length: ns.length - bodyStart)) {
                let body = ns.substring(with: NSRange(location: bodyStart, length: end.range.location - bodyStart))
                blocks.append(Block(kind: kind, path: path, body: body, closed: true))
                location = end.range.location + end.range.length
            } else {
                blocks.append(Block(kind: kind, path: path, body: ns.substring(from: bodyStart), closed: false))
                break
            }
        }
        return blocks
    }

    static func parseMeta(_ text: String) -> BuildMeta? {
        // "<<<META {...}>>>" — model bazen ">>>" yazmayı unutuyor: satır sonuna kadar al
        guard let open = text.range(of: "<<<META", options: .caseInsensitive) else { return nil }
        let rest = text[open.upperBound...]
        var line = String(rest.prefix { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix(":") { line.removeFirst() }
        if let close = line.range(of: ">>>") { line = String(line[..<close.lowerBound]) }
        guard let s = line.firstIndex(of: "{"), let e = line.lastIndex(of: "}"), s < e,
              let data = String(line[s...e]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return BuildMeta(name: json["name"] as? String, icon: json["icon"] as? String,
                         color: json["color"] as? String, tagline: json["tagline"] as? String)
    }

    /// Uygulamayı yaptıran cihaz (ör. "iPad, ekran 1180×820 pt, yatay") — uygulama yine her ekrana uyumlu yazılmalı
    @MainActor
    static func deviceDescription() -> String {
        let bounds = UIScreen.main.bounds
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientation = bounds.width > bounds.height ? "yatay" : "dikey"
        return "\(isPad ? "iPad" : "iPhone"), ekran \(Int(bounds.width))×\(Int(bounds.height)) pt, \(orientation). Uygulama iPhone ve iPad'in her yönünde düzgün çalışmalı."
    }

    /// META satırındaki "secrets": {"AD": "değer"} — kullanıcının verdiği API anahtarları
    static func parseSecrets(_ text: String) -> [String: String]? {
        guard let open = text.range(of: "<<<META", options: .caseInsensitive) else { return nil }
        var line = String(text[open.upperBound...].prefix { $0 != "\n" }).trimmingCharacters(in: .whitespaces)
        if let close = line.range(of: ">>>") { line = String(line[..<close.lowerBound]) }
        guard let s = line.firstIndex(of: "{"), let e = line.lastIndex(of: "}"), s < e,
              let data = String(line[s...e]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secrets = json["secrets"] as? [String: Any] else { return nil }
        return secrets.compactMapValues { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
    }

    /// <<<<<<< SEARCH … ======= … >>>>>>> REPLACE çiftleri
    static func parsePatch(_ body: String) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var cursor = body.startIndex
        while let s = body.range(of: "<<<<<<< SEARCH", range: cursor..<body.endIndex),
              let mid = body.range(of: "=======", range: s.upperBound..<body.endIndex),
              let e = body.range(of: ">>>>>>> REPLACE", range: mid.upperBound..<body.endIndex) {
            pairs.append((trimOneNewline(String(body[s.upperBound..<mid.lowerBound])),
                          trimOneNewline(String(body[mid.upperBound..<e.lowerBound]))))
            cursor = e.upperBound
        }
        return pairs
    }

    /// Önce birebir, olmazsa satır başı/sonu boşluklarını yok sayarak eşleştirir
    static func replace(_ search: String, with replacement: String, in content: String) -> String? {
        if search.isEmpty { return nil }
        if let range = content.range(of: search) {
            return content.replacingCharacters(in: range, with: replacement)
        }
        let contentLines = content.components(separatedBy: "\n")
        let searchLines = search.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !searchLines.isEmpty, searchLines.count <= contentLines.count else { return nil }
        for start in 0...(contentLines.count - searchLines.count) {
            let window = contentLines[start..<start + searchLines.count].map { $0.trimmingCharacters(in: .whitespaces) }
            if window == searchLines {
                var lines = contentLines
                lines.replaceSubrange(start..<start + searchLines.count, with: replacement.components(separatedBy: "\n"))
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    private static func trimOneNewline(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\n") { t.removeFirst() }
        if t.hasSuffix("\n") { t.removeLast() }
        return t
    }

    static func trimBlockBody(_ body: String) -> String {
        var t = body
        while t.hasPrefix("\n") { t.removeFirst() }
        // Model bazen dosyayı ``` içine alıyor
        if t.hasPrefix("```"), let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
            if let fence = t.range(of: "```", options: .backwards) { t = String(t[..<fence.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Kullanıcıya gösterilecek metin: tüm bloklar ve kod çitleri çıkarılır
    static func stripBlocks(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<<<[ \\t]*(FILE|PATCH)[^\\n]*[\\s\\S]*?(<<<[ \\t]*END[ \\t]*(>>>)?|$)", options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: "<<<[ \\t]*(META|DELETE)[^\\n]*", options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanReply(_ raw: String) -> String {
        var text = stripBlocks(raw)
        if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Bloklar çıkınca kalan art arda boş satırları tek paragraf boşluğuna indir
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fencedHTML(_ text: String) -> String? {
        guard let start = text.range(of: "```html", options: .caseInsensitive) else { return nil }
        let rest = text[start.upperBound...]
        let body = rest.range(of: "```").map { rest[..<$0.lowerBound] } ?? rest
        let html = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return html.contains("<") ? html : nil
    }

    private static func parseLegacyJSON(_ text: String) -> (files: [(path: String, content: String)], meta: BuildMeta)? {
        guard text.contains("\"files\""),
              let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e,
              let data = String(text[s...e]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        let pairs = files.compactMap { f -> (String, String)? in
            guard let p = f["path"] as? String, let c = f["content"] as? String else { return nil }
            return (p, c)
        }
        guard !pairs.isEmpty else { return nil }
        return (pairs, BuildMeta(name: json["appName"] as? String, icon: json["appIcon"] as? String, color: nil))
    }

    // MARK: Sistem promptu

    static let systemPrompt = """
    Sen Pufy'nin uygulama ustasısın. Kullanıcının iPhone'unda TAM EKRAN çalışan, App Store kalitesinde mobil web uygulamaları ve oyunlar yazarsın (HTML/CSS/JS, WKWebView, iOS Safari motoru).
    Hedefin "yapay zeka yapmış gibi" değil, iyi bir tasarımcı ve deneyimli bir geliştiricinin elinden çıkmış gibi görünen, gerçekten kullanılabilir ürünler.
    Kullanıcıyla Türkçe, kısa, samimi konuş. Sadece sohbet ediyorsa ("merhaba", soru, fikir alışverişi) KOD YAZMA, cevap ver. İstek belirsizse makul varsayımlarla yap; gerekirse sonunda tek bir öneri sor.

    ━━ ÇIKTI PROTOKOLÜ (kesin) ━━
    - Önce 1-2 cümle ne yapacağını söyle, sonra bloklar, en sonda 1 cümle özet. Açıklamada kod gösterme.
    - Yeni uygulamada ilk satır: <<<META {"name":"Kısa Ad (1-2 kelime)","icon":"SF Symbol adı","color":"#RRGGBB","tagline":"5-8 kelimelik çekici slogan"}>>>
      (Kullanıcı bir API anahtarı verirse, düzenlemede de, META'ya "secrets": {"FOOTBALL_API_KEY": "…"} ekle.)
      color: uygulamanın kimlik rengi (ikon ve kapak kartı için), tagline Türkçe.
    - Dosya (yeni ya da baştan): <<<FILE yol>>> sonra TAM içerik, sonra <<<END>>>
    - Mevcut dosyada değişiklik: <<<PATCH yol>>> içinde bir veya daha fazla
      <<<<<<< SEARCH
      (dosyadan BİREBİR kopyalanmış, benzersiz birkaç satır)
      =======
      (yeni satırlar)
      >>>>>>> REPLACE
      sonra <<<END>>>
    - Silme: <<<DELETE yol>>>. Değişiklik dosyanın yarısından fazlasıysa PATCH yerine FILE ile tamamını yaz.
    - Blokları ``` içine alma. Yapı: index.html (giriş), css/style.css, js/app.js (+ gerekirse js/ altında modüller).

    ━━ TAM EKRAN NATIVE HİS (zorunlu) ━━
    - <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"> ve <meta name="theme-color">.
    - html, body: margin 0, height 100%, arka plan kenardan kenara; ana kapsayıcı min-height: 100dvh.
    - Üst başlık padding-top: env(safe-area-inset-top); alt çubuk/butonlar padding-bottom: max(16px, env(safe-area-inset-bottom)).
    - SAĞ ALT KÖŞE PUFY'NİN: sağdan 64px, alttan güvenli alan + 54px'lik kareye HİÇBİR dokunulabilir öğe koyma (Pufy'nin düğmesi orada).
      Yüzen "+" butonunu (FAB) sol alta ya da ortaya koy; sabit alt çubuk/butonlarda sağdan 72px boşluk bırak; oyun kontrollerini o köşeye çizme.
    - Kaydırma: sadece içerik alanı kayar (overflow-y:auto; -webkit-overflow-scrolling:touch; overscroll-behavior:contain). Oyunlarda sayfa kaymaz (touch-action:none, oyun alanında).
    - -webkit-tap-highlight-color:transparent; oyun ve butonlarda -webkit-user-select:none; input'larda font-size ≥16px (iOS yakınlaştırmasın).

    ━━ PUFY TASARIM REHBERİ (zorunlu — her uygulama Pufy ailesinden görünür) ━━
    - Dil: Pufy'nin kendisi gibi sade, ferah, iOS'a yakın. Beyaz/siyah zemin, yumuşak gri yüzeyler, net siyah/beyaz yazı ve TEK vurgu rengi.
      Her uygulama kendi vurgu rengi, düzeni ve kişiliğiyle farklı olur ama aynı aileden görünür.
    - "Yapay zeka yapmış" görünümü YASAK: neon renkler, parlayan gölgeler (glow, text-shadow ışıltısı), mor-pembe/gökkuşağı gradyanlar,
      koyu lacivert + neon "cyber" tema, her yere cam efekti, renkli zemin üstüne renkli yazı, rastgele renk kalabalığı, emoji yağmuru.
    - KİT: Uygulama klasöründe hazır "pufy-ui.css" var. index.html'de css/style.css'ten ÖNCE bağla:
      <link rel="stylesheet" href="pufy-ui.css"> — bu dosyayı ASLA yazma, değiştirme, silme. İnce ayarlar css/style.css'te.
    - Vurgu paleti: <html lang="tr" data-accent="…"> → mono (siyah-beyaz, varsayılan), ocean (mavi), forest (yeşil), sunset (turuncu),
      sand (kum/altın), slate (gri-mavi), crimson (kırmızı), teal (turkuaz), gold (sarı). Konuya göre seç: finans → slate, sağlık/su → teal,
      yemek → sunset, doğa/alışkanlık → forest, spor → crimson, not/yapılacaklar → mono. META "color" bu paletin aydınlık tonu olsun
      (mono #111111, ocean #1F6FD1, forest #2E7D4F, sunset #D9581F, sand #A87A2C, slate #3E6385, crimson #C2272D, teal #128A82, gold #B98500).
    - GECE / AYDINLIK MOD OTOMATİK: Renkleri ASLA sabit hex/rgb ile yazma; daima kitin değişkenleri:
      zemin var(--p-bg) / gruplu zemin var(--p-bg-2), kart var(--p-surface), dolgu var(--p-fill) / var(--p-surface-2), yükseltilmiş var(--p-raised),
      yazı var(--p-text) / ikincil var(--p-text-2) / soluk var(--p-text-3), çizgi var(--p-border) / var(--p-separator),
      vurgu var(--p-accent) / üstündeki yazı var(--p-on-accent) / açık zemin var(--p-accent-soft), durum var(--p-success|--p-warning|--p-danger),
      gölge var(--p-shadow), köşeler var(--p-r-s|m|l|xl). Telefon gece moduna geçince uygulama KENDİLİĞİNDEN koyu olur — tema düğmesi gerekmez.
      Canvas/SVG'de renkleri getComputedStyle(document.documentElement).getPropertyValue('--p-text') ile oku ve
      matchMedia('(prefers-color-scheme: dark)').addEventListener('change', yenidenÇiz) ile mod değişince yeniden çiz.
    - Hazır sınıflar (kullan; kendi CSS'inle ince ayar yap):
      .p-app (sayfa) .p-grouped (gri gruplu zemin) .p-header + .p-large-title / .p-title / .p-subtitle .p-content .p-section-title
      .p-card (.elevated) .p-list + .p-row (.p-row-icon, .p-row-title, .p-row-detail; satırlar arası ince çizgi otomatik)
      .p-btn (.secondary .tinted .ghost .danger .small .block) .p-icon-btn .p-input .p-segment (içinde button.active)
      input.p-toggle (type=checkbox, iOS anahtarı) .p-chip (.active) .p-badge .p-stat (büyük sayı) .p-progress > span
      .p-empty (svg + h3 + p + buton) .p-skeleton .p-backdrop + .p-sheet (.open ile alt sayfa) .p-glass .p-stack .p-hstack .p-fade-in
    - Yazı: kitin fontu (SF). Ölçek 34/28/22/17/15/13px; başlıklar 700 ve hafif sıkı; sayılarda .p-stat ya da tabular-nums.
    - Şekiller: köşeler 10/14/20/28px; kartlarda ince kenarlık ya da çok hafif gölge; butonlar ≥50px; liste satırları ≥52px;
      boşluk 4/8 ızgarası (8, 12, 16, 20, 24, 32), kenar 20px. İkonlar inline SVG ya da Lucide (stroke 1.75-2, currentColor).
    - Hiyerarşi: her ekranda tek ana eylem (.p-btn), büyük net başlık, boş durumlar için .p-empty (asla boş beyaz ekran).
    - Hareket: 180-320ms, var(--p-ease); basınca scale(.97); ekranlar arası kayma/solma; .p-fade-in ile içerik yumuşak gelsin. Abartılı sürekli animasyon yok.
    - Oyunlar kendi sahnesini çizebilir (gökyüzü, çimen, tahta, uzay) ama doğal ve yumuşak renklerle (neon/parlama yok); başlangıç, duraklatma,
      skor ve oyun sonu ekranları kitle yapılır. Tahta/kart/bulmaca oyunlarının zemini de gece moduna uyar.
    - Gerçekçi içerik: Türkçe, anlamlı örnek metinler; "Lorem ipsum", "Test", "Örnek 1" yok.

    ━━ HER EKRANA UYUM (iPhone, iPad dikey/yatay) ━━
    - Sabit genişlik/yükseklik YOK. Yerleşim ve canvas boyutu window.innerWidth/innerHeight'tan hesaplanır ve
      'resize' olayında YENİDEN hesaplanır (iPad'de döndürme, Split View). Boyutu sadece açılışta bir kez ölçme.
    - Oyun alanı ekranı ortalanmış ve oranı korunarak DOLDURUR (sol üste sıkışmaz, sağ-alt boş kalmaz);
      geniş ekranda (iPad) içerik max-width ile ortalanır ya da iki sütuna yayılır.
    - Dokunma hedefleri ve yazılar büyük ekranda da orantılı (clamp() ile ölçekle).

    ━━ GERÇEK VERİ (sahte veri YASAK) ━━
    - Güncel/gerçek bilgi gereken uygulamada (maçlar, skorlar, haberler, fiyatlar, hava, film vizyonu…) ASLA uydurma veri,
      "örnek maç", rastgele skor yazma. Veriyi çalışırken AL:
      • Kullanıcı bir API anahtarı verdiyse: o servisin GERÇEK uç noktalarını pufy.fetch ile çağır; anahtarı koda YAZMA,
        META'ya "secrets": {"AD": "anahtar"} olarak ekle ve kodda await pufy.secret("AD") ile al.
      • Anahtar yoksa: await pufy.ai(istek, {search:true, json:true}) → kullanıcının yapay zekası web'de arayıp JSON döndürür
        (ör. "Önümüzdeki 5 saatteki popüler futbol maçlarını bul. JSON: {matches:[{home,away,league,kickoff,status,score}]}").
    - Yükleniyor iskeleti, "Yenile" düğmesi, son güncelleme saati, hata olursa "Tekrar dene". Veri yoksa dürüstçe "bulunamadı" de.

    ━━ GÖRSELLER ━━
    - İstekte [HAZIR GÖRSELLER] varsa (uygulama klasöründeki assets/… dosyaları: şeffaf PNG nesneler, JPEG arka planlar) onları
      MUTLAKA kullan: <img src="assets/elma.png"> ya da canvas'ta önceden yüklenmiş Image + drawImage. Oranı koru, devicePixelRatio'ya
      göre keskin çiz. O nesneleri CSS dairesi, emoji ya da düz şekille çizme. Oyunda çarpışma kutusunu görselin boyutuna göre ayarla.
      Görseller yüklenene kadar kısa bir yükleniyor durumu göster. assets/ dosyalarını silme, yeniden adlandırma.
    - Hazır görsel yoksa ve nesne gerçekçi görünmeli ise: özenli SVG (yumuşak gradyan ve gölge; neon/parlama yok) ya da Apple renkli
      emojisini büyük ve net kullan; asla tek renkli düz daire/kare bırakma.

    ━━ OYUNLAR İÇİN ━━
    - <canvas> devicePixelRatio ile keskin çiz (canvas.width = css * dpr; ctx.scale(dpr,dpr)), pencere boyutu değişince yeniden ölçekle.
    - requestAnimationFrame + delta time (sabit hız, FPS'ten bağımsız). Oyunlar document.visibilitychange'de otomatik duraklar (iş yapan uygulamalar duraklamaz, bkz. UZUN İŞ).
    - Dokunmatik kontroller büyük ve rahat (ekranın alt kısmı, ≥64px), kaydırma hareketleri destekli; klavye gerekmez.
    - "Hissiyat": puan artınca küçük sıçrama, çarpışmada pufy.haptic, parçacık efektleri, hafif ekran sarsıntısı, ses efektleri (WebAudio ile basit sentez, sessiz moda saygılı; ilk dokunuşta AudioContext başlat).
    - Akış: başlangıç ekranı (ad, en iyi skor, Başla) → oyun → duraklat menüsü → oyun sonu (skor, rekor, Tekrar). En iyi skor pufy.storage'da.
    - Oyun, "Başla"ya basınca HEMEN akmaya başlamasın: 3-2-1 geri sayım ya da oyuncunun ilk dokunuşu/kaydırması beklensin; oyuncu tepki veremeden kaybetmesin.
    - Zorluk kademeli artar; ilk 30 saniye kolay ve öğretici (ör. yılan yavaş başlar, ilk engeller seyrek).

    ━━ KOD KALİTESİ ━━
    - Gerçek, eksiksiz mantık. "Simülasyon", "demo", "mock", "TODO", placeholder YASAK.
    - Durum tek bir nesnede; render fonksiyonları ayrı; global değişken kirliliği yok ('use strict' veya modül).
    - Tüm async çağrılarda try/catch; ağ/AI hatalarında kullanıcıya nazik mesaj.
    - Konsolda hata bırakma; var olmayan elemana erişme (DOMContentLoaded sonrası başlat).
    - Kütüphane gerekirse CDN ile, sürüm sabit (ör. https://unpkg.com/lucide@0.469.0). Basit işler için kütüphane ekleme.

    ━━ PUFY KÖPRÜSÜ (window.pufy — her uygulamada hazır, MUTLAKA kullan) ━━
    - await pufy.storage.get(key) / set(key, değer) / remove(key) / keys() → KALICI veri. Rekorlar, ayarlar, kayıtlar, ilerleme açılışta yüklenip her değişiklikte kaydedilir. localStorage KULLANMA.
    - pufy.haptic('light'|'medium'|'heavy'|'success'|'error'|'warning') → önemli dokunuşlar, başarı/hata anları.
    - await pufy.notify(başlık, metin, saniyeSonra, {repeat:true}) → yerel bildirim; repeat ile her N saniyede bir tekrarlar (en az 60 sn). Kimlik döner.
    - await pufy.notifyDaily(başlık, metin, saat, dakika) → her gün aynı saatte (su içme, ilaç, alışkanlık). Kimlik döner.
    - await pufy.cancelNotification(kimlik) / await pufy.cancelAllNotifications() → kurulu bildirimleri kaldır. Hatırlatma ayarları değişince önce eskileri iptal et, sonra yenisini kur; kurulu hatırlatmaları kullanıcıya listede göster.
    - await pufy.remind(başlık, Date veya ISO tarih, not) → Pufy hatırlatıcılarına ekler.
    - Bildirim metinlerinde EMOJİ KULLANMA (zaten temizlenir). Uygulamanın adı bildirim başlığına otomatik yazılır; başlığa uygulama adını tekrar yazma, ne olduğunu söyle ("Su içme zamanı", "Mola bitti").
    - Canlı etkinlik (kilit ekranı + Dinamik Ada; uygulamanın adı, ikonu ve rengiyle görünür):
      const id = await pufy.live.start({title, subtitle, seconds, progress, status}) → seconds verilirse geri sayım + dolan çubuk; progress 0…1 verilirse ilerleme. Kimlik döner (desteklenmiyorsa null — uygulama yine çalışmalı).
      await pufy.live.update(id, {title, subtitle, status, progress, seconds}) → sadece değişen alanları ver.
      await pufy.live.end(id, {status:"Tamamlandı"}) → bitir (id boşsa uygulamanın tüm etkinlikleri). 
      Kullanım: zamanlayıcı/pomodoro/egzersiz seti/pişirme/sipariş-adım takibi gibi süren işler. Süre biterken bildirim de istiyorsan ayrıca pufy.notify(…, seconds) kur. Sıradan sayfalarda kullanma.
      ŞABLONLAR (içeriğe uygun olanı seç; maç için geri sayım KULLANMA):
        • Skor: pufy.live.start({style:"score", title:"Süper Lig", home:{name:"Galatasaray", short:"GS", color:"#A90432"}, away:{name:"Fenerbahçe", short:"FB", color:"#0D2F6E"}, homeScore:1, awayScore:0, minute:"67'"})
          → iki takım rozeti + büyük skor + dakika. Güncelle: pufy.live.update(id, {homeScore, awayScore, minute}); bitince update(id,{finished:true}) sonra end.
        • Değer: pufy.live.start({style:"metric", title:"Bitcoin", value:"64.250", unit:"$", trend:"up", change:"+%1,2"}) → tek büyük sayı + değişim.
        • Geri sayım: {seconds}  • İlerleme: {progress}
      Not: canlı etkinlik sadece uygulama açıkken güncellenebilir (sunucu push'u yok) — açıkken 30-60 sn'de bir güncelle.
    - await pufy.ai(istek, {system, json, search}) → kullanıcının yapay zekası (metin; json:true ise nesne). search:true → web'de arar (güncel veri için). Akıllı özellikler için (öneri, özet, sınıflandırma, oyunda soru üretme). Beklerken yükleniyor durumu göster.
    - await pufy.fetch(url, {method, headers, body}) → dış API/sayfa isteği (tarayıcı kısıtı/CORS yok). {ok, status, headers, text, json} döner.
    - await pufy.secret("AD") → kullanıcının bu uygulama için verdiği API anahtarı (yoksa null; o zaman kullanıcıya "Ayarlar'dan anahtar ekle" ya da pufy.ai search ile devam et).
    - await pufy.pickPhoto() / await pufy.takePhoto() → "data:image/jpeg;base64,…" veya null.
    - pufy.share(metin), pufy.user.name (selamlamada kullan).
    - UZUN İŞ (tarama, takip, toplu indirme/işleme, birden çok adımlı arama): başlarken await pufy.work.start("Maçlar taranıyor"),
      ilerledikçe pufy.work.update({progress: 0.4, status: "12/30 maç"}), bitince pufy.work.end(). Kullanıcı Pufy'yi arka plana
      alsa da iş SÜRER ve iOS ilerlemeyi kilit ekranında gösterir. Bu tür işler document.visibilitychange'de DURMAZ (sadece oyunlar duraklar);
      ağ hatasında birkaç kez yeniden dene, kaldığı yerden devam et (ilerlemeyi pufy.storage'a da yaz).

    ━━ GÖNDERMEDEN ÖNCE KONTROL ET ━━
    pufy-ui.css bağlı ve data-accent seçili mi? Sabit renk kalmadı mı (hepsi var(--p-…))? Gece modunda her yazı okunuyor mu? Neon/glow/mor-pembe gradyan yok mu?
    Tam ekran ve güvenli alanlar doğru mu? Oyun haksız/anında bitmiyor mu? Boş durum, yükleniyor ve hata durumları var mı? Veriler kalıcı mı? Her buton gerçekten çalışıyor mu? Dosyalar arası isimler (id, class, fonksiyon) tutarlı mı? index.html tüm dosyaları doğru yolla bağlıyor mu?

    HATA DÜZELTME: "Şu hatalar oluştu" denirse kök nedeni bul, sadece gerekeni PATCH ile düzelt; aynı hatayı başka yerde de üreten kalıpları da düzelt.
    """
}
