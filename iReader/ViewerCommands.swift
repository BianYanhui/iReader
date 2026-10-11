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
            Divider()
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
