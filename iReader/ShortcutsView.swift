import SwiftUI

/// Help > 键盘快捷键.
struct ShortcutsView: View {
    static let windowID = "shortcuts"

    private struct Item: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private struct ShortcutSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }

    private let sections: [ShortcutSection] = [
        ShortcutSection(title: "文件", items: [
            Item(keys: "⌘O", action: "打开"),
            Item(keys: "⌘S", action: "保存"),
            Item(keys: "⌥⇧⌘S", action: "另存为"),
            Item(keys: "⌘P", action: "打印"),
        ]),
        ShortcutSection(title: "查找与导航", items: [
            Item(keys: "⌘F", action: "搜索（输入后回车）"),
            Item(keys: "⌘G / ⇧⌘G", action: "下一个 / 上一个结果"),
            Item(keys: "⌥⌘G", action: "前往页面"),
            Item(keys: "⌥⌘↓ / ⌥⌘↑", action: "下一页 / 上一页"),
            Item(keys: "⌥⇧⌘↑ / ⌥⇧⌘↓", action: "第一页 / 最后一页"),
            Item(keys: "⌥⌘1 – ⌥⌘4", action: "侧栏：缩略图 / 目录 / 标注 / 搜索结果"),
        ]),
        ShortcutSection(title: "显示", items: [
            Item(keys: "⌘= / ⌘-", action: "放大 / 缩小"),
            Item(keys: "⌘0", action: "实际大小"),
            Item(keys: "⌘9", action: "自动缩放"),
            Item(keys: "⌘8", action: "适合宽度"),
            Item(keys: "⌘7", action: "适合整页"),
            Item(keys: "⌥⌘N", action: "夜间模式"),
            Item(keys: "⌃⌘F", action: "全屏"),
        ]),
        ShortcutSection(title: "页面", items: [
            Item(keys: "⌘L / ⌘R", action: "向左 / 向右旋转"),
            Item(keys: "⌥⌘B", action: "插入空白页"),
            Item(keys: "⌥⌘D", action: "复制页面"),
            Item(keys: "⌥⌘I", action: "从文件插入页面"),
            Item(keys: "⌥⌘E", action: "提取为新 PDF"),
            Item(keys: "⌥⇧⌘E", action: "导出为 PNG"),
            Item(keys: "⌫（侧栏）/ ⌥⌘⌫", action: "删除页面"),
        ]),
        ShortcutSection(title: "标注", items: [
            Item(keys: "⌘1 – ⌘9", action: "选择 / 高亮 / 下划线 / 删除线 / 画笔 / 矩形 / 箭头 / 文本框 / 橡皮擦"),
            Item(keys: "右键标注", action: "改颜色、编辑文字、拷贝、删除"),
            Item(keys: "⌘Z / ⇧⌘Z", action: "撤销 / 重做"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            ForEach(section.items) { item in
                                GridRow {
                                    Text(item.keys)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(minWidth: 150, alignment: .leading)
                                    Text(item.action)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 560)
    }
}
