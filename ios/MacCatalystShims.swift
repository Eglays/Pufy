// MARK: - Mac (Catalyst) için yedekler
//
// Kullanıcı (20 Ekim 2026): "Mac'te iPad arayüzü olduğu için tam ekrana alamıyorum; sağ ve sol kırpılıyor."
// Pufy artık Mac'te gerçek bir Mac uygulaması (Mac Catalyst): pencere serbestçe boyutlanır, tam ekran kırpılmaz; görünüm
// iPad'dekiyle aynı. Mac'te olmayan iPhone'a özgü özellikler (Dinamik Ada / kilit ekranı canlı etkinlikleri, iOS'un arka plan
// ilerleme görevi) burada sessizce "yok" sayılır — kodun geri kalanı aynen derlenir. Bu dosya iPhone/iPad derlemesine girmez.

#if targetEnvironment(macCatalyst)
import Foundation
import BackgroundTasks

protocol ActivityAttributes {
    associatedtype ContentState: Codable & Hashable
}

struct ActivityContent<State> {
    var state: State
    var staleDate: Date?
    init(state: State, staleDate: Date?) {
        self.state = state
        self.staleDate = staleDate
    }
}

enum ActivityUIDismissalPolicy {
    case `default`, immediate
    static func after(_ date: Date) -> ActivityUIDismissalPolicy { .default }
}

struct ActivityAuthorizationInfo {
    var areActivitiesEnabled: Bool { false }
}

struct PushType {}

struct ActivityUnsupported: Error {}

final class Activity<Attributes: ActivityAttributes> {
    static var activities: [Activity<Attributes>] { [] }
    let id = UUID().uuidString
    let attributes: Attributes
    private(set) var content: ActivityContent<Attributes.ContentState>

    private init(attributes: Attributes, content: ActivityContent<Attributes.ContentState>) {
        self.attributes = attributes
        self.content = content
    }

    static func request(attributes: Attributes, content: ActivityContent<Attributes.ContentState>,
                        pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityUnsupported()
    }

    func update(_ content: ActivityContent<Attributes.ContentState>) async {}
    func end(_ content: ActivityContent<Attributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {}
}

/// iOS 26'nın "arka planda süren iş" görevi Mac'te yok: Mac'te uygulama arka planda zaten çalışmaya devam eder
final class BGContinuedProcessingTask: NSObject {
    let progress = Progress()
    var expirationHandler: (() -> Void)?
    func updateTitle(_ title: String, subtitle: String) {}
    func setTaskCompleted(success: Bool) {}
}

final class BGContinuedProcessingTaskRequest: BGProcessingTaskRequest {
    enum Strategy { case fail, queue }
    var strategy: Strategy = .fail
    convenience init(identifier: String, title: String, subtitle: String) {
        self.init(identifier: "\(identifier).unsupported")
    }
}
#endif
