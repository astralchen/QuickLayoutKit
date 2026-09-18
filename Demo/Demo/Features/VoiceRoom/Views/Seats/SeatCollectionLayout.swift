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

/// 一个麦位的布局输入；不持有用户资料或已经计算的几何属性。
struct SeatLayoutItem: Equatable {
    /// 与数据源对应的稳定条目标识。
    let identifier: SeatCollectionItemID
    /// 客户端布局中的稳定位置标识。
    let slotID: SeatSlotID
    /// 麦位在所属房间中的零基位置。
    let position: SeatPosition
    /// 麦位所属房间，用于区分 PK 两侧。
    let roomSide: SeatRoomSide
    /// 决定麦位尺寸的客户端样式。
    let styleID: SeatVisualStyleID

    /// 创建几何无关的麦位描述。
    init(
        identifier: SeatCollectionItemID,
        slotID: SeatSlotID,
        position: SeatPosition,
        roomSide: SeatRoomSide,
        styleID: SeatVisualStyleID
    ) {
        self.identifier = identifier
        self.slotID = slotID
        self.position = position
        self.roomSide = roomSide
        self.styleID = styleID
    }

    /// 从展示条目提取布局所需的身份、位置及尺寸样式。
    init(item: SeatCollectionItem) {
        self.init(
            identifier: item.id,
            slotID: item.slot.slotID,
            position: item.slot.position,
            roomSide: item.slot.roomSide,
            styleID: item.slot.styleID
        )
    }
}

/// 单分区舞台的布局规则；条目数组同时定义稳定身份和显示顺序。
struct SeatLayoutSection: Equatable {
    /// 客户端布局标识，同时决定是否采用普通 RTL 镜像。
    let layoutID: SeatLayoutID
    /// 用于选择行列与主持麦排布算法的布局家族。
    let layoutFamily: SeatLayoutFamily
    /// 按数据源显示顺序排列的完整布局条目。
    let items: [SeatLayoutItem]
    /// 当前尺寸等级下的宽度、间距与外部舞台边距。
    let metrics: SeatLayoutMetrics

    /// 从有序条目派生的数据源标识，不另存可分歧的顺序。
    var itemIdentifiers: [SeatCollectionItemID] { items.map(\.identifier) }

    /// 创建分区规则；重复条目或位置标识属于调用方编程错误。
    init(
        layoutID: SeatLayoutID,
        layoutFamily: SeatLayoutFamily,
        items: [SeatLayoutItem],
        metrics: SeatLayoutMetrics
    ) {
        precondition(Set(items.map(\.identifier)).count == items.count, "Duplicate seat item identifier")
        precondition(Set(items.map(\.slotID)).count == items.count, "Duplicate seat slot identifier")
        self.layoutID = layoutID
        self.layoutFamily = layoutFamily
        self.items = items
        self.metrics = metrics
    }
}

/// Layout 提供给分区描述闭包的当前容器环境。
struct SeatLayoutEnvironment {
    /// 扣除 CollectionView 内容边距后的容器尺寸，单位为点。
    let effectiveContentSize: CGSize
    /// 当前有效的界面布局方向。
    let layoutDirection: UIUserInterfaceLayoutDirection
    /// 当前容器的系统特征，例如尺寸类与显示比例。
    let traitCollection: UITraitCollection
}

/// 返回指定分区的布局描述；当前舞台只请求分区 0，nil 表示空布局。
typealias SeatCollectionLayoutSectionProvider = (
    _ sectionIndex: Int,
    _ layoutEnvironment: SeatLayoutEnvironment
) -> SeatLayoutSection?

/// 根据分区描述和容器环境生成麦位属性的非滚动布局。
///
/// 分区提供者的输入变化后调用 invalidateLayout()。最终几何及转场端点由布局
/// 自身计算；属性查询始终通过当前数据源身份匹配几何，不缓存过期的 IndexPath。
final class SeatCollectionLayout: UICollectionViewLayout {
    private let sectionProvider: SeatCollectionLayoutSectionProvider
    private var needsGeometryUpdate = true
    private var cachedEnvironment: SeatLayoutEnvironment?
    private var currentSection: SeatLayoutSection?
    private var geometry = SeatCollectionGeometry.empty
    private var orderedIdentifiers: [SeatCollectionItemID] = []

    /// Stage 在数据源初始化后连接此查询；固定分区布局未连接时使用描述顺序。
    var itemIdentifierProvider: ((IndexPath) -> SeatCollectionItemID?)?

    @MainActor
    private struct Transition {
        let currentSection: SeatLayoutSection?
        let nextSection: SeatLayoutSection
        var currentGeometry = SeatCollectionGeometry.empty
        var nextGeometry = SeatCollectionGeometry.empty
    }
    private var transition: Transition?
    private var progress: CGFloat = 0

    /// 当前阶段应安装的数据源顺序；转场期间包括源与目标的条目并集。
    var itemIdentifiers: [SeatCollectionItemID] {
        updateGeometryIfNeeded()
        return orderedIdentifiers
    }

    /// 当前几何转场的完成比例；无转场时写入无效，有限数值限制在 0...1。
    var transitionProgress: CGFloat {
        get { progress }
        set {
            guard transition != nil, newValue.isFinite else { return }
            let value = min(1, max(0, newValue))
            guard value != progress else { return }
            progress = value
            // 进度不改变分区提供者的输入，UIKit 按新比例重新查询属性。
            super.invalidateLayout()
        }
    }

    /// 创建始终使用指定分区描述的布局。
    convenience init(section: SeatLayoutSection) {
        self.init(sectionProvider: { _, _ in section })
    }

    /// 创建在布局失效或环境变化时重新取得分区描述的布局。
    init(sectionProvider: @escaping SeatCollectionLayoutSectionProvider) {
        self.sectionProvider = sectionProvider
        super.init()
    }

    /// 从归档创建空布局；动态舞台使用分区提供者初始化器。
    required init?(coder: NSCoder) {
        sectionProvider = { _, _ in nil }
        super.init(coder: coder)
    }

    override func prepare() {
        super.prepare()
        updateGeometryIfNeeded()
    }

    override func invalidateLayout() {
        needsGeometryUpdate = true
        super.invalidateLayout()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        needsGeometryUpdate = true
        super.invalidateLayout(with: context)
    }

    override var collectionViewContentSize: CGSize {
        updateGeometryIfNeeded()
        guard let transition else { return geometry.contentSize }
        return CGSize(
            width: interpolate(transition.currentGeometry.contentSize.width, transition.nextGeometry.contentSize.width),
            height: interpolate(transition.currentGeometry.contentSize.height, transition.nextGeometry.contentSize.height)
        )
    }

    /// 测量目标分区，不改变当前提供者结果、布局缓存或转场进度。
    func sizeThatFits(
        _ size: CGSize,
        for section: SeatLayoutSection,
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> CGSize {
        SeatCollectionGeometry.resolve(
            section: section,
            environment: SeatLayoutEnvironment(
                effectiveContentSize: size,
                layoutDirection: layoutDirection,
                traitCollection: collectionView?.traitCollection ?? UITraitCollection()
            )
        ).contentSize
    }

    /// 安装转场两端描述，并以目标条目优先的并集顺序显示起点。
    func beginTransition(to section: SeatLayoutSection) {
        precondition(transition == nil, "Finish the current seat transition before starting another")
        updateGeometryIfNeeded()
        transition = Transition(currentSection: currentSection, nextSection: section)
        progress = 0
        invalidateLayout()
        updateGeometryIfNeeded()
    }

    /// 收敛至提供者的最新描述；宿主应先将提供者内容更新为目标状态。
    func finishTransition() {
        guard transition != nil else { return }
        transition = nil
        progress = 0
        invalidateLayout()
        updateGeometryIfNeeded()
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        updateGeometryIfNeeded()
        return (0..<currentItemCount).compactMap { item in
            let attributes = attributesForItem(at: IndexPath(item: item, section: 0))
            return attributes.flatMap { $0.frame.intersects(rect) ? $0 : nil }
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        updateGeometryIfNeeded()
        guard indexPath.section == 0, indexPath.item >= 0, indexPath.item < currentItemCount else { return nil }
        return attributesForItem(at: indexPath)
    }

    /// 每次查询都解析当前 Snapshot 身份；返回独立属性对象，避免 UIKit 修改几何缓存。
    private func attributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        /// 与数据源对应的稳定条目标识。
    let identifier: SeatCollectionItemID?
        if let itemIdentifierProvider {
            identifier = itemIdentifierProvider(indexPath)
        } else {
            identifier = orderedIdentifiers.indices.contains(indexPath.item) ? orderedIdentifiers[indexPath.item] : nil
        }
        guard let identifier else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        if let transition {
            let source = transition.currentGeometry.frames[identifier]
            let destination = transition.nextGeometry.frames[identifier]
            guard let start = source ?? destination, let end = destination ?? source else { return nil }
            attributes.frame = CGRect(
                x: interpolate(start.minX, end.minX), y: interpolate(start.minY, end.minY),
                width: interpolate(start.width, end.width), height: interpolate(start.height, end.height)
            )
            attributes.alpha = interpolate(source == nil ? 0 : 1, destination == nil ? 0 : 1)
            let scale = interpolate(source == nil ? 0.86 : 1, destination == nil ? 0.86 : 1)
            attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        } else {
            guard let frame = geometry.frames[identifier] else { return nil }
            attributes.frame = frame
        }
        attributes.zIndex = indexPath.item
        return attributes
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private var currentItemCount: Int {
        guard let collectionView, collectionView.numberOfSections > 0 else { return 0 }
        return collectionView.numberOfItems(inSection: 0)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }

    /// prepare 与查询共用更新入口；缓存不按瞬时 Snapshot 数量裁剪。
    private func updateGeometryIfNeeded() {
        let contentSize = collectionView.map {
            $0.bounds.inset(by: $0.adjustedContentInset).size
        } ?? .zero
        let environment = SeatLayoutEnvironment(
            effectiveContentSize: contentSize,
            layoutDirection: collectionView?.effectiveUserInterfaceLayoutDirection ?? .leftToRight,
            traitCollection: collectionView?.traitCollection ?? UITraitCollection()
        )
        let environmentChanged = cachedEnvironment.map {
            abs($0.effectiveContentSize.width - environment.effectiveContentSize.width) > 0.5
                || $0.layoutDirection != environment.layoutDirection
                || !$0.traitCollection.isEqual(environment.traitCollection)
        } ?? true
        guard needsGeometryUpdate || environmentChanged else { return }
        needsGeometryUpdate = false
        cachedEnvironment = environment
        if var transition {
            transition.currentGeometry = transition.currentSection.map {
                SeatCollectionGeometry.resolve(section: $0, environment: environment)
            } ?? .empty
            transition.nextGeometry = SeatCollectionGeometry.resolve(section: transition.nextSection, environment: environment)
            let destinationIDs = transition.nextSection.itemIdentifiers
            let destinationSet = Set(destinationIDs)
            orderedIdentifiers = destinationIDs + (transition.currentSection?.itemIdentifiers ?? []).filter {
                !destinationSet.contains($0)
            }
            self.transition = transition
        } else {
            let section = sectionProvider(0, environment)
            // 即使提供者仍返回源分区，结束转场也必须移除并集标识。
            orderedIdentifiers = section?.itemIdentifiers ?? []
            // 数据源内容刷新也会使 UIKit 失效；相同规则无需重算几何。
            guard section != currentSection || environmentChanged else { return }
            currentSection = section
            geometry = section.map {
                SeatCollectionGeometry.resolve(section: $0, environment: environment)
            } ?? .empty
        }
    }
}

/// Layout 内部的几何结果；业务容器只提交分区规则，不直接依赖此类型。
@MainActor
private struct SeatCollectionGeometry {
    let frames: [SeatCollectionItemID: CGRect]
    let contentSize: CGSize
    static let empty = Self(frames: [:], contentSize: .zero)

    static func resolve(section: SeatLayoutSection, environment: SeatLayoutEnvironment) -> Self {
        let metrics = section.metrics
        let availableWidth = max(0, environment.effectiveContentSize.width)
        let logicalFrames: [SeatCollectionItemID: CGRect]
        switch section.layoutFamily {
        case .partyGrid:
            logicalFrames = partyFrames(items: section.items, metrics: metrics, availableWidth: availableWidth)
        case .individualAudience:
            logicalFrames = individualFrames(items: section.items, metrics: metrics, availableWidth: availableWidth)
        case .pk:
            let geometry = RoomPKGeometry(width: availableWidth, sizeClass: metrics.sizeClass)
            logicalFrames = Dictionary(uniqueKeysWithValues: section.items.map { item in
                (item.identifier, geometry.frame(side: item.roomSide, position: item.position.rawValue))
            })
        }
        let frames = logicalFrames.mapValues { frame in
            if environment.layoutDirection == .rightToLeft && section.layoutID != .roomPKNine {
                return CGRect(x: availableWidth - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
            }
            return frame
        }
        return Self(frames: frames, contentSize: CGSize(width: availableWidth, height: frames.values.map(\.maxY).max() ?? 0))
    }

    /// 返回派对房主持麦与两排观众麦在舞台中的矩形。
    private static func partyFrames(
        items: [SeatLayoutItem],
        metrics: SeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [SeatCollectionItemID: CGRect] {
        let slots = items.sorted { $0.position < $1.position }
        guard let host = slots.first else { return [:] }

        let seatSize = SeatView.fittingSize(
            styleID: host.styleID,
            sizeClass: metrics.sizeClass,
            width: metrics.standardSeatWidth
        )
        var frames: [SeatCollectionItemID: CGRect] = [
            host.identifier: CGRect(
                x: (availableWidth - seatSize.width) / 2,
                y: 0,
                width: seatSize.width,
                height: seatSize.height
            ),
        ]
        let guestSlots = Array(slots.dropFirst())
        let rowCapacity = 4
        for (offset, slot) in slots.dropFirst().enumerated() {
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
            frames[slot.identifier] = CGRect(
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
        items: [SeatLayoutItem],
        metrics: SeatLayoutMetrics,
        availableWidth: CGFloat
    ) -> [SeatCollectionItemID: CGRect] {
        let slots = items.sorted { $0.position < $1.position }
        guard let host = slots.first else { return [:] }

        let hostSize = SeatView.fittingSize(
            styleID: host.styleID,
            sizeClass: metrics.sizeClass,
            width: metrics.emphasizedHostWidth
        )
        var frames: [SeatCollectionItemID: CGRect] = [
            host.identifier: CGRect(
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
            let seatSize = guestSizes[offset]
            frames[slot.identifier] = CGRect(
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
