//
//  IMessageConversationView.swift
//  Demo
//

import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit
import UIKit

/// 用户在时间线消息上发起的操作。
///
/// 图片、视频和音频操作均由 ViewController 路由到对应协调器；Conversation View
/// 和 Cell 不直接创建页面级播放器。
nonisolated enum IMessageChatMessageAction: Equatable, Sendable {
    /// 请求重试指定身份的失败消息。
    case retryMessage(messageID: Int)
    /// 请求打开文件或链接附件。
    case openDocument(IMessageChatAttachment)
    /// 请求保存指定消息中的附件。
    case saveAttachment(messageID: Int, attachment: IMessageChatAttachment)
    /// 请求切换指定消息音频的播放状态。
    case toggleAudioPlayback(
        messageID: Int,
        attachment: IMessageChatAudioAttachment
    )
    /// 请求从指定索引打开媒体组的全屏预览。
    case openMediaGroup(
        messageID: Int,
        attachment: IMessageChatMediaGroupAttachment,
        index: Int
    )
}

/// 将时间线状态映射为可复用消息单元格，并管理滚动与局部交互的视图。
final class IMessageConversationView: UIView {

    /// 会话集合视图使用的稳定分区身份。
    nonisolated enum Section: Hashable, Sendable {
        /// 包含所有时间分隔、消息和输入状态项的时间线分区。
        case timeline
    }

    /// 垂直滚动并支持交互式收起键盘的消息集合视图。
    let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewFlowLayout()
    )

    /// 将时间线模型映射到单元格并执行差异更新的 ListKit 适配器。
    private lazy var adapter = CollectionListAdapter<Section>(
        collectionView: collectionView
    )
    /// 当前渲染版本，用于使旧列表完成回调失效。
    private var renderGeneration = 0
    /// 指示首次加载或主动发送触发的滚动请求尚未执行的布尔值。
    private var pendingExplicitScroll = false
    /// 按消息和附件组合身份查询权威保存状态的回调。
    var attachmentSaveState: ((IMessageChatAttachmentSaveKey) -> IMessageChatAttachmentSaveState)?
    /// 最近一次渲染的完整状态，用于附件保存状态变化时重新配置列表。
    private var lastState: IMessageChatViewModel.State?
    /// 收到保存状态通知后记录的附件状态缓存。
    private var saveStates: [IMessageChatAttachmentSaveKey: IMessageChatAttachmentSaveState] = [:]

    /// 更新指定附件的保存状态，并以保存原因重新渲染当前时间线。
    func updateSaveState(_ state: IMessageChatAttachmentSaveState, for key: IMessageChatAttachmentSaveKey) {
        saveStates[key] = state
        if let lastState { render(lastState, reason: .attachmentSave) }
    }

    /// 返回指定消息的附件保存状态，优先使用页面状态提供者。
    private func saveState(for message: IMessageChatMessagePresentation) -> IMessageChatAttachmentSaveState {
        guard case .attachment(let attachment) = message.content else { return .hidden }
        let key = IMessageChatAttachmentSaveKey(messageID: message.id, attachmentID: attachment.id)
        return attachmentSaveState?(key) ?? saveStates[key] ?? .available
    }

    /// 将消息内容身份与保存反馈组合的单元格刷新身份。
    nonisolated private struct SaveRefreshIdentity: Hashable, Sendable {
        /// 消息正文、附件、方向与发送状态构成的内容身份。
        let message: IMessageChatMessageRefreshIdentity
        /// 当前附件保存状态，参与判断单元格是否需要重新配置。
        let state: IMessageChatAttachmentSaveState
    }

    /// 将消息内容身份和当前保存状态组合为列表刷新标识。
    private func saveRefreshIdentity(_ message: IMessageChatMessagePresentation) -> SaveRefreshIdentity {
        .init(message: message.refreshIdentity, state: saveState(for: message))
    }

    /// 最近一次提交的时间线项目数量，用于判断初始滚动行为。
    private var timelineCount = 0
    /// 最近一次显式应用的界面布局方向。
    private var lastAppliedLayoutDirection: UIUserInterfaceLayoutDirection?
    /// 页面音频控制器发布的播放状态，供可见和新配置单元格共用。
    private var playbackState: IMessageChatPlaybackState = .idle
    /// 按消息身份保留媒体组当前封面索引的状态存储。
    private let mediaStackStateStore = IMessageChatMediaStackStateStore()
    /// 媒体消息和预览入口配置时使用的本地化文字集合。
    private var mediaStrings = IMessageChatMediaStrings(
        photo: "Photos",
        itemsFormat: "%d items",
        image: "Image",
        animatedImage: "Animated image",
        video: "Video",
        videoDurationFormat: "Video, duration %@",
        importing: "Importing",
        remove: "Remove",
        play: "Play",
        openPreview: "Open preview",
        close: "Close",
        firstItem: "First item",
        lastItem: "Last item",
        positionFormat: "%d of %d"
    )

    /// 消息 Cell 请求页面级操作时调用。
    var actionRequested: ((IMessageChatMessageAction) -> Void)?

    /// 使用指定初始边框创建 `IMessageConversationView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureCollectionView()
    }

    /// 不支持从归档创建 `IMessageConversationView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 将完整时间线状态串行应用到列表，并按更新原因选择滚动与阅读锚点策略。
    ///
    /// 列表完成回调只应用最新渲染版本；局部状态更新不会丢弃尚未执行的主动滚动请求。
    func render(
        _ state: IMessageChatViewModel.State,
        reason: IMessageChatViewModel.UpdateReason
    ) {
        lastState = state
        if reason == .initial || reason == .sentMessage { pendingExplicitScroll = true }
        let wasNearBottom = timelineCount == 0 || isNearBottom
        let localizationAnchor = (reason == .attachmentSave || ((reason == .localization || reason == .audioTranscript || reason == .messageStatus) && !wasNearBottom))
            ? collectionView.captureLocalizationAnchor()
            : nil
        timelineCount = state.timeline.count
        let mediaMessageIDs = Set(state.timeline.compactMap { item -> Int? in
            guard case .message(let message) = item.content,
                  message.mediaGroup != nil else { return nil }
            return message.id
        })
        mediaStackStateStore.retainMessages(mediaMessageIDs)
        renderGeneration &+= 1
        let generation = renderGeneration
        // 送达、已读和键入可连续发生。必须完成前一份可见内容刷新，避免
        // coalesceLatest 取代结构提交后丢失旧 Cell 的状态变更。
        let transaction = ListTransaction(
            animation: reason == .sentMessage || reason == .receivedMessage ? .automatic : .disabled,
            updatePolicy: .serial
        )

        adapter.apply(
            transaction: transaction,
            completion: { [weak self] _ in
                guard let self, self.renderGeneration == generation else {
                    return
                }
                self.collectionView.layoutIfNeeded()
                self.refreshMaterializedContentLayoutDirection()

                let explicitScroll = self.pendingExplicitScroll
                self.pendingExplicitScroll = false
                if let localizationAnchor, !explicitScroll {
                    _ = self.collectionView.restoreLocalizationAnchor(
                        localizationAnchor
                    )
                    return
                }

                let shouldScroll: Bool = switch reason {
                case .attachmentSave:
                    false
                case .initial, .sentMessage:
                    true
                case .receivedMessage, .localization, .audioTranscript, .messageStatus:
                    wasNearBottom
                }
                guard explicitScroll || shouldScroll else { return }
                self.scrollToBottom(
                    animated: reason == .sentMessage
                        || reason == .receivedMessage
                )
            }
        ) {
            ListSection(.timeline) {
                ForEach(state.timeline, id: \.id) { item in
                    switch item.content {
                    case .timestamp(let timestamp):
                        Row(
                            model: timestamp,
                            cell: IMessageTimestampCell.self
                        ) { cell, timestamp, _ in
                            cell.configure(timestamp)
                        }
                        .refreshID(timestamp.text)

                    case .message(let message):
                        switch message.content {
                        case .text:
                            Row(
                                model: message,
                                cell: IMessageBubbleCell.self
                            ) { [weak self] cell, message, _ in
                                cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                cell.configure(message)
                            }
                            .refreshID(message.refreshIdentity)
                            .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))

                        case .attachment(let attachment):
                            switch attachment {
                            case .file, .link:
                                Row(model: message, cell: IMessageChatDocumentBubbleCell.self) { [weak self] cell, message, _ in
                                    cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                    cell.open = { [weak self] in self?.actionRequested?(.openDocument($0)) }
                                    cell.saveRequested = { [weak self] in
                                        self?.actionRequested?(.saveAttachment(messageID: message.id, attachment: attachment))
                                    }
                                    cell.configure(message, saveState: self?.saveState(for: message) ?? .available)
                                }
                                .refreshID(saveRefreshIdentity(message))
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            case .audio:
                                Row(
                                    model: message,
                                    cell: IMessageAudioBubbleCell.self
                                ) { [weak self] cell, message, _ in
                                    guard let self else { return }
                                    cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                    cell.playbackRequested = {
                                        [weak self] id, audio in
                                        self?.actionRequested?(
                                            .toggleAudioPlayback(
                                                messageID: id,
                                                attachment: audio
                                            )
                                        )
                                    }
                                    cell.configure(
                                        message,
                                        playback: playbackState,
                                        playAccessibilityLabel: DemoLocalization.text(
                                            "imessage.audio.play"
                                        ),
                                        pauseAccessibilityLabel: DemoLocalization.text(
                                            "imessage.audio.pause"
                                        )
                                    )
                                }
                                .refreshID(message.refreshIdentity)
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            case .mediaGroup(let group):
                                Row(
                                    model: message,
                                    cell: IMessageChatMediaBubbleCell.self
                                ) { [weak self] cell, message, _ in
                                    guard let self else { return }
                                    cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                    cell.frontIndexDidChange = {
                                        [weak self] messageID, index in
                                        self?.mediaStackStateStore.setIndex(
                                            index,
                                            for: messageID,
                                            itemCount: group.items.count
                                        )
                                    }
                                    cell.previewRequested = {
                                        [weak self] messageID, attachment, index in
                                        self?.actionRequested?(
                                            .openMediaGroup(
                                                messageID: messageID,
                                                attachment: attachment,
                                                index: index
                                            )
                                        )
                                    }
                                    cell.saveRequested = { [weak self] in
                                        self?.actionRequested?(.saveAttachment(messageID: message.id, attachment: .mediaGroup(group)))
                                    }
                                    cell.configure(
                                        message,
                                        group: group,
                                        frontIndex: mediaStackStateStore.index(
                                            for: message.id,
                                            itemCount: group.items.count
                                        ),
                                        strings: mediaStrings,
                                        saveState: saveState(for: message)
                                    )
                                }
                                .refreshID(saveRefreshIdentity(message))
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            }
                        }

                    case .typing(let accessibilityLabel):
                        Row(
                            model: accessibilityLabel,
                            cell: IMessageTypingCell.self
                        ) { cell, accessibilityLabel, _ in
                            cell.configure(
                                accessibilityLabel: accessibilityLabel
                            )
                        }
                        .refreshID(accessibilityLabel)
                    }
                }
            }
            .selectionMode(.none)
            .layout(
                .list(
                    itemHeight: .estimated(52),
                    spacing: 2,
                    contentInsets: .init(
                        top: 10,
                        leading: 0,
                        bottom: 10,
                        trailing: 0
                    )
                )
            )
        }
    }

    /// 更新后续媒体单元格配置使用的本地化文字集合。
    func configureMediaStrings(_ strings: IMessageChatMediaStrings) {
        mediaStrings = strings
    }

    /// 将页面级播放状态应用到可见的音频消息 Cell。
    ///
    /// 屏幕外的 Cell 会在 ListKit 配置时接收相同状态。
    ///
    /// - Parameter playback: 当前音频消息播放状态。
    func updateAudioPlayback(_ playback: IMessageChatPlaybackState) {
        playbackState = playback
        for case let cell as IMessageAudioBubbleCell
                in collectionView.visibleCells {
            cell.updatePlayback(
                playback,
                playAccessibilityLabel: DemoLocalization.text(
                    "imessage.audio.play"
                ),
                pauseAccessibilityLabel: DemoLocalization.text(
                    "imessage.audio.pause"
                )
            )
        }
    }

    /// 应用指定布局方向并重建集合布局，同时尽量保留当前可见消息位置。
    func applyLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        lastAppliedLayoutDirection = direction
        collectionView.applyLocalization(
            DemoLocalization.layoutDirectionUpdate(direction),
            preservingVisibleItem: true,
            rebuildingLayoutWith: { [unowned self] in
                makeCollectionViewLayout()
            }
        )
    }

    /// 将最后一个时间线项目滚动到可见区域底部；列表为空时直接返回。
    func scrollToBottom(animated: Bool) {
        guard collectionView.numberOfSections > 0 else { return }
        let section = collectionView.numberOfSections - 1
        let itemCount = collectionView.numberOfItems(inSection: section)
        guard itemCount > 0 else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: itemCount - 1, section: section),
            at: .bottom,
            animated: animated
        )
    }

    /// 指示当前滚动位置距离内容底部不超过 88 点的布尔值。
    var isNearBottom: Bool {
        collectionView.layoutIfNeeded()
        let minimumOffset = -collectionView.adjustedContentInset.top
        let maximumOffset = max(
            minimumOffset,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        return maximumOffset - collectionView.contentOffset.y <= 88
    }

    /// 配置集合视图的滚动、键盘、辅助功能及组合布局行为。
    private func configureCollectionView() {
        backgroundColor = .systemBackground
        collectionView.frame = bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.accessibilityIdentifier = "imessage.timeline"
        addSubview(collectionView)
        collectionView.collectionViewLayout = makeCollectionViewLayout()
    }

    /// 创建不自动引用系统内容内边距的垂直时间线组合布局。
    private func makeCollectionViewLayout()
        -> UICollectionViewCompositionalLayout {
        adapter.makeCompositionalLayout(
            configuration: ListCompositionalLayoutConfiguration(
                scrollDirection: .vertical,
                interSectionSpacing: 0,
                contentInsetsReference: .none
            )
        )
    }

    /// 向已经物化的单元格重新应用当前布局方向，并保留可见项目位置。
    private func refreshMaterializedContentLayoutDirection() {
        guard collectionView.window != nil
                || collectionView.semanticContentAttribute != .unspecified else {
            return
        }
        let direction = lastAppliedLayoutDirection
            ?? collectionView.effectiveUserInterfaceLayoutDirection
        collectionView.applyLocalization(
            DemoLocalization.layoutDirectionUpdate(
                direction,
                reasons: [.layoutDirection, .configuration]
            ),
            preservingVisibleItem: true
        )
    }
}

#if DEBUG
/// 创建指定布局方向、使用固定时间线数据的会话列表预览。
@MainActor
private func makeIMessageConversationPreview(
    direction: UIUserInterfaceLayoutDirection
) -> UIViewController {
    let conversationView = IMessageConversationView(frame: .zero)
    conversationView.applyLayoutDirection(direction)
    conversationView.render(IMessageChatPreviewData.state, reason: .initial)
    return QuickLayoutHostingController {
        conversationView.resizable().frame(width: 390, height: 560)
    }
}

#Preview("消息会话列表") {
    makeIMessageConversationPreview(direction: .leftToRight)
}

#Preview("消息会话列表 · RTL") {
    makeIMessageConversationPreview(direction: .rightToLeft)
}
#endif
