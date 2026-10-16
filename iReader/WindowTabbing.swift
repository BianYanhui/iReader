import AppKit
import ObjectiveC.runtime

/// Reliable multi-PDF tabs for SwiftUI `DocumentGroup` windows.
///
/// AppKit only auto-tabs windows that already share a `tabbingIdentifier`
/// *before* they are ordered front. Configuring after `didBecomeKey` (v1.4.0)
/// was too late, so documents opened as separate windows. This version:
/// 1. Swizzles `makeKeyAndOrderFront:` / `orderFront:` to stamp the identifier first
/// 2. Explicitly calls `addTabbedWindow(_:ordered:)` so a newly opened PDF joins
///    the existing document window's tab group when the setting is on
enum WindowTabbing {
    static let documentTabbingIdentifier = "io.github.bianyanhui.iReader.documents"

    private static var didInstall = false
    /// Re-entrancy guard while we call `addTabbedWindow` / `makeKeyAndOrderFront`.
    private static var isMerging = false

    static var preferTabs: Bool {
        if UserDefaults.standard.object(forKey: Prefs.preferTabsWhenOpening) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Prefs.preferTabsWhenOpening)
    }

    static func enable() {
        NSWindow.allowsAutomaticWindowTabbing = true
        installSwizzlesIfNeeded()
    }

    static func configureOpenWindows() {
        for window in NSApp.windows {
            configureIfDocumentWindow(window)
        }
        // After stamping identifiers, merge stray document windows into one tab group.
        if preferTabs {
            mergeDocumentWindowsIntoTabs()
        }
    }

    static func configureIfDocumentWindow(_ window: NSWindow) {
        guard isDocumentWindow(window) else { return }
        prepareForTabbing(window)
    }

    /// Sets identifier + mode. Must run before the window is ordered front when possible.
    static func prepareForTabbing(_ window: NSWindow) {
        window.tabbingIdentifier = documentTabbingIdentifier
        window.tabbingMode = preferTabs ? .preferred : .automatic
    }

    // MARK: - Force merge

    /// If several document windows are visible as separate windows, fold them into tabs.
    static func mergeDocumentWindowsIntoTabs() {
        guard preferTabs, !isMerging else { return }
        let docs = NSApp.windows.filter { isDocumentWindow($0) && $0.isVisible && !$0.isMiniaturized }
        guard docs.count >= 2 else { return }

        // Prefer an existing tab group host, else the key document window, else the first.
        let host = docs.first(where: { ($0.tabGroup?.windows.count ?? 0) > 1 })
            ?? docs.first(where: \.isKeyWindow)
            ?? docs.first(where: \.isMainWindow)
            ?? docs[0]

        prepareForTabbing(host)

        for window in docs where window !== host {
            prepareForTabbing(window)
            if let group = host.tabGroup, group.windows.contains(where: { $0 === window }) {
                continue
            }
            if window.tabGroup != nil && window.tabGroup === host.tabGroup {
                continue
            }
            isMerging = true
            host.addTabbedWindow(window, ordered: .above)
            isMerging = false
        }
    }

    /// Called right after a document window is shown: attach it as a tab of an existing host.
    static func attachNewDocumentWindowIfNeeded(_ window: NSWindow) {
        guard preferTabs, isDocumentWindow(window), !isMerging else { return }
        prepareForTabbing(window)

        let others = NSApp.windows.filter {
            $0 !== window && isDocumentWindow($0) && $0.isVisible && !$0.isMiniaturized
        }
        guard let host = others.first(where: { ($0.tabGroup?.windows.count ?? 0) >= 1 })
                ?? others.first(where: \.isKeyWindow)
                ?? others.first
        else { return }

        if let group = host.tabGroup, group.windows.contains(where: { $0 === window }) {
            return
        }

        prepareForTabbing(host)
        isMerging = true
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        isMerging = false
    }

    // MARK: - Classification

    static func isDocumentWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        if !window.styleMask.contains(.titled) { return false }
        if !window.styleMask.contains(.closable) { return false }

        let title = window.title
        let blockedTitles = ["键盘快捷键", "Settings", "设置", "Preferences", "General", "通用"]
        if blockedTitles.contains(title) || title.hasPrefix("偏好") {
            return false
        }
        if let id = window.identifier?.rawValue.lowercased() {
            if id.contains("settings") || id.contains("shortcut") || id.contains("preference") {
                return false
            }
        }

        if window.windowController?.document != nil {
            return true
        }

        // SwiftUI DocumentGroup windows are resizable editor windows.
        if window.styleMask.contains(.resizable) {
            // Exclude tiny utility-sized windows (shortcuts help is content-sized).
            if window.frame.width >= 500 && window.frame.height >= 360 {
                return true
            }
        }
        return false
    }

    // MARK: - Swizzling (stamp identifier before order-front)

    private static func installSwizzlesIfNeeded() {
        guard !didInstall else { return }
        didInstall = true
        swizzle(#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.ireader_makeKeyAndOrderFront(_:)))
        swizzle(#selector(NSWindow.orderFront(_:)), #selector(NSWindow.ireader_orderFront(_:)))
    }

    private static func swizzle(_ original: Selector, _ replacement: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(NSWindow.self, original),
            let swizzledMethod = class_getInstanceMethod(NSWindow.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension NSWindow {
    @objc func ireader_makeKeyAndOrderFront(_ sender: Any?) {
        if WindowTabbing.isDocumentWindow(self) {
            WindowTabbing.prepareForTabbing(self)
        }
        // Calls the original implementation (exchanged).
        self.ireader_makeKeyAndOrderFront(sender)
        if WindowTabbing.isDocumentWindow(self) {
            DispatchQueue.main.async {
                WindowTabbing.attachNewDocumentWindowIfNeeded(self)
            }
        }
    }

    @objc func ireader_orderFront(_ sender: Any?) {
        if WindowTabbing.isDocumentWindow(self) {
            WindowTabbing.prepareForTabbing(self)
        }
        self.ireader_orderFront(sender)
        if WindowTabbing.isDocumentWindow(self) {
            DispatchQueue.main.async {
                WindowTabbing.attachNewDocumentWindowIfNeeded(self)
            }
        }
    }
}
