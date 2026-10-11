import SwiftUI

@main
struct iReaderApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            ViewerCommands()
        }
    }
}
