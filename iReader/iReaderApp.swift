import SwiftUI

@main
struct iReaderApp: App {
    @StateObject private var updater = AppUpdater.shared

    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            ContentView(document: file.document)
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
