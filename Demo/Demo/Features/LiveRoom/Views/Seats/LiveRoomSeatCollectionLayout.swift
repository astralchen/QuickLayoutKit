//
//  LiveRoomSeatCollectionLayout.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import UIKit

/// CollectionView 内部使用的展示身份。
///
/// 有用户时使用 `userID`，保证用户换麦或切换房型时仍是同一个 Item；空麦使用
/// `slotID`，保证每个可见空位都有稳定且互不冲突的身份。服务端 `seatID` 不参与
/// 视觉动画身份计算。
nonisolated enum LiveRoomSeatCollectionItemID: Hashable, Sendable {
    case user(LiveRoomUserID)
    case vacancy(LiveRoomSeatSlotID)
}

nonisolated struct LiveRoomSeatCollectionItem: Sendable {
    let id: LiveRoomSeatCollectionItemID
    let slot: LiveRoomSeatSlotPresentation

    init(slot: LiveRoomSeatSlotPresentation) {
        self.slot = slot
        if let userID = slot.assignment?.userID {
            id = .user(userID)
        } else {
            id = .vacancy(slot.slotID)
        }
    }
}

/// 单个麦位在自定义 Collection Layout 中的完整视觉状态。
struct LiveRoomSeatCollectionLayoutState: Equatable {
    let frame: CGRect
    let alpha: CGFloat
    let transform: CGAffineTransform

    init(
        frame: CGRect,
        alpha: CGFloat = 1,
        transform: CGAffineTransform = .identity
    ) {
        self.frame = frame
        self.alpha = alpha
        self.transform = transform
    }
}

struct LiveRoomSeatCollectionLayoutConfiguration: Equatable {
    let itemIDs: [LiveRoomSeatCollectionItemID]
    let states: [LiveRoomSeatCollectionItemID: LiveRoomSeatCollectionLayoutState]
    let contentSize: CGSize

    static let empty = Self(itemIDs: [], states: [:], contentSize: .zero)
}

/// 非滚动麦位舞台使用的绝对几何布局。
///
/// 布局只消费已经由 Resolver 校验过的 Presentation，不读取 ViewModel，也不推断
/// 后台业务。所有 Frame 都由客户端受控的布局家族与 Metrics 计算。
final class LiveRoomSeatCollectionLayout: UICollectionViewLayout {

    private(set) var configuration = LiveRoomSeatCollectionLayoutConfiguration.empty
    private var attributesByIndexPath: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    override var collectionViewContentSize: CGSize {
        configuration.contentSize
    }

    func apply(_ configuration: LiveRoomSeatCollectionLayoutConfiguration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        attributesByIndexPath.removeAll(keepingCapacity: true)
        for (index, itemID) in configuration.itemIDs.enumerated() {
            guard let state = configuration.states[itemID] else { continue }
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = state.frame
            attributes.alpha = state.alpha
            attributes.transform = state.transform
            attributes.zIndex = index
            attributesByIndexPath[indexPath] = attributes
        }
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        attributesByIndexPath.values.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        attributesByIndexPath[indexPath]
    }

    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }
}

/// 将业务布局家族解析为 CollectionView 可直接消费的绝对 Frame。
enum LiveRoomSeatCollectionGeometry {

    static func configuration(
        presentation: LiveRoomSeatStagePresentation,
        items: [LiveRoomSeatCollectionItem],
        metrics: LiveRoomSeatLayoutMetrics,
        availableWidth: CGFloat,
        direction: UIUserInterfaceLayoutDirection
    ) -> LiveRoomSeatCollectionLayoutConfiguration {
        let slots = Dictionary(
            uniqueKeysWithValues: items.map { ($0.slot.slotID, $0) }
        )
        let logicalFrames: [LiveRoomSeatCollectionItemID: CGRect]
        switch presentation.layoutFamily {
        case .partyGrid:
            logicalFrames = partyFrames(
                presentation: presentation,
                itemsBySlotID: slots,
                metrics: metrics,
                availableWidth: availableWidth
            )
        case .individualAudience:
            logicalFrames = individualFrames(
                presentation: presentation,
                itemsBySlotID: slots,
                metrics: metrics,
                availableWidth: availableWidth
            )
        case .pk:
            // 未注册的 PK 布局会在 Resolver 层被拒绝；这里不降级成其他房型。
            logicalFrames = [:]
        }

        let states = Dictionary(
            uniqueKeysWithValues: logicalFrames.map { itemID, frame in
                let resolvedFrame: CGRect
                if direction == .rightToLeft {
                    resolvedFrame = CGRect(
                        x: availableWidth - frame.maxX,
                        y: frame.minY,
                        width: frame.width,
                        height: frame.height
                    )
                } else {
                    resolvedFrame = frame
                }
                return (
                    itemID,
                    LiveRoomSeatCollectionLayoutState(frame: resolvedFrame)
                )
            }
        )
        let contentHeight = states.values.map(\.frame.maxY).max() ?? 0
        return LiveRoomSeatCollectionLayoutConfiguration(
            itemIDs: items.map(\.id),
            states: states,
            contentSize: CGSize(width: availableWidth, height: contentHeight)
        )
    }

    private static func partyFrames(
        presentation: LiveRoomSeatStagePresentation,
        itemsBySlotID: [LiveRoomSeatSlotID: LiveRoomSeatCollectionItem],
        metrics: LiveRoomSeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [LiveRoomSeatCollectionItemID: CGRect] {
        let slots = presentation.visibleSlots.sorted { $0.position < $1.position }
        guard let host = slots.first,
            let hostItem = itemsBySlotID[host.slotID]
        else { return [:] }

        let seatSize = LiveRoomSeatView.fittingSize(
            styleID: host.styleID,
            presentation: metrics.presentation,
            width: metrics.standardSeatWidth
        )
        var frames: [LiveRoomSeatCollectionItemID: CGRect] = [
            hostItem.id: CGRect(
                x: (availableWidth - seatSize.width) / 2,
                y: 0,
                width: seatSize.width,
                height: seatSize.height
            ),
        ]
        let guestSlots = Array(slots.dropFirst())
        let rowCapacity = 4
        for (offset, slot) in slots.dropFirst().enumerated() {
            guard let item = itemsBySlotID[slot.slotID] else { continue }
            let row = offset / rowCapacity
            let column = offset % rowCapacity
            let itemCountInRow = min(
                rowCapacity,
                guestSlots.count - row * rowCapacity
            )
            let rowOriginX = centeredRowOriginX(
                itemCount: itemCountInRow,
                itemWidth: seatSize.width,
                spacing: metrics.partyHorizontalSpacing,
                availableWidth: availableWidth
            )
            frames[item.id] = CGRect(
                x: rowOriginX + CGFloat(column)
                    * (seatSize.width + metrics.partyHorizontalSpacing),
                y: seatSize.height
                    + metrics.partyVerticalSpacing
                    + CGFloat(row)
                    * (seatSize.height + metrics.partyVerticalSpacing),
                width: seatSize.width,
                height: seatSize.height
            )
        }
        return frames
    }

    private static func individualFrames(
        presentation: LiveRoomSeatStagePresentation,
        itemsBySlotID: [LiveRoomSeatSlotID: LiveRoomSeatCollectionItem],
        metrics: LiveRoomSeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [LiveRoomSeatCollectionItemID: CGRect] {
        let slots = presentation.visibleSlots.sorted { $0.position < $1.position }
        guard let host = slots.first,
            let hostItem = itemsBySlotID[host.slotID]
        else { return [:] }

        let hostSize = LiveRoomSeatView.fittingSize(
            styleID: host.styleID,
            presentation: metrics.presentation,
            width: metrics.emphasizedHostWidth
        )
        var frames: [LiveRoomSeatCollectionItemID: CGRect] = [
            hostItem.id: CGRect(
                x: (availableWidth - hostSize.width) / 2,
                y: 0,
                width: hostSize.width,
                height: hostSize.height
            ),
        ]
        let guestSlots = Array(slots.dropFirst())
        let guestSizes = guestSlots.map { slot in
            LiveRoomSeatView.fittingSize(
                styleID: slot.styleID,
                presentation: metrics.presentation,
                width: metrics.standardSeatWidth
            )
        }
        let guestRowWidth = guestSizes.reduce(0) { $0 + $1.width }
            + metrics.guestHorizontalSpacing
                * CGFloat(max(0, guestSizes.count - 1))
        let guestRowOriginX = max(
            0,
            (availableWidth - guestRowWidth) / 2
        )
        var guestOriginX = guestRowOriginX
        for (offset, slot) in slots.dropFirst().enumerated() {
            guard let item = itemsBySlotID[slot.slotID] else { continue }
            let seatSize = guestSizes[offset]
            frames[item.id] = CGRect(
                x: guestOriginX,
                y: hostSize.height + metrics.stageSpacing,
                width: seatSize.width,
                height: seatSize.height
            )
            guestOriginX += seatSize.width + metrics.guestHorizontalSpacing
        }
        return frames
    }

    /// 以容器可用宽度为准居中一排麦位，不依赖设备类型或屏幕尺寸。
    private static func centeredRowOriginX(
        itemCount: Int,
        itemWidth: CGFloat,
        spacing: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let rowWidth = CGFloat(itemCount) * itemWidth
            + CGFloat(itemCount - 1) * spacing
        return max(0, (availableWidth - rowWidth) / 2)
    }
}
