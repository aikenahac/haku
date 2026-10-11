import SwiftUI

@main
struct HakuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Haku manages its own windows (widget, panel, slips, Tasks, Settings…).
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { AppDelegate.shared?.showSettings(nil) }.keyboardShortcut(",")
                }
                CommandGroup(replacing: .newItem) {
                    Button("New Chat") { AppDelegate.shared?.newChat() }.keyboardShortcut("n")
                    Button("Haku Window") { AppDelegate.shared?.showMain() }.keyboardShortcut("0")
                }
                CommandGroup(after: .sidebar) {
                    Button("Chats") { AppDelegate.shared?.showMain(.chat) }.keyboardShortcut("1")
                    Button("Tasks") { AppDelegate.shared?.showMain(.tasks) }.keyboardShortcut("2")
                    Button("Workflows") { AppDelegate.shared?.showMain(.workflows) }.keyboardShortcut("3")
                }
            }
    }
}
