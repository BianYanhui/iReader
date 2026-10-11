import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: PDFFileDocument
    @StateObject private var viewer = ViewerState()

    var body: some View {
        Group {
            if document.pdf.pageCount == 0 {
                EmptyDocumentView()
            } else {
                PDFKitView(document: document, viewer: viewer, revision: document.revision)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar { toolbarContent }
        .focusedSceneObject(viewer)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: openDroppedFiles)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { viewer.zoomOut() } label: {
                Label("缩小", systemImage: "minus.magnifyingglass")
            }
            .help("缩小")
            Button { viewer.zoomIn() } label: {
                Label("放大", systemImage: "plus.magnifyingglass")
            }
            .help("放大")
            Button { viewer.zoomToFit() } label: {
                Label("适合窗口", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("缩放至适合窗口")
        }
    }

    /// Dropping PDF files onto a window opens each of them as a document.
    private func openDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url,
                      UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
                else { return }
                DispatchQueue.main.async {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
        }
        return accepted
    }
}

/// Shown for a new, empty document (File > New).
struct EmptyDocumentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("将 PDF 文件拖到这里，或选择「文件 > 打开…」")
                .foregroundStyle(.secondary)
            Button("打开…") {
                NSDocumentController.shared.openDocument(nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
