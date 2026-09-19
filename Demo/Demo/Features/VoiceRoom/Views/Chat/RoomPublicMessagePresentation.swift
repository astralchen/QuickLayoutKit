import AppLocalization
import UIKit

/// 将业务内容映射为当前语言的独立语义片段；不解析已拼好的昵称或消息字符串。
struct RoomPublicMessagePresentation: Identifiable, Hashable, Sendable {
    enum Style: Hashable, Sendable { case text, system, arrival, gift }
    struct Run: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case body, name, accent }
        let text: String
        let kind: Kind
    }

    let id: String
    let style: Style
    let badge: String?
    let symbolName: String?
    let runs: [Run]
    let accessibilityText: String
    var text: String { runs.map(\.text).joined() }

    @MainActor
    init(message: RoomPublicMessage) {
        id = message.id
        var author: RoomPublicMessage.Author?
        switch message.content {
        case let .text(sender, body):
            style = .text
            author = sender
            symbolName = nil
            runs = [Run(text: sender.name.localized + Localization.text("liveRoom.publicChat.colon"), kind: .name),
                    Run(text: body.localized, kind: .body)]
        case let .system(body):
            style = .system
            symbolName = "info.circle.fill"
            runs = [Run(text: body.localized, kind: .body)]
        case let .arrival(sender):
            style = .arrival
            author = sender
            symbolName = "sparkles"
            runs = Self.formattedRuns(
                Localization.text("liveRoom.publicChat.arrival"),
                values: ["{user}": Run(text: sender.name.localized, kind: .name)]
            )
        case let .gift(sender, recipients, gift, quantity):
            style = .gift
            author = sender
            symbolName = gift.symbolName
            runs = Self.formattedRuns(
                Localization.text("liveRoom.publicChat.gift"),
                values: [
                    "{sender}": Run(text: sender.name.localized, kind: .name),
                    "{recipients}": Run(text: recipients.map { $0.name.localized }.joined(separator: Localization.text("liveRoom.gift.name.separator")), kind: .name),
                    "{gift}": Run(text: gift.localizedTitle, kind: .accent),
                    "{quantity}": Run(text: String(quantity), kind: .accent),
                ]
            )
        }
        badge = author?.role == .host ? Localization.text("liveRoom.publicChat.host") : nil
        accessibilityText = [badge, runs.map(\.text).joined()].compactMap { $0 }.joined(separator: " ")
    }

    /// 只替换翻译模板中的显式参数，保留各语言的语序及正文中的原始字符。
    private static func formattedRuns(_ template: String, values: [String: Run]) -> [Run] {
        var remaining = template[...]
        var result: [Run] = []
        while !remaining.isEmpty {
            let match = values.keys.compactMap { token in
                remaining.range(of: token).map { (token, $0) }
            }.min { $0.1.lowerBound < $1.1.lowerBound }
            guard let (token, range) = match else {
                result.append(Run(text: String(remaining), kind: .body))
                break
            }
            result.append(Run(text: String(remaining[..<range.lowerBound]), kind: .body))
            if let value = values[token] { result.append(value) }
            remaining = remaining[range.upperBound...]
        }
        return result
    }
}

extension RoomPublicMessage.Text {
    @MainActor var localized: String {
        switch self {
        case let .literal(value): value
        case let .localized(key): Localization.text(key)
        }
    }
}
