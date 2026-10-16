import SwiftUI

@main
struct iReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var updater = AppUpdater.shared

    init() {
        Prefs.registerDefaults()
        WindowTabbing.enable()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .onAppear {
                    updater.checkOnLaunchIfNeeded()
                }
                .onOpenURL { url in
                    AIBridge.handle(url)
                }
        }
        .commands {
            ViewerCommands()
            UpdateCommands(updater: updater)
        }

        Settings {
            SettingsView()
        }

        Window("键盘快捷键", id: ShortcutsView.windowID) {
            ShortcutsView()
        }
        .windowResizability(.contentSize)
    }
}
