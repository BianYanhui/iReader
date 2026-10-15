import AppKit
import SwiftUI

/// Menu bar commands that act on the focused document window.
struct ViewerCommands: Commands {
    @FocusedObject private var viewer: ViewerState?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            // DocumentGroup only shows "Save As…" while Option is held;
            // offer it explicitly. NSDocument handles it via the responder chain.
            Button("另存为…") {
                NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .option, .shift])
            Divider()
            Button("合并 PDF…") {
                PDFMerger.mergeIntoNewDocument()
            }
            .keyboardShortcut("m", modifiers: [.command, .option, .shift])
            .help("选择多个 PDF，调整顺序后保存为一个新文件")
            Button("批量转换 Word 为 PDF…") {
                WordToPDFConverter.runInteractive()
            }
            .help("多选 .doc / .docx，转为 PDF（可选合并）")
            Divider()
            Menu("导出") {
                Button("导出 PDF…") { viewer?.exportPDFInteractive() }
                    .disabled(viewer == nil)
                Button("导出为 PNG…") { viewer?.exportImagesInteractive(format: .png) }
                    .disabled(viewer == nil)
                Button("导出为 JPEG…") { viewer?.exportImagesInteractive(format: .jpeg) }
                    .disabled(viewer == nil)
                Divider()
                Button("导出标注为 Markdown…") { viewer?.exportAnnotationsInteractive(asMarkdown: true) }
                    .disabled(viewer == nil)
                Button("导出标注为纯文本…") { viewer?.exportAnnotationsInteractive(asMarkdown: false) }
                    .disabled(viewer == nil)
                Button("导出目录…") { viewer?.exportOutlineInteractive() }
                    .disabled(viewer == nil)
                Button("导出摘要 JSON…") { viewer?.exportSummaryJSONInteractive() }
                    .disabled(viewer == nil)
            }
        }

        CommandGroup(replacing: .printItem) {
            Button("打印…") { viewer?.printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(viewer == nil)
        }

        CommandGroup(replacing: .textEditing) {
            Button("查找…") { viewer?.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewer == nil)
            Button("查找下一个") { viewer?.findNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(viewer == nil)
            Button("查找上一个") { viewer?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(viewer == nil)
        }

        CommandGroup(before: .toolbar) {
            Button("放大") { viewer?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(viewer == nil)
            Button("缩小") { viewer?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(viewer == nil)
            Button("实际大小") { viewer?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(viewer == nil)
            Button("缩放至适合窗口") { viewer?.zoomToFit() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(viewer == nil)
            Button("适合宽度") { viewer?.fitWidth() }
                .keyboardShortcut("8", modifiers: .command)
                .disabled(viewer == nil)
            Button("适合整页") { viewer?.fitPage() }
                .keyboardShortcut("7", modifiers: .command)
                .disabled(viewer == nil)
            Divider()
            Menu("页面布局") {
                ForEach(PageLayout.allCases) { layout in
                    Button(layout.title) { viewer?.layout = layout }
                        .disabled(viewer == nil)
                }
            }
            Button("夜间模式") { viewer?.nightMode.toggle() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Divider()
            Menu("侧栏") {
                ForEach(Array(SidebarMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.title) { viewer?.sidebarMode = mode }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                        .disabled(viewer == nil)
                }
            }
            Divider()
        }

        CommandMenu("前往") {
            Button("下一页") { viewer?.goToNextPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("上一页") { viewer?.goToPreviousPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("第一页") { viewer?.goToFirstPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option, .shift])
                .disabled(viewer == nil)
            Button("最后一页") { viewer?.goToLastPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option, .shift])
                .disabled(viewer == nil)
            Divider()
            Button("前往页面…") { viewer?.showGoToPage = true }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(viewer == nil)
        }

        CommandMenu("页面") {
            Button("向左旋转") { viewer?.rotate(by: -90) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(viewer == nil)
            Button("向右旋转") { viewer?.rotate(by: 90) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewer == nil)
            Divider()
            Button("插入空白页") { viewer?.insertBlankPage() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("复制页面（本页副本）") { viewer?.duplicatePages() }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("拷贝页面到剪贴板") { viewer?.copyPagesToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(viewer == nil)
                .help("复制选中页到跨文档剪贴板，可在另一个 PDF 窗口粘贴")
            Button("粘贴页面") { viewer?.pastePagesFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("粘贴到末尾") { viewer?.pastePagesFromClipboard(atEnd: true) }
                .disabled(viewer == nil)
            Button("从文件插入页面…") { viewer?.insertPagesFromFile() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("合并到当前文档…") { viewer?.mergePDFsIntoCurrentDocument() }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(viewer == nil)
                .help("把其他 PDF 合并进当前文档（可追加或插入，可撤销）")
            Divider()
            Button("提取为新 PDF…") { viewer?.extractPages() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(viewer == nil)
            Button("导出为 PNG…") { viewer?.exportImagesInteractive(format: .png) }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(viewer == nil)
            Divider()
            Button("删除页面") { viewer?.deleteTargetPages() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(viewer == nil)
        }

        CommandMenu("标注") {
            ForEach(Array(AnnotationTool.allCases.enumerated()), id: \.element) { index, tool in
                Button(tool.title) { viewer?.tool = tool }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(viewer == nil)
            }
        }
    }
}
