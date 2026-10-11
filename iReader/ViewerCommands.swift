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

        CommandMenu("标注") {
            ForEach(Array(AnnotationTool.allCases.enumerated()), id: \.element) { index, tool in
                Button(tool.title) { viewer?.tool = tool }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(viewer == nil)
            }
        }
    }
}
