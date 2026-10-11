import SwiftUI
import PDFKit

struct ContentView: View {
    @ObservedObject var document: PDFFileDocument

    var body: some View {
        Group {
            if document.pdf.pageCount == 0 {
                EmptyDocumentView()
            } else {
                Text("\(document.pdf.pageCount) 页")
            }
        }
        .frame(minWidth: 700, minHeight: 500)
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
