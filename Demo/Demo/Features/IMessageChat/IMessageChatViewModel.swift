//
//  IMessageChatViewModel.swift
//  Demo
//

import AppLocalization
import Foundation

/// 管理本地聊天消息、发送尝试、模拟回复及时间线展示状态的对象。
///
/// 所有消息状态更新在主 Actor 上串行执行，异步结果通过操作身份校验后应用。
@MainActor
final class IMessageChatViewModel {

    /// 描述本次发出消息应产生的模拟回复载荷。
    private enum ReplyKind {
        /// 使用现有本地化文本生成回复。
        case text

        /// 使用发送时解析的文本和区域设置生成本地音频附件。
        case synthesizedAudio(text: String, locale: Locale, fallback: IMessageChatAttachment)

        /// 保留原文件与元数据，以独立身份模拟对方发送同类型附件。
        case attachment(IMessageChatAttachment)
    }

    /// 指明时间线更新来源，以便视图选择动画与滚动策略。
    enum UpdateReason: Equatable {
        /// 首次绑定时发布完整初始状态。
        case initial
        /// 当前用户追加了发出消息。
        case sentMessage
        /// 时间线追加了收到的消息。
        case receivedMessage
        /// 应用语言变化，需要重新解析展示文字。
        case localization
        /// 音频文件识别完成，需要回填气泡文字。
        case audioTranscript
        /// 附件保存反馈发生变化，需要刷新对应单元格。
        case attachmentSave
        /// 发送、送达、已读或处理状态发生变化。
        case messageStatus
    }

    /// 供会话视图一次性渲染的完整状态快照。
    struct State: Equatable {
        /// 按展示顺序排列的时间、消息与输入状态项。
        let timeline: [IMessageChatTimelineItem]
        /// 指示是否显示对方正在输入的布尔值。
        let isTyping: Bool
        /// 指示发送、排队回复或活动回复是否仍在处理的布尔值。
        var isProcessingMessages: Bool = false
    }

    /// 在主 Actor 上取得当前日期的闭包类型。
    typealias Clock = @MainActor () -> Date
    /// 在主 Actor 上取得当前区域设置的闭包类型。
    typealias LocaleProvider = @MainActor () -> Locale
    /// 可取消的异步延时操作类型，用于模拟回复时序。
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    /// 携带完整状态及更新原因的渲染回调类型。
    typealias StateHandler = (State, UpdateReason) -> Void

    /// 插入时间分隔项所需的相邻消息最小间隔，单位为秒。
    private static let timestampInterval: TimeInterval = 5 * 60

    /// 将消息资源键解析为当前语言文字的本地化服务。
    private let localizer: Localizer
    /// 生成消息时间的可注入时钟。
    private let clock: Clock
    /// 在生成模拟回复时捕获当前语言的区域设置提供者。
    private let localeProvider: LocaleProvider
    /// 控制模拟阅读与回复延时的可注入挂起操作。
    private let sleeper: Sleeper
    /// 为音频消息生成同类型回复的可选合成器。
    private let replyAudioSynthesizer: (any IMessageChatReplyAudioSynthesizing)?
    /// 当前绑定的状态渲染回调。
    private var render: StateHandler?
    /// 按进入会话顺序保存的原始消息数组。
    private var messages: [IMessageChatMessage]
    /// 下一条新增消息将使用的递增标识符。
    private var nextMessageID: Int
    /// 串行处理模拟回复队列的任务；空闲时为 `nil`。
    private var pendingReplyTask: Task<Void, Never>?
    /// 按发送顺序保存的待回复消息身份与回复类型。
    private var pendingReplies: [(messageID: Int, kind: ReplyKind)] = []
    /// 当前是否需要在时间线显示对方输入状态。
    private var isTyping = false
    /// 提供异步发送确认或失败结果的消息发送器。
    private let messageSender: any IMessageChatMessageSending
    /// 指示是否接受并应用模拟阅读回执的布尔值。
    private let readReceiptsEnabled: Bool
    /// 按消息身份索引的活动发送任务。
    private var sendTasks: [Int: Task<Void, Never>] = [:]
    /// 每条消息当前发送尝试的令牌，用于拒绝旧尝试的异步结果。
    private var sendAttempts: [Int: UUID] = [:]
    /// 回复队列当前代次的令牌，取消后更换以使旧结果失效。
    private var replyGeneration = UUID()
    /// 当前正在生成回复的原发出消息标识符。
    private var activeReplyID: Int?

    /// 最近一次生成并向界面发布的完整状态快照。
    private(set) var state: State

    /// 使用实时本地化、系统时钟和默认模拟发送器创建视图模型。
    convenience init() {
        self.init(
            localizer: .live,
            clock: Date.init,
            localeProvider: {
                Localization.localizationController.currentLocale.locale
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
                Localization.localizationController.currentLocale.locale
            },
            replyAudioSynthesizer: replyAudioSynthesizer,
            sleeper: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    /// 使用可注入依赖创建聊天视图模型，并生成初始示例消息。
    ///
    /// - Parameters:
    ///   - localizer: 用于解析资源键的本地化服务。
    ///   - clock: 新消息时间来源。
    ///   - localeProvider: 发送时捕获的语言来源，默认使用当前应用区域设置。
    ///   - replyAudioSynthesizer: 可选的音频回复合成器。
    ///   - messageSender: 可选消息发送器；省略时使用本地模拟实现。
    ///   - readReceiptsEnabled: 是否处理阅读回执，默认值为 `true`。
    ///   - sleeper: 可取消的模拟时序延时操作。
    init(
        localizer: Localizer,
        clock: @escaping Clock,
        localeProvider: @escaping LocaleProvider = {
            Localization.localizationController.currentLocale.locale
        },
        replyAudioSynthesizer: (any IMessageChatReplyAudioSynthesizing)? = nil,
        messageSender: (any IMessageChatMessageSending)? = nil,
        readReceiptsEnabled: Bool = true,
        sleeper: @escaping Sleeper
    ) {
        self.localizer = localizer
        self.clock = clock
        self.localeProvider = localeProvider
        self.replyAudioSynthesizer = replyAudioSynthesizer
        self.sleeper = sleeper
        self.messageSender = messageSender ?? IMessageChatSimulatedMessageSender.liveDemo()
        self.readReceiptsEnabled = readReceiptsEnabled

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

    /// 在视图模型释放时取消回复工作任务和全部发送任务。
    deinit {
        pendingReplyTask?.cancel()
        sendTasks.values.forEach { $0.cancel() }
    }

    #if DEBUG
    /// 仅用于真实系统保存流程的 UI 回归与预览启动参数。
    func appendSavePreviewAttachment(_ attachment: IMessageChatAttachment) {
        messages.append(.init(id: nextMessageID, direction: .incoming, content: .attachment(attachment),
                              sentAt: clock(), deliveryState: nil))
        nextMessageID += 1
        publish(reason: .receivedMessage)
    }
    #endif

    /// 替换状态渲染回调，并立即以初始原因交付当前状态。
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
    /// 音频与媒体组都在写入时间线前完成文件、尺寸、时长和缩略图校验，并共用
    /// 同一条消息生命周期。
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

    /// 以一次时间线事务发送媒体组，并在其后追加可选文字消息。
    ///
    /// 媒体和文字只发布一次发送状态，各消息按顺序获得同类型回复。任一媒体无效时不会产生
    /// 部分时间线写入，调用方可以完整保留 Composer 草稿并重试。
    @discardableResult
    func sendMediaGroup(
        _ group: IMessageChatMediaGroupAttachment,
        followedByText rawText: String
    ) -> Bool {
        sendAttachments([.mediaGroup(group)], followedByText: rawText)
    }

    /// 照片面板媒体组沿用附件优先的兼容入口，统一交给有序事务发送。
    @discardableResult
    func sendAttachments(_ attachments: [IMessageChatAttachment], followedByText rawText: String) -> Bool {
        sendContents(attachments.map { .attachment($0) } + [.userText(rawText)])
    }

    /// 全批验证后按文档顺序一次性发布；失败不写入部分消息，正文不裁剪。
    @discardableResult
    func sendContents(_ contents: [IMessageChatMessageContent]) -> Bool {
        var ids: Set<UUID> = []
        var payloads: [IMessageChatMessageContent] = []
        for content in contents {
            switch content {
            case .attachment(let attachment):
                guard validates(attachment), ids.insert(attachment.id).inserted else { return false }
                payloads.append(content)
            case .userText(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payloads.append(content) }
            case .localized: return false
            }
        }
        guard !payloads.isEmpty else { return false }
        let sentAt = clock()
        let firstID = nextMessageID
        for content in payloads {
            enqueueReply(for: content, messageID: nextMessageID)
            messages.append(IMessageChatMessage(
                id: nextMessageID, direction: .outgoing, content: content,
                sentAt: sentAt, deliveryState: .sending
            ))
            nextMessageID += 1
        }
        publish(reason: .sentMessage)
        for id in firstID..<nextMessageID { startSending(messageID: id) }
        return true
    }

    /// 验证附件是否满足进入消息时间线的最低条件。
    ///
    /// - Parameter attachment: 即将发送的页面附件。
    /// - Returns: 附件文件和类型专属元数据均有效时为 `true`。
    private func validates(_ attachment: IMessageChatAttachment) -> Bool {
        switch attachment {
        case .file(let file):
            file.fileURL.isFileURL && !file.displayName.isEmpty
                && FileManager.default.isReadableFile(atPath: file.fileURL.path)
                && (try? file.fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        case .link(let link):
            IMessageChatLinkAttachment.accepts(link.url)
        case .audio(let audio):
            IMessageChatRecordingPolicy.accepts(
                duration: audio.duration,
                fileExists: FileManager.default.fileExists(
                    atPath: audio.fileURL.path
                )
            )
        case .mediaGroup(let group):
            !group.items.isEmpty
                && group.items.count <= IMessageChatMediaGroupAttachment
                    .selectionLimit
                && group.items.allSatisfy { item in
                    guard item.pixelSize.width > 0,
                          item.pixelSize.height > 0,
                          FileManager.default.fileExists(
                            atPath: item.originalFileURL.path
                          ),
                          FileManager.default.fileExists(
                            atPath: item.thumbnailFileURL.path
                          ) else {
                        return false
                    }
                    switch item.kind {
                    case .image:
                        return true
                    case .video(let duration):
                        return duration.isFinite && duration > 0
                    }
                }
        }
    }

    /// 返回附件类型对应的模拟回复计划，语音合成失败仍保持语音类型。
    private func replyKind(for attachment: IMessageChatAttachment) -> ReplyKind {
        let reply = attachment.simulatedReply()
        switch attachment {
        case .audio:
            return .synthesizedAudio(
                text: localizer.text("imessage.reply.1"),
                locale: IMessageChatSpeechConfiguration.speechLocale(for: localeProvider()),
                fallback: reply
            )
        case .mediaGroup, .file, .link:
            return .attachment(reply)
        }
    }

    /// 根据消息载荷创建对应回复类型，并将其加入有序待回复集合。
    private func enqueueReply(for content: IMessageChatMessageContent, messageID: Int) {
        let kind: ReplyKind
        if case .attachment(let attachment) = content {
            kind = replyKind(for: attachment)
        } else {
            kind = .text
        }
        pendingReplies.append((messageID, kind))
    }

    /// 追加处于发送中的消息和对应回复请求，发布状态后启动异步发送。
    private func appendOutgoing(content: IMessageChatMessageContent, replyKind: ReplyKind) {
        let messageID = nextMessageID
        pendingReplies.append((messageID, replyKind))
        messages.append(IMessageChatMessage(
            id: nextMessageID, direction: .outgoing, content: content,
            sentAt: clock(), deliveryState: .sending
        ))
        nextMessageID += 1
        publish(reason: .sentMessage)
        startSending(messageID: messageID)
    }

    /// 仅更新身份仍匹配的音频，不改变消息生命周期或重新安排回复。
    @discardableResult
    func updateAudioTranscript(_ rawText: String, messageID: Int, attachmentID: UUID) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              case .attachment(.audio(var audio)) = messages[index].content,
              audio.id == attachmentID, audio.transcript == nil else { return false }
        audio.transcript = text
        messages[index].content = .attachment(.audio(audio))
        publish(reason: .audioTranscript)
        return true
    }

    /// 按当前语言重新生成并发布展示状态，保留消息原始载荷。
    func refreshLocalizedContent() {
        publish(reason: .localization)
    }

    /// 页面离开时取消整个模拟会话，令迟到送达、已读和回复全部失效。
    func cancelPendingReply() {
        replyGeneration = UUID()
        pendingReplyTask?.cancel()
        pendingReplyTask = nil
        activeReplyID = nil
        pendingReplies.removeAll()
        sendTasks.values.forEach { $0.cancel() }
        sendTasks.removeAll()
        sendAttempts.removeAll()
        for index in messages.indices where messages[index].deliveryState == .sending {
            messages[index].deliveryState = .failed
        }
        isTyping = false
        publish(reason: .messageStatus)
    }

    /// 重试原消息；保持 ID、顺序、附件和发送时间，重复点击不会启动第二次尝试。
    @discardableResult
    func retryMessage(id: Int) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id && $0.direction == .outgoing }),
              messages[index].deliveryState == .failed else { return false }
        messages[index].deliveryState = .sending
        enqueueReply(for: messages[index].content, messageID: id)
        publish(reason: .messageStatus)
        startSending(messageID: id)
        return true
    }

    /// 为尚无活动请求的发送中消息创建新的发送尝试。
    ///
    /// 异步完成后验证取消状态、尝试令牌和消息状态，再应用送达或失败结果。
    private func startSending(messageID: Int) {
        guard let message = messages.first(where: { $0.id == messageID }),
              message.deliveryState == .sending, sendTasks[messageID] == nil else { return }
        let attempt = UUID()
        sendAttempts[messageID] = attempt
        let sender = messageSender
        sendTasks[messageID] = Task { [weak self] in
            let succeeded: Bool
            do {
                try await sender.send(message)
                succeeded = true
            } catch {
                succeeded = false
            }
            // 重试或页面退出可能已替换发送尝试；成功和失败都必须通过同一身份校验。
            guard !Task.isCancelled, let self, sendAttempts[messageID] == attempt,
                  let index = messages.firstIndex(where: { $0.id == messageID }),
                  messages[index].deliveryState == .sending else { return }
            sendTasks[messageID] = nil
            sendAttempts[messageID] = nil
            messages[index].deliveryState = succeeded ? .delivered : .failed
            if !succeeded { pendingReplies.removeAll { $0.messageID == messageID } }
            publish(reason: .messageStatus)
            scheduleReplies()
        }
    }

    /// 收件端阅读回执是独立事件，只推进到指定已存在消息；不根据回复推断已读。
    /// 连续消息的已读进度单调前进，失败和仍在发送的消息不会被提前标记。
    func receiveReadReceipt(through messageID: Int) {
        guard readReceiptsEnabled,
              messages.contains(where: { $0.id == messageID && $0.direction == .outgoing &&
                  ($0.deliveryState == .delivered || $0.deliveryState == .read) }) else { return }
        var changed = false
        for index in messages.indices where messages[index].id <= messageID &&
            messages[index].direction == .outgoing && messages[index].deliveryState == .delivered {
            messages[index].deliveryState = .read
            changed = true
        }
        if changed { publish(reason: .messageStatus) }
    }

    /// 在队首消息已送达时启动单个回复任务，按顺序模拟阅读和同类型回复。
    ///
    /// 每次挂起后验证回复代次，取消或异常时避免遗留输入状态与工作任务所有权。
    private func scheduleReplies() {
        guard pendingReplyTask == nil, let first = pendingReplies.first,
              messages.contains(where: { $0.id == first.messageID &&
                  ($0.deliveryState == .delivered || $0.deliveryState == .read) }) else { return }
        let generation = replyGeneration
        let sleeper = sleeper
        let synthesizer = replyAudioSynthesizer
        activeReplyID = first.messageID
        pendingReplyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let reply = self?.takeNextReply(generation: generation) else { return }
                do {
                    // 模拟对方先查看消息，随后才开始键入；已读不等待附件准备或回复完成。
                    try await sleeper(.milliseconds(300))
                    guard !Task.isCancelled, self?.replyGeneration == generation else { return }
                    self?.receiveReadReceipt(through: reply.messageID)
                    if case .text = reply.kind { self?.setTyping(true) }
                    let content: IMessageChatMessageContent
                    switch reply.kind {
                    case .text:
                        try await sleeper(.milliseconds(900))
                        content = .localized(key: "imessage.reply.1")
                    case .attachment(let attachment):
                        try await sleeper(.milliseconds(900))
                        content = .attachment(attachment)
                    case .synthesizedAudio(let text, let locale, let fallback):
                        async let audio = synthesizer?.synthesizeReplyAudio(text: text, locale: locale)
                        try await sleeper(.milliseconds(900))
                        if let generated = try? await audio {
                            content = .attachment(.audio(generated))
                        } else {
                            content = .attachment(fallback)
                        }
                    }
                    guard !Task.isCancelled, self?.replyGeneration == generation else { return }
                    self?.completeReply(content: content)
                } catch {
                    // 延时/生成任务异常也必须释放队列所有权，不能永久卡在“正在输入”。
                    guard !Task.isCancelled, self?.replyGeneration == generation else { return }
                    self?.finishReplyWorker()
                    self?.scheduleReplies()
                    return
                }
            }
        }
    }

    /// 取出当前代次中已经送达的队首回复请求；无法继续时结束工作状态。
    private func takeNextReply(generation: UUID) -> (messageID: Int, kind: ReplyKind)? {
        guard generation == replyGeneration else { return nil }
        guard let first = pendingReplies.first,
              messages.contains(where: { $0.id == first.messageID &&
                  ($0.deliveryState == .delivered || $0.deliveryState == .read) }) else {
            finishReplyWorker()
            return nil
        }
        activeReplyID = first.messageID
        return pendingReplies.removeFirst()
    }

    /// 仅在输入状态变化时记录新值并发布时间线更新。
    private func setTyping(_ value: Bool) {
        guard isTyping != value else { return }
        isTyping = value
        publish(reason: .messageStatus)
    }

    /// 解除活动回复任务与消息身份，关闭输入状态并发布更新。
    private func finishReplyWorker() {
        pendingReplyTask = nil
        activeReplyID = nil
        isTyping = false
        publish(reason: .messageStatus)
    }

    /// 将回复载荷追加为收到消息，推进消息身份并结束当前输入提示。
    private func completeReply(content: IMessageChatMessageContent) {
        messages.append(IMessageChatMessage(
            id: nextMessageID, direction: .incoming, content: content,
            sentAt: clock(), deliveryState: nil
        ))
        nextMessageID += 1
        isTyping = false
        publish(reason: .receivedMessage)
    }

    /// 重新生成完整展示状态，并携带指定原因同步调用渲染回调。
    private func publish(reason: UpdateReason) {
        state = makeState()
        render?(state, reason)
    }

    /// 将原始消息解析为有序时间线，补充时间分隔、发送状态文字和输入状态项。
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
                        locale: Localization.localizationController
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
            if message.direction == .outgoing, let deliveryState = message.deliveryState,
               message.id == latestOutgoingID || deliveryState == .sending || deliveryState == .failed {
                let key: String = switch deliveryState {
                case .sending: "imessage.status.sending"
                case .delivered: "imessage.status.delivered"
                case .read: "imessage.status.read"
                case .failed: "imessage.status.failed"
                }
                deliveryText = localizer.text(key)
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
                    deliveryText: deliveryText,
                    deliveryState: message.deliveryState
                )
            case .localized, .userText:
                presentation = IMessageChatMessagePresentation(
                    id: message.id,
                    direction: message.direction,
                    text: resolvedText(message.content),
                    deliveryText: deliveryText,
                    deliveryState: message.deliveryState
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

        return State(timeline: timeline, isTyping: isTyping, isProcessingMessages:
            activeReplyID != nil || !pendingReplies.isEmpty || messages.contains { $0.deliveryState == .sending })
    }

    /// 解析本地化或用户文本载荷；附件载荷返回空字符串。
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

    /// 按指定区域设置将日期格式化为不含日期部分的短时间文字。
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
