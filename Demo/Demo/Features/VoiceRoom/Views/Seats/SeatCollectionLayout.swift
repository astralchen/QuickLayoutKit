//
//  SeatCollectionLayout.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

/// CollectionView 内部使用的展示身份。
///
/// 有用户时使用 `userID`，保证用户换麦或切换房型时仍是同一个 Item；空麦使用
/// `slotID`，保证每个可见空位都有稳定且互不冲突的身份。服务端 `seatID` 不参与
/// 视觉动画身份计算。
nonisolated enum SeatCollectionItemID: Hashable, Sendable {
    /// 以稳定用户标识维持有人麦位跨布局移动的身份。
    case user(RoomUserID)
    /// 以稳定布局位置标识维持空麦条目的身份。
    case vacancy(SeatSlotID)
}

/// 将稳定集合条目标识与一个麦位展示状态绑定的数据项。
nonisolated struct SeatCollectionItem: Sendable {
    /// 用于区分当前数据项的稳定标识。
    let id: SeatCollectionItemID
    /// 此集合条目对应的麦位展示数据。
    let slot: SeatSlotPresentation

    /// 以占麦用户标识或空麦位置标识创建集合条目。
    init(slot: SeatSlotPresentation) {
        self.slot = slot
        if let userID = slot.assignment?.userID {
            id = .user(userID)
        } else {
            id = .vacancy(slot.slotID)
        }
    }
}

/// 单个麦位在自定义 Collection Layout 中的完整视觉状态。
struct SeatCollectionLayoutState: Equatable {
    /// 条目在集合视图内容坐标系中的矩形，单位为点。
    let frame: CGRect
    /// 条目显示的不透明度，范围为 `0...1`。
    let alpha: CGFloat
    /// 应用到条目的二维几何变换。
    let transform: CGAffineTransform

    /// 创建指定矩形的条目几何状态；默认完全不透明且不应用变换。
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

/// 一次布局提交所需的条目顺序、几何状态和内容尺寸。
struct SeatCollectionLayoutConfiguration: Equatable {
    /// 按集合视图显示顺序排列的稳定条目标识。
    let itemIDs: [SeatCollectionItemID]
    /// 以稳定条目标识索引的几何和透明度状态。
    let states: [SeatCollectionItemID: SeatCollectionLayoutState]
    /// 整个集合视图内容区域的尺寸，单位为点。
    let contentSize: CGSize

    /// 不包含条目且内容尺寸为零的初始布局配置。
    static let empty = Self(itemIDs: [], states: [:], contentSize: .zero)
}

/// 非滚动麦位舞台使用的绝对几何布局。
///
/// 布局只消费已经由 Resolver 校验过的 Presentation，不读取 ViewModel，也不推断
/// 后台业务。所有 Frame 都由客户端受控的布局家族与 Metrics 计算。
final class SeatCollectionLayout: UICollectionViewLayout {

    /// 最近一次提交给布局对象的完整几何配置。
    private(set) var configuration = SeatCollectionLayoutConfiguration.empty
    /// 按索引路径缓存的集合视图布局属性。
    private var attributesByIndexPath: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    /// 当前几何配置声明的内容尺寸，单位为点。
    override var collectionViewContentSize: CGSize {
        configuration.contentSize
    }

    /// 替换几何配置、重建布局属性并使集合视图布局失效。
    func apply(_ configuration: SeatCollectionLayoutConfiguration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        // Snapshot 更新期间 UIKit 可能在下一次 prepare() 前查询布局。
        // 配置与缓存必须同步切换，避免返回旧并集的索引或旧身份对应的 Frame。
        rebuildAttributes()
        invalidateLayout()
    }

    /// 按当前条目顺序生成包含位置、透明度和变换的布局属性缓存。
    private func rebuildAttributes() {
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

    /// 返回与指定内容矩形相交且索引仍有效的条目布局属性。
    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        let itemCount = currentItemCount
        return attributesByIndexPath.values.filter {
            $0.indexPath.item < itemCount && $0.frame.intersects(rect)
        }
    }

    /// 返回指定有效索引路径的布局属性；不存在时为 `nil`。
    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0,
            indexPath.item >= 0,
            indexPath.item < currentItemCount
        else { return nil }
        return attributesByIndexPath[indexPath]
    }

    // 配置和 Diffable Snapshot 分两步提交；缓存即使是最新配置，也只能向 UIKit
    // 返回当前 Snapshot 中存在的索引。不要在建缓存时裁剪，否则扩展后会缺失麦位。
    /// 集合视图当前第一分区中可安全查询的条目数量。
    private var currentItemCount: Int {
        guard let collectionView, collectionView.numberOfSections > 0 else { return 0 }
        return collectionView.numberOfItems(inSection: 0)
    }

    /// 返回容器宽度变化是否超过半点；只有满足该条件时才使布局失效。
    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }
}

/// 将业务布局家族解析为 CollectionView 可直接消费的绝对 Frame。
@MainActor
enum SeatCollectionGeometry {

    /// 根据舞台数据、尺寸参数、可用宽度和布局方向生成确定性几何配置。
    static func configuration(
        presentation: SeatStagePresentation,
        items: [SeatCollectionItem],
        metrics: SeatLayoutMetrics,
        availableWidth: CGFloat,
        direction: UIUserInterfaceLayoutDirection
    ) -> SeatCollectionLayoutConfiguration {
        let slots = Dictionary(
            uniqueKeysWithValues: items.map { ($0.slot.slotID, $0) }
        )
        let logicalFrames: [SeatCollectionItemID: CGRect]
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
            let geometry = RoomPKGeometry(width: availableWidth, sizeClass: metrics.sizeClass)
            logicalFrames = Dictionary(uniqueKeysWithValues: items.map { item in
                (item.id, geometry.frame(side: item.slot.roomSide, position: item.slot.position.rawValue))
            })
        }

        let states = Dictionary(
            uniqueKeysWithValues: logicalFrames.map { itemID, frame in
                let resolvedFrame: CGRect
                // 普通房型镜像逻辑布局；厅 PK 保持本房在物理左侧，避免交换双方身份位置。
                if direction == .rightToLeft && presentation.layoutID != .roomPKNine {
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
                    SeatCollectionLayoutState(frame: resolvedFrame)
                )
            }
        )
        let contentHeight = states.values.map(\.frame.maxY).max() ?? 0
        return SeatCollectionLayoutConfiguration(
            itemIDs: items.map(\.id),
            states: states,
            contentSize: CGSize(width: availableWidth, height: contentHeight)
        )
    }

    /// 返回派对房主持麦与两排观众麦在舞台中的矩形。
    private static func partyFrames(
        presentation: SeatStagePresentation,
        itemsBySlotID: [SeatSlotID: SeatCollectionItem],
        metrics: SeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [SeatCollectionItemID: CGRect] {
        let slots = presentation.visibleSlots.sorted { $0.position < $1.position }
        guard let host = slots.first,
            let hostItem = itemsBySlotID[host.slotID]
        else { return [:] }

        let seatSize = SeatView.fittingSize(
            styleID: host.styleID,
            sizeClass: metrics.sizeClass,
            width: metrics.standardSeatWidth
        )
        var frames: [SeatCollectionItemID: CGRect] = [
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

    /// 返回个播房放大主持麦及可见观众麦的矩形。
    private static func individualFrames(
        presentation: SeatStagePresentation,
        itemsBySlotID: [SeatSlotID: SeatCollectionItem],
        metrics: SeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [SeatCollectionItemID: CGRect] {
        let slots = presentation.visibleSlots.sorted { $0.position < $1.position }
        guard let host = slots.first,
            let hostItem = itemsBySlotID[host.slotID]
        else { return [:] }

        let hostSize = SeatView.fittingSize(
            styleID: host.styleID,
            sizeClass: metrics.sizeClass,
            width: metrics.emphasizedHostWidth
        )
        var frames: [SeatCollectionItemID: CGRect] = [
            hostItem.id: CGRect(
                x: (availableWidth - hostSize.width) / 2,
                y: 0,
                width: hostSize.width,
                height: hostSize.height
            ),
        ]
        let guestSlots = Array(slots.dropFirst())
        let guestSizes = guestSlots.map { slot in
            SeatView.fittingSize(
                styleID: slot.styleID,
                sizeClass: metrics.sizeClass,
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
