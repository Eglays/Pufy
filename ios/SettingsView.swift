import SwiftUI
import AVFoundation
import PhotosUI

/// Ayarlar — yerel iOS Form yapısı.
/// Liquid Glass içerik kartlarına değil, gezinme katmanına (araç çubuğu, sheet) aittir;
/// iOS 26'da Form ve toolbar bunu kendiliğinden uygular.
struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    // Düzenleme sırasında yerel kopya — "Kaydet"e basılana kadar uygulanmaz
    @State private var apiKey = ""
    @State private var endpoint = ""
    @State private var model = ""
    @State private var format: APIFormat = .gemini
    @State private var imageModel = ""
    @State private var heavyModel = ""
    @State private var streaming = true
    @State private var googleSearch = true
    @State private var searxngURL = ""
    @State private var jinaKey = ""
    @State private var userName = ""
    @State private var avatarData: Data?
    @State private var avatarItem: PhotosPickerItem?

    @State private var showKey = false
    @State private var modelHint = "ör. gemini-2.5-flash"
    @State private var testState: TestState = .idle
    @State private var showMemoryBook = false
    @State private var showPastReminders = false
    @State private var confirmClearChats = false
    @State private var confirmClearMemory = false
    @State private var confirmDeleteAllStep1 = false
    @State private var confirmDeleteAllStep2 = false
    @State private var presentedURL: IdentifiableURL?

    @AppStorage("app_language") private var selectedLanguage = "auto"

    private var currentPreset: ProviderPreset? {
        ProviderPreset.all.first { $0.baseURL == endpoint }
    }

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                providerSection
                advancedSection
                languageSection
                searchSection
                dataSection
                helpSection
                deleteAllDataSection
                aboutAndLegalSection
            }
            .navigationTitle(AppLanguage.isEnglish ? "Settings" : "Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.isEnglish ? "Cancel" : "Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.isEnglish ? "Save" : "Kaydet", action: save)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showMemoryBook) {
                MemoryBookView(viewModel: viewModel)
                    .pufyLargeSheet()
            }
            .sheet(item: $presentedURL) { item in
                SafariView(url: item.url)
            }
            .confirmationDialog(
                AppLanguage.isEnglish ? "Delete all your data?\nChats, notes, reminders, Personal Network, apps, settings, and API keys." : "Tüm verilerin silinsin mi?\nSohbetler, notlar, hatırlatıcılar, Kişisel Ağ, uygulamalar, ayarlar ve API anahtarları.",
                isPresented: $confirmDeleteAllStep1,
                titleVisibility: .visible
            ) {
                Button(AppLanguage.isEnglish ? "Delete" : "Sil", role: .destructive) {
                    confirmDeleteAllStep2 = true
                }
                Button(AppLanguage.isEnglish ? "Cancel" : "Vazgeç", role: .cancel) {}
            }
            .confirmationDialog(
                AppLanguage.isEnglish ? "Final confirmation: This cannot be undone. All data on this device will be reset." : "Son onay: Bu işlem geri alınamaz. Cihazındaki tüm veriler sıfırlanacak ve ilk kuruluma döneceksin.",
                isPresented: $confirmDeleteAllStep2,
                titleVisibility: .visible
            ) {
                Button(AppLanguage.isEnglish ? "Delete Everything" : "Tümünü Sil", role: .destructive) {
                    executeDeleteAllData()
                }
                Button(AppLanguage.isEnglish ? "Cancel" : "Vazgeç", role: .cancel) {}
            }
            // Menüden buraya taşındı (kullanıcı isteği)
            .sheet(isPresented: $showPastReminders) {
                PastRemindersSheet()
            }
            .onChange(of: avatarItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarData = ImageUtils.preparedJPEG(from: image, maxDimension: 600)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Bölümler

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let avatarData, let image = UIImage(data: avatarData) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.pufyPrimary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.pufySoft)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())

                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.pufyOnPrimary, Color.pufyPrimary)
                            .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profil fotoğrafını değiştir")

                TextField(AppLanguage.isEnglish ? "Full name" : "Ad Soyad", text: $userName)
                    .font(.body.weight(.medium))
                    .textContentType(.name)
            }
            .padding(.vertical, 4)
        } header: {
            Text(AppLanguage.isEnglish ? "Profile" : "Profil")
        }
    }

    private var providerSection: some View {
        Section {
            Menu {
                ForEach(ProviderPreset.all) { preset in
                    Button(preset.name) { apply(preset) }
                }
            } label: {
                Label("Hazır sağlayıcı seç", systemImage: "sparkles")
            }

            Picker("API formatı", selection: $format) {
                ForEach(APIFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            LabeledContent("Adres") {
                TextField(format == .gemini ? "https://generativelanguage.googleapis.com" : "https://api.openai.com/v1", text: $endpoint)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }

            if endpoint.lowercased().hasPrefix("http://") && !endpoint.contains("192.168.") && !endpoint.contains("10.") && !endpoint.contains("172.") && !endpoint.contains("localhost") && !endpoint.contains("127.0.0.1") {
                Text(AppLanguage.isEnglish ? "Insecure connection, use https" : "Güvenli olmayan bağlantı, https kullan")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let help = currentPreset?.helpText {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentPreset?.isLocal != true {  // özel sunucuda anahtar isteğe bağlı ama alan görünür
                LabeledContent("API anahtarı") {
                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("anahtar", text: $apiKey)
                            } else {
                                SecureField("anahtar", text: $apiKey)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showKey ? "Anahtarı gizle" : "Anahtarı göster")
                    }
                }
            }

            LabeledContent("Model") {
                TextField(modelHint, text: $model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            // Zor işler: derin araştırma (çok adımlı, paralel arama + doğrulama) ve uygulama yapımı (plan, kod, denetim)
            LabeledContent("Zor işler için model") {
                TextField("boş = ana model", text: $heavyModel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }

            Button(action: runTest) {
                HStack {
                    Label("Bağlantıyı test et", systemImage: "bolt.horizontal.circle")
                    Spacer()
                    switch testState {
                    case .idle: EmptyView()
                    case .running: ProgressView()
                    case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
            .disabled(testState == .running)

            if case .success(let reply) = testState {
                Text("Çalışıyor. Modelin cevabı: \"\(reply.prefix(60))\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if case .failure(let message) = testState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Yapay Zeka")
        } footer: {
            Text(format.footnote + " Ana model her soruda kullanılır. Zor işler modeli (daha çok düşünen) sadece derin araştırmada ve uygulama yaparken devreye girer. Anahtar cihazın Keychain'inde saklanır.")
        }
    }

    private var advancedSection: some View {
        Section {
            Toggle(isOn: $streaming) {
                Label("Canlı yazım (streaming)", systemImage: "text.word.spacing")
            }
            if format == .gemini {
                LabeledContent("Görsel modeli") {
                    TextField("boş = kapalı", text: $imageModel)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
        } header: {
            Text("Gelişmiş")
        } footer: {
            Text("Canlı yazım açıkken cevap, ChatGPT'deki gibi geldikçe ekrana yazılır. Sunucu desteklemiyorsa otomatik olarak normal moda geçilir.")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Dil", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang.rawValue)
                }
            }
        } header: {
            Text("Dil")
        } footer: {
            Text("Dil değişikliği uygulamayı yeniden açınca tam uygulanır.")
        }
    }

    private var searchSection: some View {
        Section {
            if format == .gemini {
                Toggle(isOn: $googleSearch) {
                    Label("Google araması", systemImage: "globe")
                }
            }
            LabeledContent("SearXNG") {
                TextField("http://…:4000", text: $searxngURL)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            LabeledContent("Jina anahtarı") {
                SecureField("opsiyonel", text: $jinaKey)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Web Araması")
        } footer: {
            Text(format == .gemini && googleSearch
                 ? "Google araması açıkken model güncel bilgi gerektiğinde Google'da kendisi arar (en hızlı ve en kapsamlı yol). SearXNG yalnızca Google araması kapalıyken veya OpenAI formatında kullanılır."
                 : "SearXNG adresi girilmezse web araması yapılmaz ve her mesaj doğrudan cevaplanır (daha hızlı). Jina, bulunan sayfaları okumak için kullanılır; anahtarsız da sınırlı çalışır.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                showMemoryBook = true
            } label: {
                Label("Kişisel haritayı aç", systemImage: "point.3.connected.trianglepath.dotted")
            }
            Button {
                showPastReminders = true
            } label: {
                Label("Geçmiş hatırlatıcılar", systemImage: "clock.arrow.circlepath")
            }
            Button(role: .destructive) {
                confirmClearMemory = true
            } label: {
                Label("Hafızayı sıfırla", systemImage: "brain")
            }
            .confirmationDialog("Pufy'nin senin hakkında bildiği her şey silinsin mi?", isPresented: $confirmClearMemory, titleVisibility: .visible) {
                Button("Hafızayı Sıfırla", role: .destructive) {
                    viewModel.saveMemory(ChatViewModel.emptyMemoryText)
                    MemoryStore.shared.resetAll()
                    PremiumHaptics.success()
                }
            }
            Button(role: .destructive) {
                confirmClearChats = true
            } label: {
                Label("Tüm sohbetleri sil", systemImage: "trash")
            }
            .confirmationDialog("Tüm sohbetler kalıcı olarak silinsin mi?", isPresented: $confirmClearChats, titleVisibility: .visible) {
                Button("Sohbetleri Sil", role: .destructive) {
                    viewModel.clearAllSessions()
                    PremiumHaptics.success()
                }
            }
        } header: {
            Text("Hafıza ve Veriler")
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink {
                HowToUseView()
            } label: {
                Label(AppLanguage.isEnglish ? "How to use" : "Nasıl kullanılır", systemImage: "questionmark.circle")
            }

            Button {
                UserDefaults.standard.set(false, forKey: "coach_marks_completed")
                UserDefaults.standard.set(false, forKey: "hint_new_app_shown")
                UserDefaults.standard.set(false, forKey: "hint_mini_exit_shown")
                UserDefaults.standard.set(false, forKey: "hint_memory_shown")
                dismiss()
            } label: {
                Label(AppLanguage.isEnglish ? "Show hints again" : "İpuçlarını tekrar göster", systemImage: "sparkles")
            }
        } header: {
            Text(AppLanguage.isEnglish ? "Help" : "Yardım")
        }
    }

    private var deleteAllDataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDeleteAllStep1 = true
            } label: {
                HStack {
                    Spacer()
                    Text(AppLanguage.isEnglish ? "Delete all my data" : "Tüm verilerimi sil")
                        .foregroundStyle(.red)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
        }
    }

    private var aboutAndLegalSection: some View {
        Section {
            Button {
                if let url = LegalLinks.privacyURL { presentedURL = IdentifiableURL(url: url) }
            } label: {
                HStack {
                    Text(AppLanguage.isEnglish ? "Privacy Policy" : "Gizlilik Politikası")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if let url = LegalLinks.termsURL { presentedURL = IdentifiableURL(url: url) }
            } label: {
                HStack {
                    Text(AppLanguage.isEnglish ? "Terms of Service" : "Kullanım Koşulları")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if let url = LegalLinks.supportURL { presentedURL = IdentifiableURL(url: url) }
            } label: {
                HStack {
                    Text(AppLanguage.isEnglish ? "Support" : "Destek")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if let url = LegalLinks.deletionURL { presentedURL = IdentifiableURL(url: url) }
            } label: {
                HStack {
                    Text(AppLanguage.isEnglish ? "Account & Data Deletion" : "Hesap ve Veri Silme")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Tanıtımı tekrar göster") {
                UserDefaults.standard.set(false, forKey: "pufy_onboarding_done")
                dismiss()
            }

            LabeledContent("Sürüm", value: appVersion)
        } header: {
            Text(AppLanguage.isEnglish ? "About and Legal" : "Hakkında ve Yasal")
        }
    }

    private func executeDeleteAllData() {
        viewModel.clearAllSessions()
        NoteStore.shared.deleteAll()
        ReminderManager.shared.deleteAll()
        viewModel.saveMemory(ChatViewModel.emptyMemoryText)
        MemoryStore.shared.resetAll()
        TabManager.shared.deleteAllMiniApps()
        AIConfig.resetAll()
        AIReportStore.shared.clearAll()
        UserDefaults.standard.set(false, forKey: "pufy_onboarding_done")
        PremiumHaptics.success()
        dismiss()
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - İşlemler

    private func load() {
        let ai = GeminiService.shared
        apiKey = ai.apiKey
        endpoint = ai.endpoint
        model = ai.modelName
        format = ai.apiFormat
        imageModel = ai.imageModelName
        heavyModel = ai.heavyModelName
        streaming = ai.streamingEnabled
        googleSearch = ai.googleSearchEnabled
        searxngURL = SearXNGService.shared.baseUrl
        jinaKey = JinaReaderService.shared.apiKey
        userName = viewModel.userName
        avatarData = viewModel.userProfileImageData
    }

    private func apply(_ preset: ProviderPreset) {
        PremiumHaptics.light()
        format = preset.format
        endpoint = preset.baseURL
        model = preset.modelHint
        modelHint = preset.modelHint.isEmpty ? (AppLanguage.isEnglish ? "Model name" : "Model adı") : "ör. \(preset.modelHint)"
        testState = .idle
    }

    private func save() {
        AIConfig.save(apiKey: apiKey, endpoint: endpoint, model: model, format: format,
                      imageModel: imageModel, streaming: streaming,
                      searxngURL: searxngURL, jinaKey: jinaKey, googleSearch: googleSearch, heavyModel: heavyModel)
        viewModel.saveUserProfile(name: userName.trimmingCharacters(in: .whitespaces), imageData: avatarData)
        PremiumHaptics.success()
        dismiss()
    }

    /// Girilen (henüz kaydedilmemiş) değerlerle küçük bir istek atar, sonra eski ayarları geri koyar
    private func runTest() {
        testState = .running
        let ai = GeminiService.shared
        let previous = (ai.apiKey, ai.endpoint, ai.modelName, ai.apiFormat)
        ai.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.apiFormat = format

        Task {
            let result = await ai.testConnection()
            (ai.apiKey, ai.endpoint, ai.modelName, ai.apiFormat) = previous
            switch result {
            case .success(let reply):
                testState = .success(reply.isEmpty ? "(boş)" : reply)
                PremiumHaptics.success()
            case .failure(let error):
                // Ayarlar teknik ekran: sohbette gösterilmeyen kurulum ipuçları burada
                var message = error.localizedDescription
                switch (error as NSError).code {
                case URLError.timedOut.rawValue:
                    message += "\nİpucu: Sunucu çalışıyor mu? Bulut sunucusunda bu port dışarıya açık mı (ör. AWS güvenlik grubu)?"
                case URLError.cannotConnectToHost.rawValue:
                    message += "\nİpucu: Port doğru mu? Sunucudaki program sadece 127.0.0.1'i dinliyorsa 0.0.0.0'a açılmalı."
                default: break
                }
                testState = .failure(message)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

