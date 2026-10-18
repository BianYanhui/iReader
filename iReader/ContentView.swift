import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: PDFFileDocument
    let fileURL: URL?

    @Environment(\.undoManager) private var undoManager
    @StateObject private var viewer = ViewerState()
    @State private var showCannotDeleteAll = false
    @State private var goToPageText = ""

    var body: some View {
        Group {
            if document.isLocked {
                UnlockView(document: document)
            } else if document.pdf.pageCount == 0 {
                EmptyDocumentView()
            } else {
                NavigationSplitView {
                    SidebarView(document: document, viewer: viewer, onDelete: deletePages)
                        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 360)
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
        .frame(minWidth: 760, minHeight: 500)
        .toolbar { toolbarContent }
        .focusedSceneObject(viewer)
        .focusedObject(viewer)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: openDroppedFiles)
        .onAppear {
            viewer.document = document
            viewer.undoManager = undoManager
            viewer.fileURL = fileURL
            // Ensure this document window joins the shared tab group.
            DispatchQueue.main.async {
                WindowTabbing.configureOpenWindows()
                if let window = NSApp.keyWindow {
                    WindowTabbing.attachNewDocumentWindowIfNeeded(window)
                }
            }
        }
        .onChange(of: fileURL) { url in
            viewer.fileURL = url
        }
        .onChange(of: viewer.selection) { ids in
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
        .alert("前往页面", isPresented: $viewer.showGoToPage) {
            TextField("页码", text: $goToPageText)
            Button("前往") {
                if let number = Int(goToPageText.trimmingCharacters(in: .whitespaces)) {
                    viewer.go(toPageIndex: number - 1)
                }
                goToPageText = ""
            }
            Button("取消", role: .cancel) { goToPageText = "" }
        } message: {
            Text("输入 1 – \(document.pdf.pageCount) 之间的页码")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            PageIndicator(viewer: viewer)
        }
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
            Menu {
                Button("放大") { viewer.zoomIn() }
                Button("缩小") { viewer.zoomOut() }
                Divider()
                Button("实际大小") { viewer.actualSize() }
                Button("适合宽度") { viewer.fitWidth() }
                Button("适合整页") { viewer.fitPage() }
                Button("自动缩放") { viewer.zoomToFit() }
                Divider()
                Picker("页面布局", selection: $viewer.layout) {
                    ForEach(PageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("夜间模式", isOn: $viewer.nightMode)
            } label: {
                Label("显示", systemImage: "doc.viewfinder")
            }
            .help("缩放、页面布局与夜间模式")
            Button { viewer.zoomOut() } label: {
                Label("缩小", systemImage: "minus.magnifyingglass")
            }
            .help("缩小")
            Button { viewer.zoomIn() } label: {
                Label("放大", systemImage: "plus.magnifyingglass")
            }
            .help("放大")
        }
        ToolbarItem {
            Menu {
                Button("向左旋转") { viewer.rotate(by: -90) }
                Button("向右旋转") { viewer.rotate(by: 90) }
                Divider()
                Button("插入空白页") { viewer.insertBlankPage() }
                Button("复制页面（本页副本）") { viewer.duplicatePages() }
                Button("拷贝页面到剪贴板") { viewer.copyPagesToClipboard() }
                Button("粘贴页面") { viewer.pastePagesFromClipboard() }
                Button("从文件插入页面…") { viewer.insertPagesFromFile() }
                Button("合并到当前文档…") { viewer.mergePDFsIntoCurrentDocument() }
                Divider()
                Button("提取为新 PDF…") { viewer.extractPages() }
                Button("导出 PDF…") { viewer.exportPDFInteractive() }
                Button("导出为 PNG…") { viewer.exportImagesInteractive(format: .png) }
                Button("导出为 JPEG…") { viewer.exportImagesInteractive(format: .jpeg) }
                Divider()
                Button("删除页面", role: .destructive) { deleteSelectedOrCurrentPage() }
                    .disabled(document.pdf.pageCount <= 1)
            } label: {
                Label("页面", systemImage: "doc.on.doc")
            }
            .help("页面操作：作用于侧栏选中的页面，未选中时作用于当前页")
        }
        ToolbarItem {
            SearchField(viewer: viewer)
        }
    }

    private func deleteSelectedOrCurrentPage() {
        if !viewer.selection.isEmpty {
            deletePages(viewer.selection)
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
        viewer.selection.subtract(ids)
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

/// "12 / 30" in the toolbar; click to jump to a page.
private struct PageIndicator: View {
    @ObservedObject var viewer: ViewerState

    var body: some View {
        Button {
            viewer.showGoToPage = true
        } label: {
            Text(viewer.pageCount > 0 ? "\(viewer.currentPageIndex + 1) / \(viewer.pageCount)" : "–")
                .monospacedDigit()
                .frame(minWidth: 64)
        }
        .help("前往页面（⌥⌘G）")
    }
}

/// Toolbar search field with match counter and previous / next buttons.
private struct SearchField: View {
    @ObservedObject var viewer: ViewerState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $viewer.searchText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { viewer.performSearch() }
                    .onExitCommand {
                        viewer.searchText = ""
                        viewer.clearSearch()
                    }
                if !viewer.searchResults.isEmpty {
                    Text("\((viewer.currentSearchIndex ?? 0) + 1)/\(viewer.searchResults.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !viewer.searchText.isEmpty {
                    Button {
                        viewer.searchText = ""
                        viewer.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: 210)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )

            Button { viewer.findPrevious() } label: {
                Image(systemName: "chevron.up")
            }
            .help("上一个（⇧⌘G）")
            .disabled(viewer.searchResults.isEmpty)
            Button { viewer.findNext() } label: {
                Image(systemName: "chevron.down")
            }
            .help("下一个（⌘G）")
            .disabled(viewer.searchResults.isEmpty)
        }
        .onChange(of: viewer.searchFocusRequest) { _ in
            // Toolbar TextFields often ignore the first focus flip; retry next runloop.
            focused = true
            DispatchQueue.main.async {
                focused = true
            }
        }
    }
}

/// Asks for the password of an encrypted PDF.
private struct UnlockView: View {
    @ObservedObject var document: PDFFileDocument
    @State private var password = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("此 PDF 受密码保护")
                .font(.headline)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(unlock)
            if failed {
                Text("密码不正确，请重试。")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Button("解锁", action: unlock)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        failed = !document.unlock(with: password)
        if !failed { password = "" }
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
