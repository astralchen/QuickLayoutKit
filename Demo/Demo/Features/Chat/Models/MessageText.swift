import Foundation

/// 消息只保存语义格式；字号、颜色随气泡方向与 Dynamic Type 在展示时生成。
nonisolated struct MessageText: Equatable, Hashable, Sendable {
    nonisolated struct Style: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let bold = Style(rawValue: 1 << 0)
        static let italic = Style(rawValue: 1 << 1)
        static let underline = Style(rawValue: 1 << 2)
        static let strikethrough = Style(rawValue: 1 << 3)
    }

    nonisolated struct Run: Equatable, Hashable, Sendable {
        var text: String
        let style: Style

        init(_ text: String, style: Style = []) {
            self.text = text
            self.style = style
        }
    }

    let runs: [Run]

    /// 合并相邻同格式片段，使刷新身份不受 TextKit 的临时属性分段影响。
    init(runs: [Run]) {
        var normalized: [Run] = []
        for run in runs where !run.text.isEmpty {
            if normalized.last?.style == run.style {
                normalized[normalized.count - 1].text += run.text
            } else {
                normalized.append(run)
            }
        }
        self.runs = normalized
    }

    var text: String { runs.map(\.text).joined() }
    var hasFormatting: Bool { runs.contains { !$0.style.isEmpty } }
}
