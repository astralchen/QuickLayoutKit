import Foundation

/// 本地 Demo 的送达边界。返回成功仅代表模拟收件端确认，不等于真实网络或 Apple 回执。
@MainActor
protocol IMessageChatMessageSending: AnyObject {
    func send(_ message: IMessageChatMessage) async throws
}

@MainActor
final class IMessageChatSimulatedMessageSender: IMessageChatMessageSending {
    private var failsNextSend: Bool

    init(failsNextSend: Bool = false) {
        self.failsNextSend = failsNextSend
    }

    static func liveDemo() -> IMessageChatSimulatedMessageSender {
        #if DEBUG
        return .init(failsNextSend: ProcessInfo.processInfo.arguments.contains("-imessage-fail-first-send"))
        #else
        return .init()
        #endif
    }

    func send(_ message: IMessageChatMessage) async throws {
        // 在挂起之前消耗故障开关，批量发送时仅使第一条失败。
        let fails = failsNextSend
        failsNextSend = false
        try await Task.sleep(for: .milliseconds(250))
        if fails { throw CocoaError(.fileWriteUnknown) }
        if case .attachment(let attachment) = message.content,
           !attachment.localFileURLs.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) {
            throw CocoaError(.fileReadNoSuchFile)
        }
    }
}
