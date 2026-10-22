import SwiftUI
import WebKit
import UserNotifications

// MARK: - Uygulama Oluşturucu
//
// Sohbet + canlı önizleme. Yapay zeka yazarken dosya dosya ilerleme görünür, her başarılı
// oluşturmada uygulama otomatik kaydedilir ve önizleme yenilenir. Her değişiklikten önce sürüm
// alınır (saat simgesi → geri dön). Önizlemede hata yakalanırsa "Düzelt" ile yapay zeka onarır.

struct AppCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var tabManager: TabManager

    var editingApp: MiniApp? = nil
    /// Açılır açılmaz gönderilecek istek (ör. çalışan uygulamadaki "Düzelt")
    var initialPrompt: String? = nil
    /// Sohbetten veya öneriden önceden doldurulmuş alanlar (otomatik gönderilmez, onay bekler)
    var prefilledName: String? = nil
    var prefilledPrompt: String? = nil
    var onUpdate: ((MiniApp) -> Void)? = nil


    @StateObject private var builder = AppBuilder()
    @State private var app: MiniApp?
    @State private var folder = UUID().uuidString
    @State private var messages: [Message] = []
    @State private var prompt = ""
    @State private var name = ""
    @State private var icon = "app.dashed"
    @State private var colorHex: String?
    @State private var tagline = ""
    @State private var versions: [MiniAppVersion] = []
    @State private var buildTask: Task<Void, Never>?
    @State private var didSetUp = false
    @State private var restoreTarget: MiniAppVersion?
    @State private var activeWorkID: String?
    /// Sohbetteki gibi yapay zeka destekli dikte
    @StateObject private var dictation = DictationManager()
    @FocusState private var composerFocused: Bool

    private var hasFiles: Bool { app != nil || MiniAppFiles.hasFiles(folder) }

    private static var suggestions: [(String, String)] {
        [
            ("square.grid.3x3.fill", String(localized: "Blok düşürme oyunu")),
            ("creditcard", String(localized: "Harcama takipçisi")),
            ("timer", String(localized: "Pomodoro zamanlayıcı")),
            ("textformat.abc", String(localized: "Kelime tahmin oyunu")),
            ("cart", String(localized: "Alışveriş listesi")),
            ("drop", String(localized: "Su içme takibi"))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // Önizleme sayfası kaldırıldı (kullanıcı isteği): uygulama hazır olunca sohbette kalınır,
            // sağ üstteki "Aç" ile gerçek tam ekran hali açılır. Hatalar çalışan uygulamada yakalanır.
            chatPane
                .pufyBar(edge: .bottom) { composer }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .onAppear(perform: setUp)
        .onDisappear { persistIfNeeded() }
        .confirmationDialog(String(localized: "Bu sürüme dönülsün mü?"), isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Geri Dön")) {
                if let v = restoreTarget { restore(v) }
            }
        } message: {
            Text(String(localized: "Şimdiki hali de sürüm olarak saklanır, istersen tekrar dönebilirsin."))
        }
    }

    // MARK: Üst bar

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemImage: "xmark", size: 38, iconSize: 14, accessibilityLabel: "Kapat") {
                dismiss()
            }

            MiniAppIconTile(icon: icon, colorHex: colorHex, size: 34)

            TextField(String(localized: "Uygulama adı"), text: $name)
                .font(.system(.headline, design: .rounded))
                .submitLabel(.done)
                .onSubmit { persistIfNeeded() }

            if !versions.isEmpty {
                Menu {
                    Section(String(localized: "Sürümler — dokun, geri dön")) {
                        ForEach(versions.prefix(15)) { v in
                            Button {
                                restoreTarget = v
                            } label: {
                                Text("\(Self.timeFormatter.string(from: v.date)) · \(v.label.isEmpty ? String(localized: "Değişiklik") : String(v.label.prefix(36)))")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .pufyGlass(Circle(), interactive: true)
                }
                .accessibilityLabel(String(localized: "Sürüm geçmişi"))
            }

            if let app {
                Button {
                    persistIfNeeded()
                    PremiumHaptics.medium()
                    let id = app.id
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tabManager.openMiniApp(id: id) }
                } label: {
                    Text(String(localized: "Aç"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.pufyPrimary))
                }
                .buttonStyle(PremiumScaleButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.dateFormat = "d MMM HH:mm"
        return f
    }()

    // MARK: Sohbet

    private var chatPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty && !builder.isBuilding {
                        emptyState
                    }

                    let lastModelID = messages.last(where: { $0.role == .model })?.id
                    ForEach(messages) { msg in
                        CreatorMessageRow(message: msg, showAvatar: !builder.isBuilding && msg.id == lastModelID)
                            .id(msg.id)
                    }

                    if builder.isBuilding {
                        BuildProgressCard(builder: builder)
                            .id("build")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .pufyChatScrollAnchor(followBottom: true)
            .pufySoftScrollEdges()
            .onChange(of: messages.count) { _ in
                withAnimation(SmoothSpring.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: builder.isBuilding) { _ in
                withAnimation(SmoothSpring.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Ne yapalım?"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(String(localized: "Bir oyun, bir araç, aklındaki herhangi bir şey. Anlat, ben yazayım; kaydetme, hafıza, bildirim, kamera ve yapay zeka desteği hazır."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.suggestions, id: \.1) { item in
                    Button {
                        PremiumHaptics.light()
                        send(AppLanguage.isEnglish ? "Make a \(item.1)" : "\(item.1) yap")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.0)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 22)
                            Text(item.1)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.pufySoft))
                    }
                    .buttonStyle(PremiumCardButtonStyle())
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 20)
    }

    // MARK: Mesaj kutusu

    private var canSend: Bool {
        !builder.isBuilding && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        Group {
            if dictation.phase != .idle {
                DictationBar(dictation: dictation)
                    .transition(.opacity)
            } else {
                composerField
                    .transition(.opacity)
            }
        }
        .pufyGlass(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(SmoothSpring.standard, value: dictation.phase)
        .onChange(of: dictation.errorMessage) { message in
            guard message != nil else { return }
            dictation.errorMessage = nil
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(hasFiles ? String(localized: "Neyi değiştirelim?") : String(localized: "Nasıl bir uygulama istersin?"), text: $prompt, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                // iPad klavyesi: Enter gönderir, Shift+Enter yeni satır
                .pufySubmitOnReturn(text: $prompt) { if canSend { send(prompt) } }
                .padding(.leading, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { composerFocused = true })

            if !builder.isBuilding && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Yazı kutusu boşken mikrofon (sohbetteki gibi)
                Button {
                    composerFocused = false
                    dictation.start { text in
                        let current = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        prompt = current.isEmpty ? text : current + " " + text
                        composerFocused = true
                    }
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(PremiumScaleButtonStyle())
                .padding(.trailing, 6)
                .padding(.bottom, 6)
                .accessibilityLabel(String(localized: "Konuşarak yaz"))
            } else {
            Button {
                if builder.isBuilding {
                    PremiumHaptics.light()
                    builder.cancel()
                    buildTask?.cancel()
                } else {
                    send(prompt)
                }
            } label: {
                Image(systemName: builder.isBuilding ? "stop.fill" : "arrow.up")
                    .font(.system(size: builder.isBuilding ? 13 : 16, weight: .bold))
                    .foregroundStyle((canSend || builder.isBuilding) ? Color.pufyOnPrimary : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill((canSend || builder.isBuilding) ? Color.pufyPrimary : Color.pufyDisabled))
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .disabled(!canSend && !builder.isBuilding)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .accessibilityLabel(builder.isBuilding ? String(localized: "Durdur") : String(localized: "Gönder"))
            }
        }
    }

    // MARK: Akış

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        if let existing = editingApp {
            app = existing
            name = existing.name
            icon = existing.icon
            colorHex = existing.colorHex
            tagline = existing.description
            folder = existing.folderName ?? folder
            messages = existing.messages ?? []
            versions = MiniAppFiles.versions(folder)
        } else {
            if let prefilledName, !prefilledName.isEmpty {
                name = prefilledName
            }
            if let prefilledPrompt, !prefilledPrompt.isEmpty {
                prompt = prefilledPrompt
            }
        }
        if let initialPrompt, !initialPrompt.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { send(initialPrompt) }
        } else if editingApp == nil {
            // Yeni uygulama: doğrudan yazmaya başlansın
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { composerFocused = true }
        }
    }

    private func send(_ text: String) {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !builder.isBuilding else { return }
        PremiumHaptics.medium()
        composerFocused = false
        let history = Array(messages.filter { !$0.content.isEmpty }.suffix(8))
        withAnimation(SmoothSpring.standard) {
            messages.append(Message(content: request, role: .user))
        }
        prompt = ""

        // Arka plana alınırsa iş sürsün, sistem canlı ilerleme göstersin (iOS 26)
        let workID = UUID().uuidString
        let displayName = name.isEmpty ? "Uygulaman" : name
        BackgroundWork.begin(id: workID, title: "\(displayName) hazırlanıyor", subtitle: "Pufy kodu yazıyor…")
        activeWorkID = workID
        // İlerlemeyi ekran değil oluşturucu bildirir (arka planda ekran güncellenmez)
        builder.backgroundWork = (workID, "\(displayName) hazırlanıyor")

        buildTask = Task {
            defer {
                activeWorkID = nil
                builder.backgroundWork = nil
            }
            do {
                let result = try await builder.build(request: request, history: history, folder: folder)
                BackgroundWork.finish(id: workID, success: true)
                notifyIfBackgrounded(title: result.didChangeFiles ? "\(name.isEmpty ? displayName : name) hazır" : "Pufy cevap verdi",
                                     body: result.didChangeFiles ? "Açmak için dokun." : String(result.reply.prefix(120)))
                var reply = result.reply
                if reply.isEmpty {
                    reply = result.didChangeFiles ? "Hazır! Önizlemeden deneyebilirsin." : "Anladım."
                }
                if !result.failedPatches.isEmpty {
                    reply += "\n\n⚠︎ Şu dosyalarda değişiklik uygulanamadı: \(result.failedPatches.joined(separator: ", ")). Tekrar dener misin?"
                }
                if let note = result.qualityNote { reply += "\n\n" + note }
                var message = Message(content: reply, role: .model)
                message.thinkingSteps = result.changedFiles.map { "✓ \($0)" }

                if let meta = result.meta {
                    if name.isEmpty || app == nil, let n = meta.name, !n.isEmpty { name = n }
                    if let i = meta.icon, UIImage(systemName: i) != nil { icon = i }
                    if let c = meta.color, Color(hex: c) != nil { colorHex = c }
                    if let t = meta.tagline, !t.isEmpty { tagline = t }
                }

                withAnimation(SmoothSpring.standard) { messages.append(message) }

                if result.didChangeFiles {
                    persist()
                    versions = MiniAppFiles.versions(folder)
                    PremiumHaptics.success()
                } else {
                    persistIfNeeded()
                }
            } catch {
                BackgroundWork.finish(id: workID, success: false)
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    notifyIfBackgrounded(title: "\(displayName) oluşturulamadı", body: error.localizedDescription)
                }
                withAnimation(SmoothSpring.standard) {
                    messages.append(Message(content: cancelled ? "Durduruldu." : "Bir sorun oluştu: \(error.localizedDescription)", role: .model))
                }
                persistIfNeeded()
            }
        }
    }

    /// Uygulama arka plandaysa iş bitince haber ver
    private func notifyIfBackgrounded(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = PufyNotifications.clean(title)
        content.body = PufyNotifications.clean(body)
        content.sound = .default
        content.userInfo = ["miniAppFolder": folder]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func restore(_ version: MiniAppVersion) {
        MiniAppFiles.restore(version, folder: folder)
        versions = MiniAppFiles.versions(folder)
        messages.append(Message(content: "\(Self.timeFormatter.string(from: version.date)) sürümüne dönüldü.", role: .model))
        persist()
        PremiumHaptics.success()
    }

    /// Uygulamayı kaydet (ilk başarılı oluşturmada yeni uygulama olarak eklenir)
    private func persist() {
        guard MiniAppFiles.hasFiles(folder) else { return }
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Yeni Uygulama" : name
        if var existing = app {
            existing.name = finalName
            existing.icon = icon
            existing.colorHex = colorHex
            if !tagline.isEmpty { existing.description = tagline }
            existing.messages = messages
            existing.folderName = folder
            existing.appSpecJson = nil
            existing.updatedAt = Date()
            app = existing
            if let onUpdate { onUpdate(existing) } else { tabManager.updateMiniApp(existing) }
        } else {
            let new = MiniApp(name: finalName, icon: icon, description: tagline,
                              htmlContent: "", messages: messages, folderName: folder, colorHex: colorHex)
            app = new
            tabManager.upsertMiniApp(new)
        }
    }

    private func persistIfNeeded() {
        if app != nil { persist() }
    }
}

// MARK: - Parçalar

private struct CreatorMessageRow: View {
    let message: Message
    let showAvatar: Bool

    var body: some View {
        if message.role == .user {
            Text(message.content.hasPrefix("Uygulama çalışırken şu hatalar oluştu") ? "Hataları düzelt" : message.content)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.pufyUserBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 44)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if showAvatar {
                    HStack(spacing: 7) {
                        Image("chat_pp")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        Text("Pufy")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
                MarkdownView(text: message.content)
                let changed = message.thinkingSteps.filter { $0.hasPrefix("✓ ") }
                if !changed.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.gearshape")
                        Text(changed.count == 1 ? String(changed[0].dropFirst(2)) : (AppLanguage.isEnglish ? "\(changed.count) files updated" : "\(changed.count) dosya güncellendi"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.pufySoft))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(SmoothSpring.standard, value: showAvatar)
        }
    }
}

/// Yapay zeka yazarken: ne yaptığı, hangi dosyada olduğu, kaç KB yazdığı
private struct BuildProgressCard: View {
    @ObservedObject var builder: AppBuilder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SpinningPufyIconView()
                    .frame(width: 26, height: 26)
                ShimmerText(text: builder.status.isEmpty ? String(localized: "Düşünüyor…") : builder.status,
                            font: .subheadline.weight(.semibold))
                    .id(builder.status)
            }

            // Ajanın adımları: plan, görseller, kod, deneme (puan), düzeltme
            if !builder.steps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(builder.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Group {
                                switch step.state {
                                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                                case .running: ProgressView().controlSize(.mini)
                                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pufyPrimary)
                                case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                                }
                            }
                            .font(.system(size: 14))
                            .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.footnote.weight(step.state == .running ? .semibold : .regular))
                                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
                                if let detail = step.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(SmoothSpring.standard, value: builder.steps)
            }

            if !builder.liveReply.isEmpty {
                Text(builder.liveReply)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else if builder.files.isEmpty, !builder.reasoning.isEmpty {
                Text(String(builder.reasoning.suffix(240)))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            if !builder.files.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(builder.files) { file in
                        HStack(spacing: 10) {
                            Group {
                                switch file.state {
                                case .writing: ProgressView().controlSize(.mini)
                                case .written: Image(systemName: "checkmark.circle.fill")
                                case .patched: Image(systemName: "pencil.circle.fill")
                                case .deleted: Image(systemName: "trash.circle.fill")
                                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                            .frame(width: 18)
                            Text(file.path)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            // GitHub tarzı satır farkı: +eklenen −silinen
                            HStack(spacing: 4) {
                                if file.added > 0 || file.state == .writing {
                                    Text("+\(file.added)").foregroundStyle(Color(red: 0.13, green: 0.70, blue: 0.33))
                                }
                                if file.removed > 0 {
                                    Text("−\(file.removed)").foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.27))
                                }
                            }
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .contentTransition(.numericText())
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(UIColor.systemBackground)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.pufySoft))
        .animation(SmoothSpring.standard, value: builder.files)
    }
}
