import SwiftUI

/// Menu bar commands that act on the focused document window.
struct ViewerCommands: Commands {
    @FocusedObject private var viewer: ViewerState?

    var body: some Commands {
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
    }
}
