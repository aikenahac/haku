import SwiftUI
enum SettingsSection: String, CaseIterable, Identifiable { case general = "General", models = "Models & agents", hotkeys = "Hotkeys & voice", appearance = "Appearance", about = "About"; var id: String { rawValue } }
struct SettingsView: View { var state: SettingsSectionState; var showWorkflows: () -> Void; var showOnboarding: () -> Void; var body: some View { Text("Settings") } }
