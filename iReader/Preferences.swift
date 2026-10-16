import Foundation
import PDFKit

/// UserDefaults keys shared by the settings window and the viewer.
enum Prefs {
    static let defaultLayout = "pref.defaultLayout"
    static let defaultColor = "pref.defaultColor"
    static let rememberPosition = "pref.rememberPosition"
    static let nightMode = "pref.nightMode"
    static let preferTabsWhenOpening = "pref.preferTabsWhenOpening"
    static let positions = "pref.positions"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultLayout: PageLayout.singleContinuous.rawValue,
            defaultColor: AnnotationColor.yellow.rawValue,
            rememberPosition: true,
            nightMode: false,
            preferTabsWhenOpening: true,
        ])
    }
}

/// Page layouts offered in the View menu.
enum PageLayout: String, CaseIterable, Identifiable {
    case single
    case singleContinuous
    case twoUp
    case twoUpContinuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "单页"
        case .singleContinuous: return "单页连续"
        case .twoUp: return "双页"
        case .twoUpContinuous: return "双页连续"
        }
    }

    var displayMode: PDFDisplayMode {
        switch self {
        case .single: return .singlePage
        case .singleContinuous: return .singlePageContinuous
        case .twoUp: return .twoUp
        case .twoUpContinuous: return .twoUpContinuous
        }
    }

    var isTwoUp: Bool { self == .twoUp || self == .twoUpContinuous }
}

/// Remembers the last page and zoom for each file (by path).
enum PositionStore {
    struct Position {
        var pageIndex: Int
        /// 0 means "auto scale".
        var scale: Double
    }

    private static let maxEntries = 300

    static func load(for url: URL) -> Position? {
        guard let all = UserDefaults.standard.dictionary(forKey: Prefs.positions),
              let entry = all[url.path] as? [String: Any],
              let page = entry["page"] as? Int else { return nil }
        let scale = entry["scale"] as? Double ?? 0
        return Position(pageIndex: page, scale: scale)
    }

    static func save(_ position: Position, for url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: Prefs.positions) ?? [:]
        all[url.path] = [
            "page": position.pageIndex,
            "scale": position.scale,
            "time": Date().timeIntervalSince1970,
        ]
        if all.count > maxEntries {
            // Drop the oldest entries.
            let sorted = all.sorted {
                (($0.value as? [String: Any])?["time"] as? Double ?? 0)
                    < (($1.value as? [String: Any])?["time"] as? Double ?? 0)
            }
            for (key, _) in sorted.prefix(all.count - maxEntries) {
                all.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(all, forKey: Prefs.positions)
    }
}
