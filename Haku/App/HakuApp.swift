import SwiftUI

@main
struct HakuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Haku manages its own windows (widget, panel, slips, Tasks, Settings…).
        Settings { EmptyView() }
    }
}
