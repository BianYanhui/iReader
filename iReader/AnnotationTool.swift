import AppKit
import PDFKit
import SwiftUI

/// The active tool of a document window.
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case highlight
    case underline
    case strikethrough
    case pen
    case rectangle
    case arrow
    case text
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "选择"
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .pen: return "画笔"
        case .rectangle: return "矩形"
        case .arrow: return "箭头"
        case .text: return "文本框"
        case .eraser: return "橡皮擦"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "character.textbox"
        case .eraser: return "eraser"
        }
    }

    var help: String {
        switch self {
        case .select: return "选择文本、点击链接；右键标注可改颜色或删除"
        case .highlight: return "拖动选择文字以添加高亮"
        case .underline: return "拖动选择文字以添加下划线"
        case .strikethrough: return "拖动选择文字以添加删除线"
        case .pen: return "在页面上自由绘制"
        case .rectangle: return "拖动画出矩形框"
        case .arrow: return "拖动画出箭头"
        case .text: return "点击页面添加文本框（批注）"
        case .eraser: return "点击标注将其删除"
        }
    }

    /// Tools that turn a text selection into markup.
    var isTextMarkup: Bool {
        self == .highlight || self == .underline || self == .strikethrough
    }

    /// Tools that draw by dragging.
    var isShape: Bool {
        self == .rectangle || self == .arrow
    }
}

extension PDFAnnotation {
    /// Subtypes created or editable by iReader (not links / form widgets).
    static let userMarkupTypes: Set<String> = [
        "highlight", "underline", "strikeout", "squiggly", "ink",
        "freetext", "text", "square", "circle", "line",
    ]

    /// Lower-case subtype without a leading slash, e.g. "highlight".
    var normalizedType: String {
        (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    var isUserMarkup: Bool { Self.userMarkupTypes.contains(normalizedType) }

    var kindTitle: String {
        switch normalizedType {
        case "highlight": return "高亮"
        case "underline": return "下划线"
        case "strikeout": return "删除线"
        case "squiggly": return "波浪线"
        case "ink": return "画笔"
        case "freetext": return "文本框"
        case "text": return "便签"
        case "square": return "矩形"
        case "circle": return "椭圆"
        case "line": return "箭头 / 线条"
        default: return "标注"
        }
    }

    var kindSymbol: String {
        switch normalizedType {
        case "highlight": return "highlighter"
        case "underline": return "underline"
        case "strikeout": return "strikethrough"
        case "squiggly": return "scribble"
        case "ink": return "pencil.tip"
        case "freetext": return "character.textbox"
        case "text": return "note.text"
        case "square": return "rectangle"
        case "circle": return "circle"
        case "line": return "arrow.up.right"
        default: return "pencil"
        }
    }

    /// Whether the annotation has user-editable text.
    var hasEditableText: Bool {
        normalizedType == "freetext" || normalizedType == "text"
    }

    /// The color to store for a palette color, matching how iReader creates
    /// each kind (translucent highlights / text box backgrounds).
    func storedColor(for base: NSColor) -> NSColor {
        switch normalizedType {
        case "highlight": return base.withAlphaComponent(0.5)
        case "freetext": return base.withAlphaComponent(0.35)
        default: return base
        }
    }
}

/// The small fixed palette offered in the toolbar.
enum AnnotationColor: String, CaseIterable, Identifiable {
    case yellow, green, blue, pink, red, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .pink: return "粉色"
        case .red: return "红色"
        case .black: return "黑色"
        }
    }

    /// Fixed sRGB colors, so that saved annotations look the same everywhere.
    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.85, blue: 0.10, alpha: 1)
        case .green: return NSColor(srgbRed: 0.30, green: 0.80, blue: 0.35, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.20, green: 0.55, blue: 1.00, alpha: 1)
        case .pink: return NSColor(srgbRed: 1.00, green: 0.45, blue: 0.70, alpha: 1)
        case .red: return NSColor(srgbRed: 0.90, green: 0.15, blue: 0.15, alpha: 1)
        case .black: return NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        }
    }

    /// A non-template swatch image, so the toolbar shows the real color.
    func swatch(selected: Bool) -> NSImage {
        let color = nsColor
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let dot = rect.insetBy(dx: 3.5, dy: 3.5)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let outline = NSBezierPath(ovalIn: dot)
            outline.lineWidth = 0.5
            outline.stroke()
            if selected {
                NSColor.controlAccentColor.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Row of color swatches for the toolbar.
struct ColorSwatchPicker: View {
    @Binding var selection: AnnotationColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Image(nsImage: color.swatch(selected: color == selection))
                }
                .buttonStyle(.borderless)
                .help(color.title)
            }
        }
    }
}
