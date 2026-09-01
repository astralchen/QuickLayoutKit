//
//  IMessageConversationView.swift
//  Demo
//

import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit
import UIKit

final class IMessageConversationView: UIView {

    nonisolated enum Section: Hashable, Sendable {
        case timeline
    }

    let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewFlowLayout()
    )

    private lazy var adapter = CollectionListAdapter<Section>(
        collectionView: collectionView
    )
    private var renderGeneration = 0
    private var timelineCount = 0
    private var lastAppliedLayoutDirection: UIUserInterfaceLayoutDirection?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureCollectionView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(
        _ state: IMessageChatViewModel.State,
        reason: IMessageChatViewModel.UpdateReason
    ) {
        let wasNearBottom = timelineCount == 0 || isNearBottom
        let localizationAnchor = reason == .localization && !wasNearBottom
            ? collectionView.captureLocalizationAnchor()
            : nil
        timelineCount = state.timeline.count
        renderGeneration &+= 1
        let generation = renderGeneration
        let transaction: ListTransaction = switch reason {
        case .sentMessage, .receivedMessage:
            .automatic
        case .initial, .localization:
            .disabled
        }

        adapter.apply(
            transaction: transaction,
            completion: { [weak self] _ in
                guard let self, self.renderGeneration == generation else {
                    return
                }
                self.collectionView.layoutIfNeeded()
                self.refreshMaterializedContentLayoutDirection()

                if let localizationAnchor {
                    _ = self.collectionView.restoreLocalizationAnchor(
                        localizationAnchor
                    )
                    return
                }

                let shouldScroll: Bool = switch reason {
                case .initial, .sentMessage:
                    true
                case .receivedMessage, .localization:
                    wasNearBottom
                }
                guard shouldScroll else { return }
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
                        Row(
                            model: message,
                            cell: IMessageBubbleCell.self
                        ) { cell, message, _ in
                            cell.configure(message)
                        }
                        .refreshID([
                            message.text,
                            message.deliveryText ?? "",
                            message.direction.rawValue,
                        ])

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
