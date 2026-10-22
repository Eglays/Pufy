import Foundation
import SwiftUI

// MARK: - MiniApp Model

struct MiniApp: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var description: String
    var htmlContent: String
    var cssCode: String?
    var htmlCode: String?
    var jsCode: String?
    var messages: [Message]?
    var appSpecJson: String?
    var folderName: String?
    var entryPoint: String? = "index.html"
    /// Ana ekran ikon rengi (#RRGGBB) — yapay zeka uygulamaya göre seçer
    var colorHex: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Bir arkadaşın paylaşımından eklendiyse paylaşım kodu (tekrar açılınca güncellenir, bkz. AppShare.swift)
    var sharedCode: String? = nil
}

// MARK: - Native Built-in App Model

struct NativeBuiltinApp: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String        // SF Symbol (fallback)
    let imageName: String?  // Asset catalog image (tercih edilir)
    let subtitle: String
    let accentColor: Color
    let urlString: String   // PWA olarak yüklenen web adresi

    var spec: AppSpecification {
        AppSpecification(appName: name, appIcon: icon, appType: id, configuration: nil)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: NativeBuiltinApp, rhs: NativeBuiltinApp) -> Bool { lhs.id == rhs.id }
}


// MARK: - App Tab Type

enum AppTabType {
    case chat
    case miniApp(MiniApp)
    case nativeApp(NativeBuiltinApp)
}

// MARK: - App Tab

struct AppTab: Identifiable {
    var id: UUID = UUID()
    var type: AppTabType

    var title: String {
        switch type {
        case .chat:                     return "Pufy"
        case .miniApp(let app):         return app.name
        case .nativeApp(let n):         return n.name
        }
    }

    var icon: String {
        switch type {
        case .chat:                     return "bubble.left.and.bubble.right.fill"
        case .miniApp(let app):         return app.icon
        case .nativeApp(let n):         return n.icon
        }
    }

    var isChatTab: Bool {
        if case .chat = type { return true }
        return false
    }

    var isNativeTab: Bool {
        if case .nativeApp = type { return true }
        return false
    }
}

// MARK: - Tab Manager

class TabManager: ObservableObject {
    static let shared = TabManager()

    /// Tüm tab'lar: [chat, miniApp...]
    /// Sıralama: native'ler solda, chat ortada, AI'lar sağda
    @Published var tabs: [AppTab]             = []
    @Published var activeTabIndex: Int        = 1   // varsayılan: chat
    @Published var isTabSwitcherVisible: Bool = false
    @Published var showAppCreator: Bool       = false
    @Published var creatorInitialName: String?   = nil
    @Published var creatorInitialPrompt: String? = nil
    @Published var creatorEditingApp: MiniApp?   = nil
    /// Uygulama değiştirici bir sonraki açılışta kartlı (pencereli) görünümle açılsın — iki parmakla kıstırınca
    var switcherOpensInCards = false

    func openCreator(name: String? = nil, prompt: String? = nil, editingApp: MiniApp? = nil) {
        creatorInitialName = name
        creatorInitialPrompt = prompt
        creatorEditingApp = editingApp
        showAppCreator = true
    }

    /// İki parmakla kıstırma: iOS'taki gibi pencereli görünüm
    func showSwitcherFromPinch() {
        guard !isTabSwitcherVisible else { return }
        switcherOpensInCards = true
        withAnimation(SmoothSpring.standard) { isTabSwitcherVisible = true }
    }

    private let storageKey      = "pufy_mini_apps_v1"
    private let nativeOrderKey  = "pufy_native_order_v1"

    private init() {
        buildInitialTabs()
        MiniAppFiles.removeLegacyPreviews()
    }

    // MARK: - Başlangıç Tab Yapısı

    private func buildInitialTabs() {
        // Kayıtlı native sırayı yükle; yoksa varsayılan sırayla başla
        let nativeApps = loadedNativeOrder()
        var result: [AppTab] = nativeApps.map { AppTab(type: .nativeApp($0)) }
        result.append(AppTab(type: .chat))
        result += loadedMiniApps().map { AppTab(type: .miniApp($0)) }
        tabs = result
        activeTabIndex = nativeApps.count // Chat her zaman native'lerin hemen sağında
    }

    // Kaydedilmiş native sırayı döndürür; bilinmeyen app'ları atlar, yeni eklenenler sona gelir
    private func loadedNativeOrder() -> [NativeBuiltinApp] {
        // Yerleşik web uygulaması yok
        let all: [NativeBuiltinApp] = []
        guard let savedIds = UserDefaults.standard.stringArray(forKey: nativeOrderKey) else {
            return all // İlk açılış: varsayılan sıra
        }
        let idMap = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var ordered = savedIds.compactMap { idMap[$0] }       // Kayıtlı sırada olanlar
        let savedSet = Set(savedIds)
        ordered += all.filter { !savedSet.contains($0.id) }   // Yeni eklenenler sona
        return ordered
    }

    // Native tab sırasını UserDefaults'a kaydet
    private func saveNativeOrder() {
        let ids = tabs.compactMap { tab -> String? in
            if case .nativeApp(let n) = tab.type { return n.id }
            return nil
        }
        UserDefaults.standard.set(ids, forKey: nativeOrderKey)
    }

    // MARK: - Aktif Tab

    var activeTab: AppTab {
        if tabs.indices.contains(activeTabIndex) { return tabs[activeTabIndex] }
        return tabs.first(where: { $0.isChatTab }) ?? AppTab(type: .chat)
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        withAnimation(SmoothSpring.standard) {
            activeTabIndex = index
            isTabSwitcherVisible = false
        }
    }

    // MARK: - Native App Aç

    func openNativeApp(_ nativeApp: NativeBuiltinApp) {
        if let idx = tabs.firstIndex(where: {
            if case .nativeApp(let n) = $0.type { return n.id == nativeApp.id }
            return false
        }) {
            selectTab(at: idx)
        }
    }

    // MARK: - AI Mini App CRUD

    func addMiniApp(_ app: MiniApp) {
        let tab = AppTab(type: .miniApp(app))
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        isTabSwitcherVisible = false
        saveMiniApps()
    }

    /// Oluşturucu ilk başarılı derlemede uygulamayı kaydeder (aktif sekmeyi değiştirmeden)
    func upsertMiniApp(_ app: MiniApp) {
        if tabs.contains(where: { if case .miniApp(let a) = $0.type { return a.id == app.id }; return false }) {
            updateMiniApp(app)
        } else {
            tabs.append(AppTab(type: .miniApp(app)))
            saveMiniApps()
        }
    }

    func openMiniApp(id: UUID) {
        if let index = tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.id == id }; return false }) {
            selectTab(at: index)
        }
    }

    /// Bildirimden / canlı etkinlikten gelince: klasör adıyla uygulamayı aç
    func openMiniApp(folder: String) {
        if let index = tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.folderName == folder }; return false }) {
            selectTab(at: index)
        }
    }

    func updateMiniApp(_ updated: MiniApp) {
        guard let idx = tabs.firstIndex(where: {
            if case .miniApp(let a) = $0.type { return a.id == updated.id }
            return false
        }) else { return }
        var app = updated
        app.updatedAt = Date()
        tabs[idx] = AppTab(id: tabs[idx].id, type: .miniApp(app))
        saveMiniApps()
    }

    // MARK: Eşitleme (diğer cihazdan gelen) — tarih değiştirilmez, yoksa iki cihaz birbirini sürekli günceller

    func applyRemoteMiniApp(_ app: MiniApp) {
        if let idx = tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.id == app.id }; return false }) {
            tabs[idx] = AppTab(id: tabs[idx].id, type: .miniApp(app))
        } else {
            tabs.append(AppTab(type: .miniApp(app)))
        }
        saveMiniApps()
    }

    func applyRemoteMiniAppDeletion(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { if case .miniApp(let a) = $0.type { return a.id == id }; return false }) else { return }
        if activeTabIndex == idx, let chat = tabs.firstIndex(where: { $0.isChatTab }) { activeTabIndex = chat }
        deleteTab(at: idx)
    }

    var miniApps: [MiniApp] {
        tabs.compactMap { if case .miniApp(let a) = $0.type { return a }; return nil }
    }

    func deleteTab(at index: Int) {
        // Önce sınır kontrolü (eskiden diziye kontrol etmeden erişiliyordu → olası çökme)
        guard tabs.indices.contains(index) else { return }
        // Chat ve native tab'lar silinemez
        let tab = tabs[index]
        if case .chat       = tab.type { return }
        if case .nativeApp  = tab.type { return }
        // Silinen uygulamanın dosyalarını da temizle (eskiden Documents/MiniApps'te birikiyordu)
        if case .miniApp(let app) = tab.type, let folder = app.folderName, !folder.isEmpty {
            MiniAppFiles.deleteAll(folder)   // dosyalar + sürümler + kaydettiği veriler
        }
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
        saveMiniApps()
    }

    func deleteAllMiniApps() {
        for tab in tabs {
            if case .miniApp(let app) = tab.type, let folder = app.folderName, !folder.isEmpty {
                MiniAppFiles.deleteAll(folder)
            }
        }
        tabs.removeAll {
            if case .miniApp = $0.type { return true }
            return false
        }
        activeTabIndex = 0
        saveMiniApps()
    }

    // MARK: - Sıra Değiştirme

    /// Native app'ları kendi grubu içinde yeniden sırala
    func moveNativeTab(from source: IndexSet, to destination: Int) {
        let nativeCount = tabs.prefix(while: { $0.isNativeTab }).count
        let clampedDest = min(destination, nativeCount)
        tabs.move(fromOffsets: source, toOffset: clampedDest)
        PremiumHaptics.light()
        saveNativeOrder() // Sırayı kaydet
    }

    /// AI mini app'ları kendi grubu içinde yeniden sırala
    func moveAITab(from source: IndexSet, to destination: Int) {
        guard let chatIdx = tabs.firstIndex(where: { if case .chat = $0.type { return true }; return false })
        else { return }
        let aiStart = chatIdx + 1
        let aiCount = tabs.count - aiStart
        // Göreli index'leri mutlak index'lere çevir
        let absSource = IndexSet(source.map { $0 + aiStart })
        let absDest   = min(destination + aiStart, aiStart + aiCount)
        guard absDest >= aiStart else { return } // Chat'ın üstüne geçme
        tabs.move(fromOffsets: absSource, toOffset: absDest)
        saveMiniApps()
        PremiumHaptics.light()
    }

    // MARK: - Kalıcılık

    func saveMiniApps() {
        // Uygulama eklendi/silindi/değişti → diğer cihaza hemen gitsin (silme beklemede kalıp geri gelmesin)
        Task { @MainActor in SyncService.shared.scheduleSync(after: 1) }
        let miniApps: [MiniApp] = tabs.compactMap {
            if case .miniApp(let a) = $0.type { return a }
            return nil
        }
        if let data = try? JSONEncoder().encode(miniApps) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadedMiniApps() -> [MiniApp] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let apps = try? JSONDecoder().decode([MiniApp].self, from: data)
        else { return [] }
        return apps
    }
}

// MARK: - Uygulama İkonu (ana ekran, oluşturucu)

struct MiniAppIconTile: View {
    let icon: String
    let colorHex: String?
    var size: CGFloat = 60

    private var background: Color { Color(hex: colorHex) ?? .pufyPrimary }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(background.gradient)
            .overlay {
                Image(systemName: UIImage(systemName: icon) != nil ? icon : "app.dashed")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color(hex: colorHex) == nil ? Color.pufyOnPrimary : .white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.04)
    }
}
