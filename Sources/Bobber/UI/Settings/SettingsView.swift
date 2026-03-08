import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case plugin = "Plugin"
    case sounds = "Sounds"
    case appearance = "Appearance"
    case sessions = "Sessions"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .plugin: return "puzzlepiece.extension"
        case .sounds: return "speaker.wave.2"
        case .appearance: return "paintbrush"
        case .sessions: return "list.bullet.rectangle"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @Binding var config: BobberConfig
    @ObservedObject var claudeCLIManager: ClaudeCLIManager
    let onConfigChanged: () -> Void
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            Group {
                switch selectedCategory {
                case .general:
                    GeneralSettingsView(config: $config, claudeCLIManager: claudeCLIManager, onConfigChanged: onConfigChanged)
                case .plugin:
                    PluginSettingsView(claudeCLIManager: claudeCLIManager)
                case .sounds:
                    SoundsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .appearance:
                    AppearanceSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .sessions:
                    SessionsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .shortcuts:
                    ShortcutsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }
}
