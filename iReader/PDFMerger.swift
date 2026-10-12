import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Dedicated PDF merge flows: into the open document, or into a brand-new file.
enum PDFMerger {
    // MARK: - Load helpers

    struct LoadResult {
        var pages: [PDFPage] = []
        var sources: [PDFDocument] = []
        var skipped: [String] = []
        var pageCounts: [URL: Int] = [:]
    }

    /// Loads every page of each URL. Password-protected files prompt once.
    @MainActor
    static func loadPages(from urls: [URL], passwordPromptVerb: String = "合并") -> LoadResult {
        var result = LoadResult()
        for url in urls {
            guard let source = PDFDocument(url: url) else {
                result.skipped.append(url.lastPathComponent)
                continue
            }
            if source.isLocked {
                guard unlock(source, name: url.lastPathComponent, verb: passwordPromptVerb) else {
                    result.skipped.append(url.lastPathComponent)
                    continue
                }
            }
            let count = source.pageCount
            guard count > 0 else {
                result.skipped.append(url.lastPathComponent)
                continue
            }
            result.sources.append(source)
            result.pageCounts[url] = count
            result.pages.append(contentsOf: (0..<count).compactMap { source.page(at: $0) })
        }
        return result
    }

    @MainActor
    private static func unlock(_ source: PDFDocument, name: String, verb: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "「\(name)」受密码保护"
        alert.informativeText = "输入密码以\(verb)其页面。"
        alert.addButton(withTitle: "解锁")
        alert.addButton(withTitle: "跳过")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return source.unlock(withPassword: field.stringValue)
    }

    // MARK: - Merge into a new document (File → 合并 PDF…)

    /// Picks several PDFs, lets the user reorder them, writes a new file and opens it.
    @MainActor
    static func mergeIntoNewDocument() {
        let open = NSOpenPanel()
        open.title = "选择要合并的 PDF"
        open.message = "按住 ⌘ 可多选。合并后可在下一步调整顺序。"
        open.prompt = "选择"
        open.allowedContentTypes = [.pdf]
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        guard open.runModal() == .OK else { return }
        let picked = open.urls
        guard picked.count >= 2 else {
            let alert = NSAlert()
            alert.messageText = "请至少选择两个 PDF 文件"
            alert.informativeText = "「合并 PDF」会把多个文件按顺序合成一个新文档。若只想把文件插入当前文档，请使用「页面 > 合并到当前文档…」。"
            alert.runModal()
            return
        }

        guard let ordered = presentOrderEditor(urls: picked) else { return }

        let loaded = loadPages(from: ordered)
        guard !loaded.pages.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "没有可合并的页面"
            alert.informativeText = loaded.skipped.isEmpty
                ? "所选文件都无法读取。"
                : "以下文件未能读取：\n" + loaded.skipped.joined(separator: "\n")
            alert.runModal()
            return
        }

        let output = PDFDocument()
        for (index, page) in loaded.pages.enumerated() {
            // Copy so the output does not share page objects with the source files.
            if let copy = page.copy() as? PDFPage {
                output.insert(copy, at: index)
            } else {
                output.insert(page, at: index)
            }
        }

        let save = NSSavePanel()
        save.title = "保存合并后的 PDF"
        save.allowedContentTypes = [.pdf]
        let stem = ordered.first?.deletingPathExtension().lastPathComponent ?? "合并"
        save.nameFieldStringValue = "\(stem)-合并.pdf"
        guard save.runModal() == .OK, let url = save.url else { return }

        guard output.write(to: url) else {
            let alert = NSAlert()
            alert.messageText = "无法写入文件"
            alert.informativeText = url.path
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        if !loaded.skipped.isEmpty {
            let alert = NSAlert()
            alert.messageText = "部分文件未能合并"
            alert.informativeText = loaded.skipped.joined(separator: "\n") + "\n\n其余页面已写入新文件。"
            alert.runModal()
        }

        // Pages were copied into `output`, so source documents can be released.
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    // MARK: - Order editor

    /// Modal window that lets the user reorder the chosen files. Returns nil if cancelled.
    @MainActor
    static func presentOrderEditor(urls: [URL]) -> [URL]? {
        var result: [URL]?
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "合并 PDF — 调整顺序"
        panel.isFloatingPanel = true
        panel.level = .modalPanel

        let closer = WindowCloseStopper()
        panel.delegate = closer

        let root = MergeOrderView(
            urls: urls,
            onConfirm: { ordered in
                result = ordered
                NSApp.stopModal(withCode: .OK)
                panel.close()
            },
            onCancel: {
                result = nil
                NSApp.stopModal(withCode: .cancel)
                panel.close()
            }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.center()
        let code = NSApp.runModal(for: panel)
        // Keep `closer` alive for the duration of the modal session.
        _ = closer
        return code == .OK ? result : nil
    }
}

/// Stops a modal session when the user clicks the window's close button.
private final class WindowCloseStopper: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if NSApp.modalWindow === sender {
            NSApp.stopModal(withCode: .cancel)
        }
        return true
    }
}

/// Where to place merged pages inside the open document.
enum MergePlacement: String, CaseIterable, Identifiable {
    case append
    case afterSelection
    case beginning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .append: return "追加到末尾"
        case .afterSelection: return "插入到选中页之后"
        case .beginning: return "插入到开头"
        }
    }

    var help: String {
        switch self {
        case .append: return "把所选 PDF 的全部页面加到文档最后"
        case .afterSelection: return "插在侧栏选中页（或当前页）的后面"
        case .beginning: return "插在文档最前面"
        }
    }
}

// MARK: - Into the current document

extension ViewerState {
    /// Dedicated merge into the open document: pick files, choose placement, insert (undoable).
    func mergePDFsIntoCurrentDocument() {
        guard let document, !document.isLocked else { return }

        let open = NSOpenPanel()
        open.title = "选择要合并进来的 PDF"
        open.message = "按住 ⌘ 可多选。页面会按文件顺序插入当前文档。"
        open.prompt = "合并"
        open.allowedContentTypes = [.pdf]
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }

        guard let placement = Self.askMergePlacement(hasSelection: !selection.isEmpty || currentPage != nil) else {
            return
        }

        let index: Int
        switch placement {
        case .append:
            index = document.pdf.pageCount
        case .beginning:
            index = 0
        case .afterSelection:
            index = insertionIndexAfterTargets
        }

        // Prefer the order chosen in the open panel (Finder selection order).
        // If the user picked several files, offer reorder when there are 2+.
        let urls: [URL]
        if open.urls.count >= 2, let ordered = PDFMerger.presentOrderEditor(urls: open.urls) {
            urls = ordered
        } else if open.urls.count >= 2 {
            return // cancelled reorder
        } else {
            urls = open.urls
        }

        let loaded = PDFMerger.loadPages(from: urls)
        for source in loaded.sources {
            document.retainSource(source)
        }
        if !loaded.pages.isEmpty {
            document.insert(loaded.pages, at: index, actionName: "合并 PDF", undoManager: undoManager)
            selection = Set(loaded.pages.map(\.pageID))
            if let first = loaded.pages.first {
                go(to: first)
            }
        }
        if !loaded.skipped.isEmpty {
            let alert = NSAlert()
            alert.messageText = loaded.pages.isEmpty ? "没有可合并的页面" : "部分文件未能合并"
            alert.informativeText = loaded.skipped.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// Asks where to put the merged pages. Returns nil if cancelled.
    private static func askMergePlacement(hasSelection: Bool) -> MergePlacement? {
        let alert = NSAlert()
        alert.messageText = "合并到当前文档的何处？"
        alert.informativeText = "合并可以撤销（⌘Z）。"

        // Build buttons in a stable order and map the modal response back.
        var options: [MergePlacement] = [.append]
        if hasSelection { options.append(.afterSelection) }
        options.append(.beginning)

        for option in options {
            alert.addButton(withTitle: option.title)
        }
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        // NSAlertFirstButtonReturn == 1000, then 1001, 1002, …
        let index = Int(response.rawValue) - Int(NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        guard index >= 0, index < options.count else { return nil }
        return options[index]
    }
}


/// Modal list for reordering PDFs before merging.
struct MergeOrderView: View {
    @State private var urls: [URL]
    let onConfirm: ([URL]) -> Void
    let onCancel: () -> Void

    init(urls: [URL], onConfirm: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
        _urls = State(initialValue: urls)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("拖动调整合并顺序（从上到下）")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            List {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    urls.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)

            HStack {
                Text("共 \(urls.count) 个文件")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("合并…") { onConfirm(urls) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(urls.count < 2)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 380)
    }
}
