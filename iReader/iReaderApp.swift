import SwiftUI

@main
struct iReaderApp: App {
    @ObservedObject private var updater = AppUpdater.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .onAppear {
                    updater.checkOnLaunchIfNeeded()
                }
        }
        .commands {
            ViewerCommands()
            UpdateCommands(updater: updater)
        }
    }
}
