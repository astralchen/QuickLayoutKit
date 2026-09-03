//
//  IMessageChatViewModel.swift
//  Demo
//

import AppLocalization
import Foundation

@MainActor
final class IMessageChatViewModel {

    /// 描述本次发出消息应产生的模拟回复载荷。
    private enum ReplyKind {
        /// 使用现有本地化文本生成回复。
        case text

        /// 使用发送时解析的文本和区域设置生成本地音频附件。
        case synthesizedAudio(text: String, locale: Locale)
    }

    enum UpdateReason: Equatable {
        case initial
        case sentMessage
        case receivedMessage
        case localization
    }

    struct State: Equatable {
        let timeline: [IMessageChatTimelineItem]
        let isTyping: Bool
    }

    typealias Clock = @MainActor () -> Date
    typealias LocaleProvider = @MainActor () -> Locale
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias StateHandler = (State, UpdateReason) -> Void

    private static let timestampInterval: TimeInterval = 5 * 60

    private let localizer: DemoLocalizer
    private let clock: Clock
    private let localeProvider: LocaleProvider
    private let sleeper: Sleeper
    private let replyAudioSynthesizer: (any IMessageChatReplyAudioSynthesizing)?
    private var render: StateHandler?
    private var messages: [IMessageChatMessage]
    private var nextMessageID: Int
    private var pendingReplyTask: Task<Void, Never>?
    private var isTyping = false

    private(set) var state: State

    convenience init() {
        self.init(
            localizer: .live,
            clock: Date.init,
            localeProvider: {
                DemoLocalization.localizationController.currentLocale.locale
            },
            replyAudioSynthesizer: nil,
            sleeper: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    /// 创建使用指定模拟回复音频合成器的视图模型。
    ///
    /// - Parameter replyAudioSynthesizer: 为发出的音频消息生成同类型回复的对象。
    convenience init(
        replyAudioSynthesizer: any IMessageChatReplyAudioSynthesizing
    ) {
        self.init(
            localizer: .live,
            clock: Date.init,
            localeProvider: {
                DemoLocalization.localizationController.currentLocale.locale
            },
            replyAudioSynthesizer: replyAudioSynthesizer,
            sleeper: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    init(
        localizer: DemoLocalizer,
        clock: @escaping Clock,
        localeProvider: @escaping LocaleProvider = {
            DemoLocalization.localizationController.currentLocale.locale
        },
        replyAudioSynthesizer: (any IMessageChatReplyAudioSynthesizing)? = nil,
        sleeper: @escaping Sleeper
    ) {
        self.localizer = localizer
        self.clock = clock
        self.localeProvider = localeProvider
        self.replyAudioSynthesizer = replyAudioSynthesizer
        self.sleeper = sleeper

        let now = clock()
        messages = [
            IMessageChatMessage(
                id: 0,
                direction: .incoming,
                content: .localized(key: "imessage.seed.incoming.1"),
                sentAt: now.addingTimeInterval(-8 * 60),
                deliveryState: nil
            ),
            IMessageChatMessage(
                id: 1,
                direction: .outgoing,
                content: .localized(key: "imessage.seed.outgoing.1"),
                sentAt: now.addingTimeInterval(-7 * 60),
                deliveryState: .read
            ),
            IMessageChatMessage(
                id: 2,
                direction: .incoming,
                content: .localized(key: "imessage.seed.incoming.2"),
                sentAt: now.addingTimeInterval(-6 * 60),
                deliveryState: nil
            ),
        ]
        nextMessageID = 3
        state = State(timeline: [], isTyping: false)
        state = makeState()
    }

    deinit {
        pendingReplyTask?.cancel()
    }

    func bind(_ render: @escaping StateHandler) {
        self.render = render
        render(state, .initial)
    }

    /// 移除首尾空白后发送用户输入的文本。
    ///
    /// 文本内部的换行仍会作为消息内容保留。
    ///
    /// - Parameter rawText: 文本编辑器中未经处理的内容。
    /// - Returns: 成功追加非空消息时为 `true`；否则为 `false`。
    @discardableResult
    func send(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        appendOutgoing(
            content: .userText(text),
            replyKind: .text
        )
        return true
    }

    /// 通过普通发出消息生命周期发送页面附件。
    ///
    /// 当前只实现音频附件。图片和视频接入后应在附件验证方法中增加各自的文件、
    /// 尺寸、时长或缩略图约束，成功后继续共用同一条消息生命周期。
    ///
    /// - Parameter attachment: 已完成预览且仍由页面附件存储持有的附件。
    /// - Returns: 成功追加附件时为 `true`；否则为 `false`。
    @discardableResult
    func sendAttachment(_ attachment: IMessageChatAttachment) -> Bool {
        guard validates(attachment) else { return false }

        appendOutgoing(
            content: .attachment(attachment),
            replyKind: replyKind(for: attachment)
        )
        return true
    }

    /// 验证附件是否满足进入消息时间线的最低条件。
    ///
    /// - Parameter attachment: 即将发送的页面附件。
    /// - Returns: 附件文件和类型专属元数据均有效时为 `true`。
    private func validates(_ attachment: IMessageChatAttachment) -> Bool {
        switch attachment {
        case .audio(let audio):
            IMessageChatRecordingPolicy.accepts(
                duration: audio.duration,
                fileExists: FileManager.default.fileExists(
                    atPath: audio.fileURL.path
                )
            )
        }
    }

    /// 返回附件类型对应的模拟回复计划。
    ///
    /// 音频继续生成同类型回复。未来图片和视频可以在此集中选择文本回复或新的
    /// 回复计划，不应在各自的发送入口复制等待、输入中和已读流程。
    private func replyKind(
        for attachment: IMessageChatAttachment
    ) -> ReplyKind {
        switch attachment {
        case .audio:
            .synthesizedAudio(
                text: localizer.text("imessage.reply.1"),
                locale: IMessageChatSpeechConfiguration.speechLocale(
                    for: localeProvider()
                )
            )
        }
    }

    private func appendOutgoing(
        content: IMessageChatMessageContent,
        replyKind: ReplyKind
    ) {
        pendingReplyTask?.cancel()
        messages.append(
            IMessageChatMessage(
                id: nextMessageID,
                direction: .outgoing,
                content: content,
                sentAt: clock(),
                deliveryState: .delivered
            )
        )
        nextMessageID += 1
        isTyping = true
        publish(reason: .sentMessage)
        scheduleReply(replyKind)
    }

    func refreshLocalizedContent() {
        publish(reason: .localization)
    }

    func cancelPendingReply() {
        pendingReplyTask?.cancel()
        pendingReplyTask = nil
        guard isTyping else { return }
        isTyping = false
        publish(reason: .localization)
    }

    /// 安排与发出消息类型一致的模拟回复。
    ///
    /// 文本回复只等待最短展示时间。音频回复会同时开始本地语音合成，并在最短
    /// 展示时间和合成都结束后进入时间线；合成失败时回退为相同资源键的文本。
    ///
    /// - Parameter replyKind: 本次发出消息所决定的回复类型。
    private func scheduleReply(_ replyKind: ReplyKind) {
        let sleeper = sleeper
        let replyAudioSynthesizer = replyAudioSynthesizer
        pendingReplyTask = Task { [weak self] in
            switch replyKind {
            case .text:
                do {
                    try await sleeper(.milliseconds(900))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.completeReply(content: .localized(key: "imessage.reply.1"))

            case .synthesizedAudio(let text, let locale):
                guard let replyAudioSynthesizer else {
                    do {
                        try await sleeper(.milliseconds(900))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let self else { return }
                    self.completeReply(
                        content: .localized(key: "imessage.reply.1")
                    )
                    return
                }

                async let generatedAttachment = replyAudioSynthesizer
                    .synthesizeReplyAudio(text: text, locale: locale)
                do {
                    try await sleeper(.milliseconds(900))
                } catch {
                    return
                }

                let replyContent: IMessageChatMessageContent
                do {
                    replyContent = .attachment(
                        .audio(try await generatedAttachment)
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    replyContent = .localized(key: "imessage.reply.1")
                }
                guard !Task.isCancelled, let self else { return }
                self.completeReply(content: replyContent)
            }
        }
    }

    /// 完成模拟回复并更新最新发出消息的已读状态。
    ///
    /// - Parameter content: 已生成的文本或音频回复载荷。
    private func completeReply(content: IMessageChatMessageContent) {
        pendingReplyTask = nil
        if let latestOutgoingIndex = messages.lastIndex(where: {
            $0.direction == .outgoing
        }) {
            messages[latestOutgoingIndex].deliveryState = .read
        }
        messages.append(
            IMessageChatMessage(
                id: nextMessageID,
                direction: .incoming,
                content: content,
                sentAt: clock(),
                deliveryState: nil
            )
        )
        nextMessageID += 1
        isTyping = false
        publish(reason: .receivedMessage)
    }

    private func publish(reason: UpdateReason) {
        state = makeState()
        render?(state, reason)
    }

    private func makeState() -> State {
        var timeline: [IMessageChatTimelineItem] = []
        var previousDate: Date?
        let latestOutgoingID = messages.last(where: {
            $0.direction == .outgoing
        })?.id

        for message in messages {
            if previousDate == nil
                || message.sentAt.timeIntervalSince(previousDate!)
                    >= Self.timestampInterval {
                let timestamp = IMessageChatTimestampPresentation(
                    sourceMessageID: message.id,
                    text: Self.timestampText(
                        for: message.sentAt,
                        locale: DemoLocalization.localizationController
                            .currentLocale.locale
                    )
                )
                timeline.append(
                    IMessageChatTimelineItem(
                        id: .timestamp(sourceMessageID: message.id),
                        content: .timestamp(timestamp)
                    )
                )
            }

            let deliveryText: String?
            if message.id == latestOutgoingID,
               let deliveryState = message.deliveryState {
                deliveryText = localizer.text(
                    deliveryState == .read
                        ? "imessage.status.read"
                        : "imessage.status.delivered"
                )
            } else {
                deliveryText = nil
            }

            let presentation: IMessageChatMessagePresentation
            switch message.content {
            case .attachment(let attachment):
                presentation = IMessageChatMessagePresentation(
                    id: message.id,
                    direction: message.direction,
                    attachment: attachment,
                    deliveryText: deliveryText
                )
            case .localized, .userText:
                presentation = IMessageChatMessagePresentation(
                    id: message.id,
                    direction: message.direction,
                    text: resolvedText(message.content),
                    deliveryText: deliveryText
                )
            }
            timeline.append(
                IMessageChatTimelineItem(
                    id: .message(message.id),
                    content: .message(presentation)
                )
            )
            previousDate = message.sentAt
        }

        if isTyping {
            timeline.append(
                IMessageChatTimelineItem(
                    id: .typing,
                    content: .typing(
                        accessibilityLabel: localizer.text(
                            "imessage.typing.accessibility"
                        )
                    )
                )
            )
        }

        return State(timeline: timeline, isTyping: isTyping)
    }

    private func resolvedText(_ content: IMessageChatMessageContent) -> String {
        switch content {
        case .localized(let key):
            localizer.text(key)
        case .userText(let text):
            text
        case .attachment:
            ""
        }
    }

    private static func timestampText(
        for date: Date,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
