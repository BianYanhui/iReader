import AppKit
import SwiftUI

/// App menu entries for updates, and the Help menu.
struct UpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                updater.checkForUpdatesFromMenu()
            }
            .disabled(updater.isBusy)

            Toggle("自动检查更新", isOn: $updater.autoCheckEnabled)
        }

        CommandGroup(replacing: .help) {
            Button("键盘快捷键") {
                openWindow(id: ShortcutsView.windowID)
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            Button("iReader 主页") {
                if let url = URL(string: "https://github.com/BianYanhui/iReader") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button("检查更新…") {
                updater.checkForUpdatesFromMenu()
            }
            .disabled(updater.isBusy)
        }
    }
}
