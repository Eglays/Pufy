import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel:  ChatViewModel
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var noteStore = NoteStore.shared
    @ObservedObject private var deckPresenter = SlideDeckPresenter.shared
    @State private var showSideMenu  = false
    @State private var showSettings  = false
    @State private var showSplash    = true
    @State private var dragOffset: CGFloat = 0
    @State private var pinchScale: CGFloat = 1.0
    @State private var showOnboardingConnectAI = false
    @AppStorage("pufy_onboarding_done") private var onboardingDone = false
    @AppStorage("coach_marks_completed") private var coachMarksCompleted = false
    @State private var showCoachMarks = false
    
    var body: some View {
        ZStack {
            // MARK: Aktif sekme içeriği
            ZStack {
                if case .chat = tabManager.activeTab.type {
                    chatWithSideMenu
                } else if case .miniApp(let app) = tabManager.activeTab.type {
                    MiniAppView(app: app)
                        .environmentObject(tabManager)
                } else if case .nativeApp(let nativeApp) = tabManager.activeTab.type {
                    NativeAppShellView(nativeApp: nativeApp)
                        .environmentObject(tabManager)
                        .id(nativeApp.id)  // Farklı app'a geçince view tamamen yeniden oluşur
                }
            }
            // Pinch gesture — sıkıştır → Tab Switcher (drag ile çakışmaz)
            .scaleEffect(tabManager.isTabSwitcherVisible ? 0.88 : (pinchScale < 1 ? max(pinchScale, 0.7) : 1.0))
            .animation(SmoothSpring.standard, value: tabManager.isTabSwitcherVisible)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        pinchScale = value
                        if value < 0.82 && !tabManager.isTabSwitcherVisible && !showCoachMarks {
                            tabManager.showSwitcherFromPinch()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(SmoothSpring.standard) {
                            pinchScale = 1.0
                        }
                    }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
                    .pufyLargeSheet()
            }
            // MARK: Hata Bildirimi (cam kapsül — kırmızı dolu kutu yerine)
            .overlay(alignment: .top) {
                if let error = viewModel.errorMessage {
                    ErrorBanner(rawMessage: error, onOpenSettings: { showSettings = true }) {
                        withAnimation(SmoothSpring.standard) { viewModel.errorMessage = nil }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(error)
                }
            }
            .animation(SmoothSpring.standard, value: viewModel.errorMessage)

            // MARK: Sağ kenardan çek → Uygulamalar
            EdgeSwipeToApps(isEnabled: !showSideMenu && !tabManager.isTabSwitcherVisible && !showSplash) {
                withAnimation(SmoothSpring.standard) { tabManager.isTabSwitcherVisible = true }
            }
            .zIndex(40)

            // MARK: Tab Switcher Overlay
            if tabManager.isTabSwitcherVisible {
                TabSwitcherView(initialTabID: tabManager.activeTab.id, initialIndex: tabManager.activeTabIndex)
                    .environmentObject(tabManager)
                    .environmentObject(viewModel)
                    .transition(.opacity)
                    .zIndex(50)
            }
            
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(100)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                showSplash = false
                            }
                        }
                    }
            }

            // MARK: İlk Açılış İpuçları (Coach marks)
            if showCoachMarks {
                CoachMarksView(isPresented: $showCoachMarks)
                    .transition(.opacity)
                    .zIndex(85)
            }
        }
        // İlk açılış rehberi (bir kez)
        // Not sayfası (menüden ya da sohbetteki "Not güncellendi" rozetinden)
        .fullScreenCover(item: $deckPresenter.presented) { presented in
            SlideDeckViewer(deck: presented.deck)
        }
        .sheet(item: $noteStore.presented) { presented in
            NoteDetailView(noteID: presented.id, startEditing: presented.editing)
                .pufyLargeSheet()
        }
        .fullScreenCover(isPresented: $tabManager.showAppCreator) {
            AppCreatorView(
                editingApp: tabManager.creatorEditingApp,
                prefilledName: tabManager.creatorInitialName,
                prefilledPrompt: tabManager.creatorInitialPrompt
            ) { updated in
                tabManager.updateMiniApp(updated)
            }
            .environmentObject(tabManager)
        }
        .fullScreenCover(isPresented: Binding(get: { (!onboardingDone && !showSplash) || showOnboardingConnectAI }, set: { if !$0 { onboardingDone = true; showOnboardingConnectAI = false } })) {
            OnboardingView(
                needsSetup: !GeminiService.shared.isConfigured,
                initialStep: showOnboardingConnectAI ? .connectAI : .intro(0),
                onOpenSettings: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showSettings = true } },
                onFinish: {
                    onboardingDone = true
                    showOnboardingConnectAI = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("pufy_open_ai_connect"))) { _ in
            showOnboardingConnectAI = true
        }
        .onAppear { updateCoachMarksVisibility() }
        .onChange(of: onboardingDone) { _ in updateCoachMarksVisibility() }
        .onChange(of: showSplash) { _ in updateCoachMarksVisibility() }
        .onChange(of: showSettings) { _ in updateCoachMarksVisibility() }
        .onChange(of: tabManager.isTabSwitcherVisible) { _ in updateCoachMarksVisibility() }
        .onChange(of: showSideMenu) { _ in updateCoachMarksVisibility() }
        .onChange(of: showOnboardingConnectAI) { _ in updateCoachMarksVisibility() }
        .onChange(of: coachMarksCompleted) { _ in updateCoachMarksVisibility() }
    }

    private func updateCoachMarksVisibility() {
        let isClean = onboardingDone && !showSplash && !showSettings && !tabManager.isTabSwitcherVisible && !showSideMenu && !showOnboardingConnectAI && !coachMarksCompleted
        if isClean && !showCoachMarks {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if onboardingDone && !showSplash && !showSettings && !tabManager.isTabSwitcherVisible && !showSideMenu && !showOnboardingConnectAI && !coachMarksCompleted {
                    withAnimation(SmoothSpring.standard) {
                        showCoachMarks = true
                    }
                }
            }
        } else if !isClean && showCoachMarks {
            withAnimation(SmoothSpring.standard) {
                showCoachMarks = false
            }
        }
    }
    
    // MARK: Sohbet + Yan Menü
    // ChatGPT gibi: menü ekranın ~%85'ini kaplar, sohbet sağda görünmeye devam eder ve kararır.
    // Genişlik GeometryReader'dan gelir → iPad'de ve Split View'da da doğru (UIScreen.main değil).
    private var chatWithSideMenu: some View {
        GeometryReader { geo in
            let menuWidth = min(geo.size.width * 0.84, 380)
            let base: CGFloat = showSideMenu ? menuWidth : 0
            let reveal = min(max(base + dragOffset, 0), menuWidth)
            let progress = menuWidth > 0 ? reveal / menuWidth : 0
            
            // Diğer uygulamalardaki gibi: menü ALTTA durur, sohbet sayfası ÜSTTE kart gibi sağa kayar.
            // Sohbetin köşeleri ovalleşir ve arkasına yumuşak bir gölge düşer; menüden sadece sohbetin sol kısmı görünür.
            let corner = 46 * progress
            ZStack(alignment: .leading) {
                SideMenuView(viewModel: viewModel, isPresented: $showSideMenu, showSettings: $showSettings)
                    .frame(width: menuWidth)
                    // Hafif derinlik: menü açılırken biraz soldan gelir
                    .offset(x: (reveal - menuWidth) * 0.25)

                ChatView(viewModel: viewModel, showSideMenu: $showSideMenu, onOpenApps: {
                    withAnimation(SmoothSpring.standard) { tabManager.isTabSwitcherVisible = true }
                }, autoFocusOnLaunch: true)
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay {
                    Color.black
                        .opacity(0.06 * progress)
                        .ignoresSafeArea()
                        .allowsHitTesting(showSideMenu)
                        .onTapGesture {
                            withAnimation(SmoothSpring.standard) { showSideMenu = false }
                        }
                }
                // Maske tam ekran: oval köşeler durum çubuğunun ve ana ekran çizgisinin olduğu yerde de çizilsin
                .mask(RoundedRectangle(cornerRadius: corner, style: .continuous).ignoresSafeArea())
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.20 * progress), radius: 26, x: -4, y: 0)
                        .ignoresSafeArea()
                )
                .offset(x: reveal)
            }
            .animation(SmoothSpring.standard, value: showSideMenu)
            .gesture(sideMenuDrag(menuWidth: menuWidth, screenWidth: geo.size.width))
        }
    }
    
    private func sideMenuDrag(menuWidth: CGFloat, screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let fromLeftEdge = !showSideMenu && value.startLocation.x < 40
                // Kenar dışından başlayan kaydırmada yatay niyet şart (dikey kaydırmayı çalmasın)
                guard fromLeftEdge || abs(dx) > abs(dy) * 1.2 else { return }
                if !showSideMenu {
                    dragOffset = min(max(dx, 0), menuWidth)
                } else {
                    dragOffset = max(min(dx, 0), -menuWidth)
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let velocity = value.predictedEndTranslation.width - dx
                withAnimation(SmoothSpring.standard) {
                    if !showSideMenu && dragOffset > 0 && (dx > menuWidth * 0.3 || velocity > 250) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showSideMenu = true
                    } else if showSideMenu && dragOffset < 0 && (dx < -menuWidth * 0.3 || velocity < -250) {
                        showSideMenu = false
                    }
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Hata Bildirimi

private struct ErrorBanner: View {
    let rawMessage: String
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var showDetails = false

    private var parsed: (userFriendly: String, detail: String) {
        let isEn = AppLanguage.isEnglish
        let lower = rawMessage.lowercased()

        let friendly: String
        if lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") || lower.contains("anahtar geçersiz") || lower.contains("invalid api key") || lower.contains("invalid_api_key") {
            friendly = isEn ? "API key is invalid or unauthorized. Please check your key." : "API anahtarı geçersiz ya da yetkisi yok. Anahtarını kontrol et."
        } else if lower.contains("404") || lower.contains("model bulunamadı") || lower.contains("model_not_found") || lower.contains("not found") {
            friendly = isEn ? "Selected model was not found. Re-select via 'Fetch models' in Settings." : "Seçili model bulunamadı. Ayarlar'dan 'Modelleri getir' ile yeniden seç."
        } else if lower.contains("429") || lower.contains("rate limit") || lower.contains("rate_limit") || lower.contains("resource_exhausted") || lower.contains("too many requests") {
            friendly = isEn ? "Provider rate limit reached. Please wait a moment or choose another model." : "Sağlayıcı istek sınırına ulaşıldı. Biraz bekleyip tekrar dene ya da başka bir model seç."
        } else if lower.contains("402") || lower.contains("quota") || lower.contains("bakiye") || lower.contains("insufficient_quota") || lower.contains("billing") {
            friendly = isEn ? "No quota or balance remaining on provider account." : "Sağlayıcı hesabında kota ya da bakiye kalmamış."
        } else if lower.contains("zaman aşımı") || lower.contains("timed out") || lower.contains("bağlanılamadı") || lower.contains("cannot connect") || lower.contains("ulaşılamıyor") || lower.contains("internet") || lower.contains("offline") {
            friendly = isEn ? "Could not reach AI. Check your internet (or same Wi-Fi for local models)." : "Yapay zekaya ulaşılamadı. İnternetini (yerel modelde aynı Wi-Fi'yi) kontrol et."
        } else if lower.contains("500") || lower.contains("502") || lower.contains("503") || lower.contains("504") || lower.contains("530") || lower.contains("server error") {
            friendly = isEn ? "Provider is currently unresponsive. Please try again shortly." : "Sağlayıcı şu an yanıt vermiyor. Biraz sonra tekrar dene."
        } else {
            friendly = isEn ? "Request could not be completed." : "İstek tamamlanamadı."
        }

        var masked = rawMessage
        let savedKey = UserDefaults.standard.string(forKey: "pufy_api_key") ?? ""
        if !savedKey.isEmpty && savedKey.count > 5 {
            masked = masked.replacingOccurrences(of: savedKey, with: "••••••••")
        }
        masked = masked.replacingOccurrences(of: #"sk-[a-zA-Z0-9_\-]{8,}"#, with: "sk-••••••••", options: .regularExpression)
        masked = masked.replacingOccurrences(of: #"AIza[a-zA-Z0-9_\-]{12,}"#, with: "AIza••••••••", options: .regularExpression)

        return (friendly, masked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16))

                Text(parsed.userFriendly)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                Spacer(minLength: 4)

                Button(action: onOpenSettings) {
                    Text(AppLanguage.isEnglish ? "Settings" : "Ayarları aç")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.pufyOnPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.pufyPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kapat")
            }

            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(AppLanguage.isEnglish ? "Details" : "Ayrıntı")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if showDetails {
                Text(parsed.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.pufySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .pufyGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: Color.orange.opacity(0.12))
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { onClose() }
        }
    }
}

// MARK: - Yan Menü (Sidebar)

struct SideMenuView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @ObservedObject private var reminderManager = ReminderManager.shared
    @ObservedObject private var noteStore = NoteStore.shared
    
    @State private var editingReminder : Reminder? = nil
    @State private var showAllNotes = false
    @State private var showMemoryBook  = false
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    /// "Tümünü gör" ile açılan bölümler
    @State private var showAllReminders = false
    @State private var showAllSessions = false
    @State private var showAllSpace = false

    private static let reminderLimit = 3
    private static let sessionLimit = 7
    
    // Rename Session states
    @State private var showRenameAlert = false
    @State private var renameSessionTarget: ChatSession? = nil
    @State private var renameSessionTitle = ""
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    /// Sohbet arama: başlıkta veya mesajlarda geçen
    private var filteredSessions: [ChatSession] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return viewModel.sessions }
        return viewModel.sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(q)
                || session.messages.contains { $0.content.localizedCaseInsensitiveContains(q) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Başlık: "Pufy" + küçük yuvarlak arama düğmesi (eskiden tam genişlik arama kutusu yer kaplıyordu)
            Group {
                if searching {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Sohbetlerde ara", text: $query)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .focused($searchFocused)
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .accessibilityLabel("Aramayı temizle")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .pufyGlass(Capsule())

                        Button("Vazgeç") {
                            withAnimation(SmoothSpring.standard) {
                                query = ""
                                searching = false
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    HStack {
                        Text("Pufy")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        GlassIconButton(systemImage: "magnifyingglass", size: 40, iconSize: 15,
                                        accessibilityLabel: "Sohbetlerde ara") {
                            withAnimation(SmoothSpring.standard) { searching = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty {
                        remindersSection
                        Divider().padding(.horizontal)
                        notesSection
                        Divider().padding(.horizontal)
                    }
                    
                    // Görev sohbetleri (zamanlanmış görevler)
                    let spaceSessions = filteredSessions.filter { $0.isSpaceChatValue }
                    if !spaceSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionHeader("Görevler", icon: nil)
                            let shown = (showAllSpace || !query.isEmpty) ? spaceSessions : Array(spaceSessions.prefix(Self.reminderLimit))
                            ForEach(shown) { session in
                                sessionRow(session: session, icon: "sparkles")
                            }
                            if spaceSessions.count > Self.reminderLimit && query.isEmpty {
                                showAllButton(expanded: showAllSpace, hidden: spaceSessions.count - Self.reminderLimit) {
                                    showAllSpace.toggle()
                                }
                            }
                        }
                        Divider().padding(.horizontal)
                    }
                    
                    // Sabitlenenler
                    let pinnedSessions = filteredSessions.filter { $0.isPinned && !$0.isSpaceChatValue }
                    if !pinnedSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionHeader("Sabitlenenler", icon: nil)
                            ForEach(pinnedSessions) { session in
                                sessionRow(session: session, icon: "pin.fill")
                            }
                        }
                    }
                    
                    // Geçmiş Sohbetler
                    let recentSessions = filteredSessions.filter { !$0.isPinned && !$0.isSpaceChatValue }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader(query.isEmpty ? "Sohbetler" : "Sonuçlar", icon: nil)
                        if recentSessions.isEmpty && pinnedSessions.isEmpty && spaceSessions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.tertiary)
                                Text(query.isEmpty ? "Henüz sohbet yok" : "Sonuç bulunamadı")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        } else {
                            // 7'den fazlası "Tümünü gör" altında (aramada hepsi)
                            let shown = (showAllSessions || !query.isEmpty) ? recentSessions : Array(recentSessions.prefix(Self.sessionLimit))
                            ForEach(shown) { session in
                                sessionRow(session: session, icon: nil)
                            }
                            if recentSessions.count > Self.sessionLimit && query.isEmpty {
                                showAllButton(expanded: showAllSessions, hidden: recentSessions.count - Self.sessionLimit) {
                                    showAllSessions.toggle()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            
            footer
        }
        .padding(.top, 8)
        // Düz, tam beyaz (koyu temada siyah) zemin — oval köşeler ve gölge üstteki sohbet sayfasında
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showMemoryBook) {
            MemoryBookView(viewModel: viewModel)
                .pufyLargeSheet()
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorSheet(reminder: reminder, isNew: reminder.title.isEmpty) { saved in
                if saved.title.isEmpty { return }
                if reminderManager.reminders.contains(where: { $0.id == saved.id }) {
                    reminderManager.update(saved)
                } else {
                    reminderManager.add(saved)
                }
            }
        }
        .alert("Yeniden Adlandır", isPresented: $showRenameAlert) {
            TextField("Yeni Başlık", text: $renameSessionTitle)
            Button("İptal", role: .cancel) { renameSessionTarget = nil }
            Button("Kaydet") {
                if let target = renameSessionTarget {
                    var updated = target
                    let trimmed = renameSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        updated.title = trimmed
                        viewModel.updateSessionInList(updated)
                    }
                }
                renameSessionTarget = nil
            }
        } message: {
            Text("Sohbet için yeni bir başlık girin.")
        }
    }
    
    /// Bölüm başlığı: kalın (kullanıcı isteği)
    private func sectionHeader(_ title: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// "Tümünü gör (4)" / "Daha az göster"
    private func showAllButton(expanded: Bool, hidden: Int, action: @escaping () -> Void) -> some View {
        Button {
            PremiumHaptics.light()
            withAnimation(SmoothSpring.standard) { action() }
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? "Daha az göster" : "Tümünü gör (\(hidden))")
                    .font(.footnote.weight(.semibold))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: Notlar (yapay zekanın aldığı notlar — sadece başlıklar; dokununca not sayfası)

    private static let noteLimit = 4

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader("Notlar", icon: nil)
                Spacer()
                Button {
                    PremiumHaptics.light()
                    let note = noteStore.create()
                    noteStore.presented = .init(id: note.id, editing: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yeni not")
                .padding(.trailing, 14)
                .padding(.bottom, 4)
            }
            let notes = noteStore.sorted
            if notes.isEmpty {
                Text("Sohbette \"bunu not al\" ya da \"alışveriş listeme ekle\" demen yeterli.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                let shown = showAllNotes ? notes : Array(notes.prefix(Self.noteLimit))
                ForEach(shown) { note in
                    NoteRow(note: note) { noteStore.presented = .init(id: note.id) }
                        .contextMenu {
                            ShareLink(item: "\(note.title)\n\n\(note.content)") { Label("Paylaş", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { withAnimation { noteStore.delete(note.id) } } label: { Label("Sil", systemImage: "trash") }
                        }
                }
                if notes.count > Self.noteLimit {
                    showAllButton(expanded: showAllNotes, hidden: notes.count - Self.noteLimit) { showAllNotes.toggle() }
                }
            }
        }
    }

    // MARK: Hatırlatıcılar
    
    private var remindersSection: some View {
        // Geçmiş hatırlatıcılar Ayarlar'a taşındı (kullanıcı isteği)
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Hatırlatıcılar", icon: nil)

            if reminderManager.visibleReminders.isEmpty {
                Text("Sohbette \"yarın 9'da hatırlat\" demen yeterli.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                // Sıradaki 3 hatırlatıcı; gerisi "Tümünü gör" altında
                let upcoming = reminderManager.visibleReminders.sorted { $0.nextOccurrence < $1.nextOccurrence }
                let shown = showAllReminders ? upcoming : Array(upcoming.prefix(Self.reminderLimit))
                ForEach(shown) { reminder in
                    reminderRow(reminder: reminder)
                }
                if upcoming.count > Self.reminderLimit {
                    showAllButton(expanded: showAllReminders, hidden: upcoming.count - Self.reminderLimit) {
                        showAllReminders.toggle()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func reminderRow(reminder: Reminder) -> some View {
        Button {
            editingReminder = reminder
        } label: {
            // Sade satır: sadece başlık ve zaman (ikon ve not yok; ayrıntı dokununca açılır)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if reminder.isAITask, let next = reminder.taskNextCheck, reminder.taskDone != true {
                            // Olay bekleniyor (ör. ilk 11'ler henüz açıklanmadı)
                            Text("Bekleniyor · sonraki kontrol \(Self.timeFormatter.string(from: next))")
                        } else {
                            Text(Self.dateFormatter.string(from: reminder.nextOccurrence))
                        }
                        if reminder.repeatType != .none {
                            Text("· \(reminder.repeatType.localizedName)")
                                .foregroundStyle(Color.pufyReminder)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Liquid Glass buton
            .pufyGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .contextMenu {
            Button {
                editingReminder = reminder
            } label: {
                Label("Düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                withAnimation { reminderManager.delete(reminder) }
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
    
    // MARK: Sohbet Satırı
    // Not: Eskiden burada .swipeActions vardı ama swipeActions yalnızca List içinde çalışır;
    // bu ScrollView olduğu için hiç çalışmıyordu. Silme/sabitleme basılı tutma menüsünde.
    
    @ViewBuilder
    private func sessionRow(session: ChatSession, icon: String?) -> some View {
        let isCurrent = viewModel.currentSessionID == session.id
        
        Button {
            withAnimation(SmoothSpring.standard) {
                viewModel.selectSession(session)
                isPresented = false
            }
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.pufyPrimary)
                }
                Text(session.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if viewModel.generatingSessionID == session.id {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.pufySoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumCardButtonStyle())
        .padding(.horizontal, 8)
        .contextMenu {
            Button {
                renameSessionTarget = session
                renameSessionTitle = session.title
                showRenameAlert = true
            } label: {
                Label("Yeniden Adlandır", systemImage: "pencil")
            }
            if !session.isSpaceChatValue {
                Button {
                    withAnimation { viewModel.togglePinSession(session) }
                } label: {
                    Label(session.isPinned ? "Sabitlemeyi Kaldır" : "Sabitle",
                          systemImage: session.isPinned ? "pin.slash" : "pin")
                }
            }
            Button(role: .destructive) {
                withAnimation { viewModel.deleteSession(session) }
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
    
    // MARK: Alt Profil Kartı
    // ChatGPT'deki gibi: karta dokun → Ayarlar. Fotoğrafa dokun → Kişisel harita.
    // (Eski "3 saniye basılı tut" gizli hareketi kimsenin bulamayacağı bir yoldu.)
    
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                showMemoryBook = true
            } label: {
                ZStack {
                    if let data = viewModel.userProfileImageData,
                       let uiImage = ThumbnailCache.shared.image(for: data, key: "profile-\(data.count)", maxPixel: 160) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(Color.pufyPrimary.opacity(0.7))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.pufyPrimary.opacity(0.35), lineWidth: 1.5))
            }
            .buttonStyle(PremiumScaleButtonStyle())
            .accessibilityLabel("Kişisel harita")
            
            Button {
                showSettings = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.userName.isEmpty ? "Profil" : viewModel.userName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(GeminiService.shared.modelName.isEmpty ? "Model seçilmedi" : GeminiService.shared.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PremiumCardButtonStyle())
            .accessibilityLabel("Ayarlar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .pufyGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Reminder Editor Sheet

struct ReminderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var reminder: Reminder
    let isNew: Bool
    let onSave: (Reminder) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Başlık") {
                    TextField("Hatırlatıcı başlığı", text: $reminder.title)
                }
                
                Section("Tarih & Saat") {
                    DatePicker("Tarih", selection: $reminder.date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .environment(\.locale, AppLanguage.swiftUILocale)
                }
                
                Section("Tekrar") {
                    Picker("Tekrar", selection: $reminder.repeatType) {
                        ForEach(ReminderRepeat.allCases, id: \.self) { type in
                            Label(type.localizedName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Not") {
                    TextField("Not ekle...", text: $reminder.note, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(isNew ? "Yeni Hatırlatıcı" : "Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(reminder)
                        dismiss()
                    }
                    .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}



// MARK: - Past Reminders Sheet
struct PastRemindersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reminderManager = ReminderManager.shared
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                if reminderManager.pastReminders.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("Geçmiş hatırlatıcı bulunmuyor.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(reminderManager.pastReminders) { reminder in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(reminder.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                if !reminder.note.isEmpty {
                                    Text(reminder.note)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.caption2)
                                    Text(dateFormatter.string(from: reminder.date))
                                        .font(.caption2)
                                    Spacer()
                                    if reminder.isAITask {
                                        Text("Ajan Görevi")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.pufyPrimary.opacity(0.12))
                                            .foregroundColor(.pufyPrimary)
                                            .cornerRadius(4)
                                    }
                                }
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Hatırlatıcı Geçmişi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Kapat") { dismiss() }
                }
                
                if !reminderManager.pastReminders.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Temizle", role: .destructive) {
                            reminderManager.clearPastReminders()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}


// MARK: - Splash View (Apple tarzı zarif animasyon)
struct SplashView: View {
    @State private var logoVisible = false
    @State private var textVisible = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                Image("chat_pp")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoVisible ? 1.0 : 0.6)
                    .opacity(logoVisible ? 1 : 0)
                
                Text("Pufy")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .opacity(textVisible ? 1 : 0)
                    .offset(y: textVisible ? 0 : 8)
            }
        }
        .onAppear {
            // Logo: zarif scale-up + fade-in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                logoVisible = true
            }
            // Yazı: logo yerleştikten sonra subtle slide-up
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                textVisible = true
            }
        }
    }
}
