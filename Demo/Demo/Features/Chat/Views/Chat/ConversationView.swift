//
//  ConversationView.swift
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
nonisolated enum MessageAction: Equatable, Sendable {
    /// 请求重试指定身份的失败消息。
    case retryMessage(messageID: Int)
    /// 执行菜单打开时锁定的内容操作。
    case menu(MessageMenuOperation, MessageMenuTarget)
    /// 请求打开文件或链接附件。
    case openDocument(messageID: Int, attachment: Attachment)
    /// 请求保存指定消息中的附件。
    case saveAttachment(messageID: Int, attachment: Attachment)
    /// 请求切换指定消息音频的播放状态。
    case toggleAudioPlayback(
        messageID: Int,
        attachment: AudioAttachment
    )
    /// 请求从指定索引打开媒体组的全屏预览。
    case openMediaGroup(
        messageID: Int,
        attachment: MediaGroupAttachment,
        index: Int
    )
}

/// 将时间线状态映射为可复用消息单元格，并管理滚动与局部交互的视图。
@available(iOS 17.0, *)
final class ConversationView: QuickLayoutView, UICollectionViewDelegate, UIGestureRecognizerDelegate {

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

    /// 让消息列表随会话容器填满可用空间。
    override var body: Layout {
        collectionView.resizable()
    }

    /// 将时间线模型映射到单元格并执行差异更新的 ListKit 适配器。
    private lazy var adapter = CollectionListAdapter<Section>(
        collectionView: collectionView
    )
    /// 当前渲染版本，用于使旧列表完成回调失效。
    private var renderGeneration = 0
    /// 初始加载或发送触发的底部滚动请求；跨越状态刷新保留至滚动完成。
    private var pendingExplicitScroll = false
    /// 首次历史等待期间发生过拖动或发送时，批量插入应保留阅读位置。
    private var hasInteractedWithTimeline = false
    /// 按消息和附件组合身份查询权威保存状态的回调。
    var attachmentSaveState: ((AttachmentSaveKey) -> AttachmentSaveState)?
    /// 最近一次渲染的完整状态，用于附件保存状态变化时重新配置列表。
    private var lastState: ChatViewModel.State?
    /// 收到保存状态通知后记录的附件状态缓存。
    private var saveStates: [AttachmentSaveKey: AttachmentSaveState] = [:]

    /// 更新指定附件的保存状态，并以保存原因重新渲染当前时间线。
    func updateSaveState(_ state: AttachmentSaveState, for key: AttachmentSaveKey) {
        saveStates[key] = state
        if let lastState { render(lastState, reason: .attachmentSave) }
    }

    /// 返回指定消息的附件保存状态，优先使用页面状态提供者。
    private func saveState(for message: MessagePresentation) -> AttachmentSaveState {
        guard case .attachment(let attachment) = message.content else { return .hidden }
        let key = AttachmentSaveKey(messageID: message.id, attachmentID: attachment.id)
        return attachmentSaveState?(key) ?? saveStates[key] ?? .available
    }

    /// 将消息内容身份与保存反馈组合的单元格刷新身份。
    nonisolated private struct SaveRefreshIdentity: Hashable, Sendable {
        /// 消息正文、附件、方向与发送状态构成的内容身份。
        let message: MessageRefreshIdentity
        /// 当前附件保存状态，参与判断单元格是否需要重新配置。
        let state: AttachmentSaveState
    }

    /// 将消息内容身份和当前保存状态组合为列表刷新标识。
    private func saveRefreshIdentity(_ message: MessagePresentation) -> SaveRefreshIdentity {
        .init(message: message.refreshIdentity, state: saveState(for: message))
    }

    /// 最近一次提交的时间线项目数量，用于判断初始滚动行为。
    private var timelineCount = 0
    /// 最近一次显式应用的界面布局方向。
    private var lastAppliedLayoutDirection: UIUserInterfaceLayoutDirection?
    /// 页面音频控制器发布的播放状态，供可见和新配置单元格共用。
    private var playbackState: PlaybackState = .idle
    /// 按消息身份保留媒体组当前封面索引的状态存储。
    private let mediaStackStateStore = MediaStackStateStore()
    /// 媒体消息和预览入口配置时使用的本地化文字集合。
    private var mediaStrings = MediaStrings(
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
    var actionRequested: ((MessageAction) -> Void)?
    var menuPreviewCoordinator: MessageMenuPreviewCoordinator?
    var menuSaveState: ((MessageMenuTarget) -> AttachmentSaveState)?

    /// 重新查询可见 Cell；收回媒体组前同步封面而不移动列表。
    func previewSource(messageID: Int, attachmentID: UUID, index: Int, synchronize: Bool) -> UIView? {
        guard let message = lastState?.timeline.compactMap({ item -> MessagePresentation? in
            guard case .message(let message) = item.content else { return nil }; return message
        }).first(where: { $0.id == messageID }), case .attachment(let attachment) = message.content,
              attachment.id == attachmentID else { return nil }
        if case .mediaGroup(let group) = attachment {
            if synchronize { mediaStackStateStore.setIndex(index, for: messageID, itemCount: group.items.count) }
            guard let cell = collectionView.visibleCells.compactMap({ $0 as? MediaBubbleCell }).first(where: { $0.previewMessageID == messageID }) else { return nil }
            if synchronize {
                cell.mediaView.configure(messageID: messageID, direction: message.direction, group: group, frontIndex: index, strings: mediaStrings)
                cell.layoutIfNeeded()
                cell.mediaView.layoutIfNeeded()
            }
            return cell.mediaView.previewSourceView
        }
        return collectionView.visibleCells.compactMap { $0 as? DocumentBubbleCell }.first { $0.previewMessageID == messageID }?.card
    }

    /// 使用指定初始边框创建 `ConversationView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureCollectionView()
        adapter.collectionDelegate = self
        let selectionDismiss = UITapGestureRecognizer(target: self, action: #selector(dismissSelectionOutside(_:)))
        selectionDismiss.cancelsTouchesInView = false
        selectionDismiss.delegate = self
        addGestureRecognizer(selectionDismiss)
    }

    /// 不支持从归档创建 `ConversationView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 列表重新显示已有 Cell 时恢复缩略图消费者。
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        MediaImageView.setContentActive(true, in: cell)
        if let timeline = lastState?.timeline, timeline.indices.contains(indexPath.item),
           case .message(let message) = timeline[indexPath.item].content {
            configureMessageMenu(cell, message: message)
        }
    }

    /// 离屏立即取消读取并释放图像，无需等待 Cell 进入复用池。
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        MediaImageView.setContentActive(false, in: cell)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        endMessageSelection()
        hasInteractedWithTimeline = true
        pendingExplicitScroll = false
    }

    /// 自适应高度可能在动画期间变化，完成后再对齐一次最终底部。
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard pendingExplicitScroll else { return }
        scrollToBottom(animated: false)
    }

    /// 将完整时间线状态串行应用到列表，并按更新原因选择滚动与阅读锚点策略。
    ///
    /// 列表完成回调只应用最新渲染版本；局部状态更新不会丢弃尚未执行的主动滚动请求。
    func render(
        _ state: ChatViewModel.State,
        reason: ChatViewModel.UpdateReason
    ) {
        let previousState = lastState
        if reason == .messageDeleted { pendingExplicitScroll = false }
        lastState = state
        if reason == .sentMessage { hasInteractedWithTimeline = true }
        let preservesHistoryPosition = reason == .historyLoaded && hasInteractedWithTimeline
        if reason == .initial || reason == .sentMessage { pendingExplicitScroll = true }
        if reason == .historyLoaded && !preservesHistoryPosition { pendingExplicitScroll = true }
        let wasNearBottom = timelineCount == 0 || pendingExplicitScroll || isNearBottom
        // 回复落地后还会立即刷新“正在输入”状态；跟随意图必须保留到最新一次提交完成。
        if reason == .receivedMessage && wasNearBottom { pendingExplicitScroll = true }
        var localizationAnchor = (preservesHistoryPosition || reason == .attachmentSave || reason == .messageDeleted || ((reason == .localization || reason == .audioTranscript || reason == .messageStatus || reason == .receivedMessage) && !wasNearBottom))
            ? collectionView.captureLocalizationAnchor()
            : nil
        // 历史插入会改变 IndexPath，必须先用旧时间线身份定位同一条消息。
        if preservesHistoryPosition || reason == .messageDeleted, let anchor = localizationAnchor {
            if let previousState, previousState.timeline.indices.contains(anchor.indexPath.item),
               let item = state.timeline.firstIndex(where: {
                   $0.id == previousState.timeline[anchor.indexPath.item].id
               }) {
                localizationAnchor = .init(indexPath: IndexPath(item: item, section: 0),
                    offsetFromViewportTop: anchor.offsetFromViewportTop,
                    offsetFromViewportLeading: anchor.offsetFromViewportLeading)
            } else if reason == .messageDeleted, let previousState {
                let survivors = previousState.timeline.enumerated().filter { old in state.timeline.contains { $0.id == old.element.id } }
                if let nearest = survivors.min(by: { abs($0.offset - anchor.indexPath.item) < abs($1.offset - anchor.indexPath.item) }),
                   let newIndex = state.timeline.firstIndex(where: { $0.id == nearest.element.id }),
                   let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: nearest.offset, section: 0)) {
                    localizationAnchor = .init(indexPath: IndexPath(item: newIndex, section: 0),
                        offsetFromViewportTop: attributes.frame.minY - collectionView.contentOffset.y - collectionView.adjustedContentInset.top,
                        offsetFromViewportLeading: anchor.offsetFromViewportLeading)
                } else { localizationAnchor = nil }
            } else { localizationAnchor = nil }
        }
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
        let receivesText: Bool
        if reason == .receivedMessage, let last = state.timeline.last,
           case .message(let message) = last.content, message.direction == .incoming {
            switch message.content {
            case .text, .richText: receivesText = true
            case .attachment: receivesText = false
            }
        } else { receivesText = false }
        let animatesReceivedMessage = reason == .receivedMessage && !receivesText
        let transaction = ListTransaction(
            // 收发文本立即完成插入与底部定位，避免长文本等待动画或下一次状态刷新才显示。
            animation: animatesReceivedMessage ? .automatic : .disabled,
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
                    _ = self.collectionView.restoreLocalizationAnchor(localizationAnchor)
                    if reason == .messageDeleted {
                        // 首次恢复可能使估算高度的相邻 Cell 进入视口并触发自适应测量。
                        // 完成这一轮布局后，用同一阅读锚点校正最终几何。
                        self.collectionView.layoutIfNeeded()
                        _ = self.collectionView.restoreLocalizationAnchor(localizationAnchor)
                    }
                    return
                }

                let shouldScroll: Bool = switch reason {
                case .attachmentSave, .messageDeleted:
                    false
                case .historyLoaded:
                    !preservesHistoryPosition
                case .initial, .sentMessage:
                    true
                case .receivedMessage, .localization, .audioTranscript, .messageStatus:
                    wasNearBottom
                }
                guard explicitScroll || shouldScroll else { return }
                self.scrollToBottom(
                    animated: animatesReceivedMessage
                )
            }
        ) {
            ListSection(.timeline) {
                ForEach(state.timeline, id: \.id) { item in
                    switch item.content {
                    case .timestamp(let timestamp):
                        Row(
                            model: timestamp,
                            cell: TimestampCell.self
                        ) { cell, timestamp, _ in
                            cell.configure(timestamp)
                        }
                        .refreshID(timestamp.text)

                    case .message(let message):
                        switch message.content {
                        case .text, .richText:
                            Row(
                                model: message,
                                cell: BubbleCell.self
                            ) { [weak self] cell, message, _ in
                                cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                cell.configure(message)
                                self?.configureMessageMenu(cell, message: message)
                            }
                            .refreshID(message.refreshIdentity)
                            .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))

                        case .attachment(let attachment):
                            switch attachment {
                            case .file, .link:
                                Row(model: message, cell: DocumentBubbleCell.self) { [weak self] cell, message, _ in
                                    cell.deliveryStatusView.retryRequested = { [weak self] in self?.actionRequested?(.retryMessage(messageID: $0)) }
                                    cell.open = { [weak self] in self?.actionRequested?(.openDocument(messageID: message.id, attachment: $0)) }
                                    cell.saveRequested = { [weak self] in
                                        self?.actionRequested?(.saveAttachment(messageID: message.id, attachment: attachment))
                                    }
                                    cell.configure(message, saveState: self?.saveState(for: message) ?? .available)
                                    self?.configureMessageMenu(cell, message: message)
                                }
                                .refreshID(saveRefreshIdentity(message))
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            case .audio:
                                Row(
                                    model: message,
                                    cell: AudioBubbleCell.self
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
                                        playAccessibilityLabel: Localization.text(
                                            "imessage.audio.play"
                                        ),
                                        pauseAccessibilityLabel: Localization.text(
                                            "imessage.audio.pause"
                                        )
                                    )
                                    configureMessageMenu(cell, message: message)
                                }
                                .refreshID(message.refreshIdentity)
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            case .mediaGroup(let group):
                                Row(
                                    model: message,
                                    cell: MediaBubbleCell.self
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
                                    configureMessageMenu(cell, message: message)
                                }
                                .refreshID(saveRefreshIdentity(message))
                                .refresh(when: .automatic, action: .reconfigure(layout: .invalidate))
                            }
                        }

                    case .typing(let accessibilityLabel):
                        Row(
                            model: accessibilityLabel,
                            cell: TypingCell.self
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
        if receivesText && wasNearBottom {
            // 无动画 snapshot 已提交，但 ListKit 的完成回调会延迟到下一次主线程调度。
            // 在首帧绘制前先完成自适应测量和定位，后续状态提交仍保留底部跟随。
            collectionView.layoutIfNeeded()
            scrollToBottom(animated: false)
            pendingExplicitScroll = true
        }
    }

    /// 更新后续媒体单元格配置使用的本地化文字集合。
    func configureMediaStrings(_ strings: MediaStrings) {
        mediaStrings = strings
    }

    /// 将页面级播放状态应用到可见的音频消息 Cell。
    ///
    /// 屏幕外的 Cell 会在 ListKit 配置时接收相同状态。
    ///
    /// - Parameter playback: 当前音频消息播放状态。
    func updateAudioPlayback(_ playback: PlaybackState) {
        playbackState = playback
        for case let cell as AudioBubbleCell
                in collectionView.visibleCells {
            cell.updatePlayback(
                playback,
                playAccessibilityLabel: Localization.text(
                    "imessage.audio.play"
                ),
                pauseAccessibilityLabel: Localization.text(
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
            Localization.layoutDirectionUpdate(direction),
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
        // 长历史中的滚动尚未抵达底部时，送达/已读刷新不得恢复中途的阅读锚点。
        pendingExplicitScroll = animated && !isNearBottom
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

    /// 重查稳定身份，供菜单和执行入口共同使用。
    func message(for target: MessageMenuTarget) -> MessagePresentation? {
        lastState?.timeline.compactMap { item -> MessagePresentation? in
            guard case .message(let message) = item.content, target.matches(message) else { return nil }
            return message
        }.first
    }

    @objc private func dismissSelectionOutside(_ gesture: UITapGestureRecognizer) {
        for cell in collectionView.visibleCells.compactMap({ $0 as? BubbleCell }) {
            let text = cell.bubbleView.messageTextView
            if text.isSelectingMessageText && text.bounds.contains(gesture.location(in: text)) { return }
        }
        endMessageSelection()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func refreshMenuAccessibility() {
        for cell in collectionView.visibleCells {
            switch cell {
            case let cell as BubbleCell: cell.messageMenu.refreshAccessibility()
            case let cell as AudioBubbleCell: cell.messageMenu.refreshAccessibility()
            case let cell as DocumentBubbleCell: cell.messageMenu.refreshAccessibility()
            case let cell as MediaBubbleCell: cell.messageMenu.refreshAccessibility()
            default: break
            }
        }
    }

    func endMessageSelection() {
        for cell in collectionView.visibleCells.compactMap({ $0 as? BubbleCell }) {
            cell.bubbleView.messageTextView.endMessageSelection()
        }
    }

    func selectMessageText(_ target: MessageMenuTarget) {
        guard message(for: target) != nil,
              let index = lastState?.timeline.firstIndex(where: { $0.id == .message(target.messageID) }),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? BubbleCell else { return }
        endMessageSelection()
        cell.bubbleView.messageTextView.beginMessageSelection()
    }

    func menuSourceView(for target: MessageMenuTarget) -> UIView? {
        guard message(for: target) != nil,
              let index = lastState?.timeline.firstIndex(where: { $0.id == .message(target.messageID) }) else { return nil }
        let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
        switch cell {
        case let cell as BubbleCell: return cell.bubbleView
        case let cell as AudioBubbleCell: return cell.bubbleView
        case let cell as DocumentBubbleCell: return cell.card
        case let cell as MediaBubbleCell: return cell.mediaView.previewSourceView
        default: return nil
        }
    }

    private func configureMessageMenu(_ cell: UICollectionViewCell, message: MessagePresentation) {
        var target = MessageMenuTarget(messageID: message.id)
        if case .attachment(let attachment) = message.content { target.attachmentID = attachment.id }
        let menu: MessageMenuInteraction
        let host: UIView
        let accessibilityView: UIView
        let source: () -> MessageMenuInteraction.Source?
        switch cell {
        case let cell as BubbleCell:
            menu = cell.messageMenu
            host = cell.bubbleView
            accessibilityView = cell.bubbleView.messageTextView
            cell.bubbleView.messageTextView.usesMessageMenu = true
            source = { [weak cell] in
                guard let cell, !cell.bubbleView.messageTextView.isSelectingMessageText else { return nil }
                return .init(target: target, view: cell.bubbleView, path: cell.bubbleView.menuPreviewPath)
            }
        case let cell as AudioBubbleCell:
            menu = cell.messageMenu
            host = cell.bubbleView
            accessibilityView = cell.bubbleView.playButton
            source = { [weak cell] in
                guard let cell else { return nil }
                return .init(target: target, view: cell.bubbleView,
                             path: cell.bubbleView.menuPreviewPath)
            }
        case let cell as DocumentBubbleCell:
            menu = cell.messageMenu
            host = cell.card
            accessibilityView = cell.card
            source = { [weak cell] in
                guard let cell else { return nil }
                return .init(target: target, view: cell.card,
                             path: UIBezierPath(roundedRect: cell.card.bounds, cornerRadius: cell.card.layer.cornerRadius))
            }
        case let cell as MediaBubbleCell:
            menu = cell.messageMenu
            host = cell.mediaView
            accessibilityView = cell.mediaView
            source = { [weak cell] in
                guard let view = cell?.mediaView, let group = view.group, group.items.indices.contains(view.frontMediaIndex),
                      let preview = view.previewSourceView else { return nil }
                var selected = target
                selected.mediaItemID = group.items[view.frontMediaIndex].id
                return .init(target: selected, view: preview,
                             path: UIBezierPath(roundedRect: preview.bounds, cornerRadius: 22),
                             canPresent: !view.isAnimating && view.interaction == nil)
            }
        default: return
        }
        menu.configure(host: host, accessibilityView: accessibilityView, source: source, items: { [weak self] target in
            guard let self, let message = self.message(for: target) else { return [] }
            return MessageMenuPolicy.items(for: message, target: target, saveState: menuSaveState?(target) ?? .available)
        }, previewProvider: { [weak self] target, source in
            self?.menuPreviewCoordinator?.makePreview(target, source: source)
        }, canPreview: { [weak self] in self?.menuPreviewCoordinator?.canPreview($0) == true },
           openPreview: { [weak self] in self?.menuPreviewCoordinator?.openAccessiblePreview($0) },
           perform: { [weak self] operation, target in
            self?.actionRequested?(.menu(operation, target))
        })
    }

    /// 配置集合视图的滚动、键盘、辅助功能及组合布局行为。
    private func configureCollectionView() {
        backgroundColor = .systemBackground
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.accessibilityIdentifier = "imessage.timeline"
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
            Localization.layoutDirectionUpdate(
                direction,
                reasons: [.layoutDirection, .configuration]
            ),
            preservingVisibleItem: true
        )
    }
}

#if DEBUG
/// 创建指定布局方向、使用固定时间线数据的会话列表预览。
@available(iOS 17.0, *)
@MainActor
private func makeConversationPreview(
    direction: UIUserInterfaceLayoutDirection
) -> UIViewController {
    let conversationView = ConversationView(frame: .zero)
    conversationView.applyLayoutDirection(direction)
    conversationView.render(ConversationPreviewData.state, reason: .initial)
    return QuickLayoutHostingController {
        conversationView.resizable().frame(width: 390, height: 560)
    }
}

@available(iOS 17.0, *)
#Preview("消息会话列表") {
    makeConversationPreview(direction: .leftToRight)
}

@available(iOS 17.0, *)
#Preview("消息会话列表 · RTL") {
    makeConversationPreview(direction: .rightToLeft)
}
#endif
