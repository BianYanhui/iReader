import SwiftUI

/// App menu + Help menu entries for checking updates.
struct UpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                updater.checkForUpdatesFromMenu()
            }
            .disabled(updater.isBusy)

            Toggle("自动检查更新", isOn: $updater.autoCheckEnabled)
        }

        CommandGroup(after: .help) {
            Button("检查更新…") {
                updater.checkForUpdatesFromMenu()
            }
            .disabled(updater.isBusy)
        }
    }
}
