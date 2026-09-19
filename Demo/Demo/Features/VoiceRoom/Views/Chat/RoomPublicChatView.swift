import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit
import UIKit

/// 单一可滚动公屏；ListKit 管理复用及增量更新，阅读位置独立于业务消息。
final class RoomPublicChatView: QuickLayoutView, UIScrollViewDelegate {
    let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    var scrollView: UIScrollView { collectionView }
    private lazy var adapter = CollectionListAdapter<String>(collectionView: collectionView)
    private let newMessagesButton = CapsuleTextButton(frame: .zero)
    private var messages: [RoomPublicMessagePresentation] = []
    private var generation = 0
    private var contentSizeObservation: NSKeyValueObservation?
    private var reconciliationScheduled = false
    private var isAdjustingPosition = false
    private var followsLatest = true
    private var isUserScrolling = false
    private struct RowVersion: Hashable, Sendable {
        let message: RoomPublicMessagePresentation
        let isLatest: Bool
    }
    private var anchor: (id: String, offset: CGFloat)?
    private var unreadIDs: Set<String> = []
    private(set) var isApplyingMessages = false
    var unreadMessageCount: Int { unreadIDs.count }
    var latestMessage: String? { messages.last?.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        ZStack(alignment: .bottomTrailing) {
            collectionView.resizable()
            if !unreadIDs.isEmpty {
                newMessagesButton.fixedSize(axis: .horizontal).fixedSize(axis: .vertical)
                    .padding(.trailing, 8).padding(.bottom, 8)
            }
        }
    }

    override func layoutSubviews() {
        isAdjustingPosition = true
        super.layoutSubviews()
        isAdjustingPosition = false
        reconcilePosition()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        collectionView.collectionViewLayout.invalidateLayout()
        scheduleReconciliation()
    }

    /// Controller 根布局（包括输入条收起）完成后再次按最终几何提交。
    func commitPendingScrollToLatest() {
        reconcilePosition()
        scheduleReconciliation()
    }

    func configure(messages: [RoomPublicMessagePresentation], scrollToLatest: Bool) {
        let firstSubmission = generation == 0
        let oldIDs = Set(self.messages.map(\.id))
        let additions = Set(messages.map(\.id)).subtracting(oldIDs)
        if firstSubmission || scrollToLatest {
            followsLatest = true
            anchor = nil
            unreadIDs.removeAll()
        } else if !followsLatest || isUserScrolling {
            unreadIDs.formUnion(additions)
        }
        if let anchor, !messages.contains(where: { $0.id == anchor.id }) {
            self.anchor = nil
            followsLatest = true
            unreadIDs.removeAll()
        }
        unreadIDs.formIntersection(messages.map(\.id))
        updateNewMessagesButton()
        guard self.messages != messages || firstSubmission else {
            commitPendingScrollToLatest()
            return
        }
        if !followsLatest, !isApplyingMessages { captureAnchor() }
        self.messages = messages
        generation += 1
        let submission = generation
        isApplyingMessages = true
        let lastID = messages.last?.id
        adapter.apply(transaction: .disabled, completion: { [weak self] _ in
            guard let self, self.generation == submission else { return }
            self.isApplyingMessages = false
            self.reconcilePosition()
            self.scheduleReconciliation()
        }) {
            ListSection("publicChat") {
                ForEach(Array(messages.enumerated()), id: \.element.id) { entry in
                    Row(model: entry.element, cell: RoomPublicMessageCell.self) { cell, message, _ in
                        cell.configure(message, identifier: message.id == lastID
                            ? "liveRoom.publicChat.latest"
                            : "liveRoom.publicChat.message.\(entry.offset)")
                    }
                    // 内容/语言或最后一条身份变化时刷新，消息 ID 始终稳定。
                    .refreshID(RowVersion(message: entry.element, isLatest: entry.element.id == lastID))
                }
            }
            .selectionMode(.none)
            .layout(.list(itemHeight: .estimated(32), spacing: 6,
                          contentInsets: .init(top: 4, leading: 0, bottom: 4, trailing: 0)))
        }
    }

    func updateLayoutDirection() {
        collectionView.semanticContentAttribute = semanticContentAttribute
        collectionView.applyLocalization(
            Localization.layoutDirectionUpdate(effectiveUserInterfaceLayoutDirection),
            preservingVisibleItem: true
        )
        scheduleReconciliation()
    }

    /// 返回最新消息，清除未读；滚动由最终自适应布局提交，避免估算高度造成跳动。
    func showLatestMessages() {
        followsLatest = true
        anchor = nil
        unreadIDs.removeAll()
        updateNewMessagesButton()
        commitPendingScrollToLatest()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 用户手势优先于尚未完成的列表/父级布局回调。
        isUserScrolling = true
        followsLatest = false
        captureAnchor()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isUserScrolling, !isAdjustingPosition, !isApplyingMessages else { return }
        followsLatest = bottomOffset - scrollView.contentOffset.y <= 44
        if followsLatest {
            anchor = nil
            if !unreadIDs.isEmpty {
                unreadIDs.removeAll()
                updateNewMessagesButton()
            }
        } else {
            captureAnchor()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollViewDidScroll(scrollView)
        if !decelerate {
            isUserScrolling = false
            scheduleReconciliation()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollViewDidScroll(scrollView)
        isUserScrolling = false
        scheduleReconciliation()
    }

    private var bottomOffset: CGFloat {
        max(-collectionView.contentInset.top,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom)
    }

    private func captureAnchor() {
        guard let attributes = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: collectionView.bounds)?
            .filter({ $0.representedElementCategory == .cell && $0.frame.intersects(collectionView.bounds) })
            .min(by: { $0.indexPath < $1.indexPath }),
              attributes.indexPath.item < messages.count else { return }
        anchor = (messages[attributes.indexPath.item].id,
                  attributes.frame.minY - collectionView.contentOffset.y)
    }

    private func reconcilePosition() {
        guard !isApplyingMessages, !isAdjustingPosition, collectionView.bounds.height > 0 else { return }
        isAdjustingPosition = true
        defer { isAdjustingPosition = false }
        collectionView.layoutIfNeeded()
        let top = max(0, collectionView.bounds.height - collectionView.contentSize.height)
        if abs(collectionView.contentInset.top - top) > 0.5 {
            collectionView.contentInset.top = top
        }
        if followsLatest, !isUserScrolling {
            collectionView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
            if !unreadIDs.isEmpty {
                unreadIDs.removeAll()
                updateNewMessagesButton()
            }
        } else if !isUserScrolling,
                  let anchor, let item = messages.firstIndex(where: { $0.id == anchor.id }),
                  let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame {
            let y = min(bottomOffset, max(-top, frame.minY - anchor.offset))
            collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    private func scheduleReconciliation() {
        guard !reconciliationScheduled else { return }
        reconciliationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconciliationScheduled = false
            self.reconcilePosition()
        }
    }

    private func updateNewMessagesButton() {
        newMessagesButton.configure(
            title: Localization.text("liveRoom.publicChat.unread", unreadIDs.count),
            font: .preferredFont(forTextStyle: .caption1),
            foregroundColor: .white,
            backgroundColor: UIColor(red: 0.39, green: 0.24, blue: 0.64, alpha: 0.96),
            contentInsets: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        )
        setNeedsQuickLayout()
    }

    private func configureViews() {
        accessibilityIdentifier = "liveRoom.publicChat.container"
        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.accessibilityIdentifier = "liveRoom.publicChat.scroll"
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(configuration:
            ListCompositionalLayoutConfiguration(scrollDirection: .vertical, interSectionSpacing: 0, contentInsetsReference: .none))
        adapter.scrollDelegate = self
        newMessagesButton.accessibilityIdentifier = "liveRoom.publicChat.newMessages"
        newMessagesButton.action = { [weak self] in self?.showLatestMessages() }
        contentSizeObservation = collectionView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            // UICollectionView 几何变化发生在主线程；延至布局退出后再改 inset/offset。
            MainActor.assumeIsolated { self?.scheduleReconciliation() }
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("语音房公屏") {
    let view = RoomPublicChatView()
    view.configure(messages: VoiceRoomPreviewData.messages.map(RoomPublicMessagePresentation.init), scrollToLatest: true)
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view.resizable().padding(14)
        }.frame(width: 390, height: 350)
    }
}
#endif
