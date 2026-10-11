import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: PDFFileDocument
    @Environment(\.undoManager) private var undoManager
    @StateObject private var viewer = ViewerState()
    @State private var selection = Set<ObjectIdentifier>()
    @State private var showCannotDeleteAll = false

    var body: some View {
        Group {
            if document.pdf.pageCount == 0 {
                EmptyDocumentView()
            } else {
                NavigationSplitView {
                    ThumbnailSidebar(document: document, selection: $selection, onDelete: deletePages)
                        .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 320)
                } detail: {
                    PDFKitView(
                        document: document,
                        viewer: viewer,
                        tool: viewer.tool,
                        color: viewer.color,
                        revision: document.revision,
                        undoManager: undoManager
                    )
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .toolbar { toolbarContent }
        .focusedSceneObject(viewer)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: openDroppedFiles)
        .onChange(of: selection) { ids in
            // Clicking a single thumbnail scrolls the document to that page.
            guard ids.count == 1, let id = ids.first,
                  let page = document.pages.first(where: { $0.pageID == id }) else { return }
            viewer.go(to: page)
        }
        .alert("无法删除全部页面", isPresented: $showCannotDeleteAll) {
            Button("好") {}
        } message: {
            Text("PDF 文档至少需要保留一页。")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("工具", selection: $viewer.tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbolName)
                        .help(tool.help)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("标注工具")
        }
        ToolbarItem {
            ColorSwatchPicker(selection: $viewer.color)
        }
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
        ToolbarItem {
            Button(role: .destructive) { deleteSelectedOrCurrentPage() } label: {
                Label("删除页面", systemImage: "trash")
            }
            .help("删除侧栏中选中的页面（未选中时删除当前页）")
            .disabled(document.pdf.pageCount <= 1)
        }
    }

    private func deleteSelectedOrCurrentPage() {
        if !selection.isEmpty {
            deletePages(selection)
        } else if let page = viewer.currentPage {
            deletePages([page.pageID])
        }
    }

    private func deletePages(_ ids: Set<ObjectIdentifier>) {
        let indices = IndexSet(document.pages.enumerated().compactMap { offset, page in
            ids.contains(page.pageID) ? offset : nil
        })
        guard !indices.isEmpty else { return }
        guard indices.count < document.pdf.pageCount else {
            showCannotDeleteAll = true
            return
        }
        document.deletePages(at: indices, undoManager: undoManager)
        selection.subtract(ids)
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
