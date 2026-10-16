import AppKit

/// Configures native macOS window tabbing for PDF document windows.
///
/// Multiple PDFs then appear as tabs in one window (same `tabbingIdentifier`).
/// ⌘W closes the current tab; closing the last tab closes the window but does
/// not quit the app (`applicationShouldTerminateAfterLastWindowClosed` → false).
enum WindowTabbing {
    static let documentTabbingIdentifier = "io.github.bianyanhui.iReader.documents"

    static func enable() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    /// Applies tabbing settings to every open document window.
    static func configureOpenWindows() {
        for window in NSApp.windows {
            configureIfDocumentWindow(window)
        }
    }

    static func configureIfDocumentWindow(_ window: NSWindow) {
        guard isDocumentWindow(window) else { return }

        if window.tabbingIdentifier != documentTabbingIdentifier {
            window.tabbingIdentifier = documentTabbingIdentifier
        }

        let preferTabs = UserDefaults.standard.object(forKey: Prefs.preferTabsWhenOpening) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Prefs.preferTabsWhenOpening)
        let mode: NSWindow.TabbingMode = preferTabs ? .preferred : .automatic
        if window.tabbingMode != mode {
            window.tabbingMode = mode
        }
    }

    /// Document windows from `DocumentGroup` / `NSDocument`, excluding Settings,
    /// shortcut help, panels and alerts.
    static func isDocumentWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        if window.styleMask.contains(.docModal) { return false }
        if !window.styleMask.contains(.titled) { return false }

        let title = window.title
        if title == "键盘快捷键" || title == "Settings" || title == "设置" || title.hasPrefix("偏好") {
            return false
        }
        if let id = window.identifier?.rawValue {
            let lower = id.lowercased()
            if lower.contains("settings") || lower.contains("shortcut") || lower.contains("preference") {
                return false
            }
        }

        if window.windowController?.document != nil {
            return true
        }

        // SwiftUI DocumentGroup windows still use an NSWindowController; the
        // concrete class name varies by OS / SDK, so accept “Document” and the
        // usual editor chrome as fallbacks.
        if let controller = window.windowController {
            let name = String(describing: type(of: controller))
            if name.contains("Document") || name.contains("SwiftUI") {
                // Avoid folding Settings into the PDF tab group: Settings is rarely resizable the same way.
                if window.styleMask.contains(.resizable) && window.styleMask.contains(.closable) {
                    return true
                }
            }
        }

        return window.styleMask.contains(.closable)
            && window.styleMask.contains(.resizable)
            && !(window is NSPanel)
    }
}
