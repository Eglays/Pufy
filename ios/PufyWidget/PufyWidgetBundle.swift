import WidgetKit
import SwiftUI

// MARK: - Pufy Widget Bundle
// Tüm widget ve Live Activity türlerini tek bir Bundle'da toplar.

@main
struct PufyWidgetBundle: WidgetBundle {
    var body: some Widget {
        PufyWidgetLiveActivity()
    }
}
