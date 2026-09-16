//
//  SeatStageView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import OSLog
import QuickLayout
import QuickLayoutKit
import UIKit

/// 直播间麦位舞台容器。
///
/// 舞台使用不可滚动的 CollectionView 统一承载所有房型。业务 Presentation 只决定
/// Item 与客户端布局家族；具体 Frame 由 `SeatCollectionGeometry` 计算。
final class SeatStageView: TranslucentCardView {

    /// 一次尚未提交完成的舞台目标数据及过渡几何。
    private struct PendingTransition {
        /// 转场完成后提交的目标舞台展示状态。
        let destinationPresentation: SeatStagePresentation
        /// 转场完成后保留的目标集合条目。
        let destinationItems: [SeatCollectionItem]
        /// 仅包含目标条目的最终布局配置。
        let destinationConfiguration: SeatCollectionLayoutConfiguration
        /// 包含源与目标条目并集的动画终点配置。
        let destinationUnionConfiguration: SeatCollectionLayoutConfiguration
    }

    /// 记录当前组件诊断信息的日志记录器。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "VoiceRoomSeatStageView"
    )

    /// 按需创建的 PK 房间标记装饰视图。
    private lazy var pkDecoration = LazyView { [unowned self] in
        let view = RoomPKDecorationView()
        view.sizeClass = layoutMetrics.sizeClass
        view.alpha = pkDecorationAlpha
        return view
    }
    /// PK 装饰的不透明度；转场时与舞台状态同步更新。
    private var pkDecorationAlpha: CGFloat = 1 {
        didSet { pkDecoration.ifLoaded?.alpha = pkDecorationAlpha }
    }
    /// 为真实麦位单元格提供绝对几何位置的集合布局。
    private let seatLayout = SeatCollectionLayout()
    /// 负责内容条目展示和复用的集合视图。
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: seatLayout
    )
    /// 管理舞台条目标识、快照和单元格配置的数据源。
    private lazy var collectionDataSource = SeatCollectionDataSource(
        collectionView: collectionView,
        itemProvider: { [weak self] itemID in
            self?.itemsByID[itemID]
        },
        metricsProvider: { [weak self] in
            self?.layoutMetrics ?? .regular
        },
        seatDidSelect: { [weak self] assignment in
            self?.seatDidSelect?(assignment)
        }
    )

    /// 最近一次完成提交的舞台展示状态。
    private var currentPresentation: SeatStagePresentation?
    /// 最近一次完成提交的可见麦位条目。
    private var currentItems: [SeatCollectionItem] = []
    /// 以稳定条目标识索引的当前及转场目标数据。
    private var itemsByID: [
        SeatCollectionItemID: SeatCollectionItem
    ] = [:]
    /// 尚未完成的舞台转场；没有转场时为 `nil`。
    private var pendingTransition: PendingTransition?
    /// 根据当前舞台容器解析的尺寸与间距参数。
    private var layoutMetrics = SeatLayoutMetrics.regular
    /// 一个布尔值，指示外层页面是否要求采用紧凑高度布局。
    private var prefersCompactHeight = false
    /// 向外层布局报告的麦位集合高度，单位为点。
    private var collectionHeight: CGFloat = 0
    /// 上次几何解析采用的容器宽度，用于避免重复计算。
    private var lastLayoutWidth: CGFloat?
    /// 上次几何解析采用的界面布局方向。
    private var lastLayoutDirection: UIUserInterfaceLayoutDirection?

    /// 舞台高度或布局参数变化后请求宿主重新布局的回调。
    var layoutMetricsDidChange: (() -> Void)?
    /// 用户选择可交互麦位时调用的回调；参数为当前麦位绑定。
    var seatDidSelect: ((SeatAssignment) -> Void)?

    /// 测试与页面诊断使用；舞台本身仍不允许滚动。
    var seatCollectionView: UICollectionView { collectionView }

    /// 一个布尔值，指示当前舞台或转场目标是否需要显示 PK 装饰。
    private var showsPKDecoration: Bool {
        currentPresentation?.layoutID == .roomPKNine
            || pendingTransition?.destinationPresentation.layoutID == .roomPKNine
    }

    /// 待完成转场的目标条目中包含的用户标识集合；没有转场时为空。
    var transitioningUserIDs: Set<RoomUserID> {
        guard let pendingTransition else { return [] }
        return Set(
            pendingTransition.destinationItems.compactMap { item in
                if case let .user(userID) = item.id { return userID }
                return nil
            }
        )
    }

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 在舞台布局完成后检查容器环境并刷新集合布局。
    override func layoutSubviews() {
        updateLayoutEnvironmentIfNeeded()
        pkDecoration.ifLoaded?.sizeClass = layoutMetrics.sizeClass
        super.layoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    @LayoutBuilder
    override var body: Layout {
        ZStack {
            collectionView.resizable()
            if showsPKDecoration {
                pkDecoration.loadIfNeeded().resizable()
            }
        }
        .frame(height: collectionHeight)
        .padding(.horizontal, layoutMetrics.stageHorizontalPadding)
        .padding(.vertical, layoutMetrics.stageVerticalPadding)
    }

    /// 更新紧凑高度偏好并重新解析几何。
    ///
    /// - Returns: 偏好发生变化时为 `true`；无需更新时为 `false`。
    @discardableResult
    func setCompactPresentation(_ prefersCompactHeight: Bool) -> Bool {
        guard self.prefersCompactHeight != prefersCompactHeight else {
            return false
        }
        self.prefersCompactHeight = prefersCompactHeight
        updateLayoutEnvironmentIfNeeded(force: true)
        return true
    }

    /// 非动画提交已经过 Resolver 校验的舞台 Presentation。
    func apply(presentation: SeatStagePresentation) {
        if pendingTransition != nil {
            finishTransitionImmediately()
        }
        commit(presentation: presentation)
    }

    /// 合并不会改变 Item 身份和几何位置的数据更新。
    ///
    /// 动画中的分数、音频状态和用户资料只刷新目标内容，不中断 CollectionView
    /// 与公屏正在共享的时间线。
    func applyDataUpdate(presentation: SeatStagePresentation) {
        guard let pendingTransition else {
            commit(presentation: presentation)
            return
        }
        let destinationItems = makeItems(for: presentation)
        guard destinationItems.map(\.id)
            == pendingTransition.destinationItems.map(\.id)
        else {
            finishTransitionImmediately()
            commit(presentation: presentation)
            return
        }
        let destinationByID = Dictionary(
            uniqueKeysWithValues: destinationItems.map { ($0.id, $0) }
        )
        itemsByID.merge(destinationByID) { _, destination in destination }
        for item in destinationItems {
            collectionDataSource.cell(for: item.id)?.refresh(
                item: item,
                metrics: layoutMetrics
            )
        }
        self.pendingTransition = PendingTransition(
            destinationPresentation: presentation,
            destinationItems: destinationItems,
            destinationConfiguration: pendingTransition.destinationConfiguration,
            destinationUnionConfiguration: pendingTransition.destinationUnionConfiguration
        )
    }

    /// 准备真实麦位单元格的几何和内容转场。
    ///
    /// 准备阶段安装源与目标条目的并集，位置仍保持在起点，同时向外层报告目标高度以测量终点。宿主随后调用 `animatePreparedTransition()`，并在结束时调用 `completePreparedTransition()`。
    ///
    /// - Parameter presentation: 已经布局解析器校验的目标舞台。
    /// - Returns: 已准备可播放的转场时为 `true`；首次提交直接显示目标并返回 `false`。
    @discardableResult
    func prepareTransition(
        to presentation: SeatStagePresentation
    ) -> Bool {
        guard let sourcePresentation = currentPresentation else {
            commit(presentation: presentation)
            return false
        }
        if pendingTransition != nil {
            finishTransitionImmediately()
        }

        let sourceItems = currentItems
        let destinationItems = makeItems(for: presentation)
        let sourceConfiguration = makeConfiguration(
            presentation: sourcePresentation,
            items: sourceItems
        )
        let destinationConfiguration = makeConfiguration(
            presentation: presentation,
            items: destinationItems
        )
        let sourceByID = Dictionary(
            uniqueKeysWithValues: sourceItems.map { ($0.id, $0) }
        )
        let destinationByID = Dictionary(
            uniqueKeysWithValues: destinationItems.map { ($0.id, $0) }
        )
        // 过渡期间保留即将移除的真实 Cell，让离场与进场共享同一条动画时间线。
        let unionIDs = destinationItems.map(\.id) + sourceItems.map(\.id).filter {
            destinationByID[$0] == nil
        }
        let sourceUnion = unionConfiguration(
            itemIDs: unionIDs,
            primary: sourceConfiguration,
            secondary: destinationConfiguration
        )
        let destinationUnion = unionConfiguration(
            itemIDs: unionIDs,
            primary: destinationConfiguration,
            secondary: sourceConfiguration
        )

        itemsByID = sourceByID.merging(destinationByID) { _, destination in
            destination
        }
        seatLayout.apply(sourceUnion)
        collectionDataSource.applySnapshot(itemIDs: unionIDs)
        collectionView.layoutIfNeeded()

        let sharedIDs = Set(sourceItems.map(\.id))
            .intersection(destinationItems.map(\.id))
        for itemID in sharedIDs {
            guard
                let item = destinationByID[itemID],
                let cell = collectionDataSource.cell(for: itemID)
            else { continue }
            cell.prepareTransition(to: item, metrics: layoutMetrics)
        }

        pkDecorationAlpha = sourcePresentation.layoutID == .roomPKNine ? 1 : 0
        pendingTransition = PendingTransition(
            destinationPresentation: presentation,
            destinationItems: destinationItems,
            destinationConfiguration: destinationConfiguration,
            destinationUnionConfiguration: destinationUnion
        )
        setNeedsQuickLayout()
        updateCollectionHeight(
            destinationConfiguration.contentSize.height,
            notify: true
        )
        setSeatInteractionEnabled(false)
        accessibilityElementsHidden = true
        return true
    }

    /// 在外层 `UIViewPropertyAnimator` 的动画闭包中提交目标布局。
    func animatePreparedTransition() {
        guard let pendingTransition else { return }
        pkDecorationAlpha = pendingTransition.destinationPresentation.layoutID == .roomPKNine ? 1 : 0
        seatLayout.apply(pendingTransition.destinationUnionConfiguration)
        collectionView.layoutIfNeeded()
        collectionView.visibleCells
            .compactMap { $0 as? SeatCollectionCell }
            .forEach { $0.animateToDestination() }
    }

    /// 收敛过渡并移除 source-only Item。
    func completePreparedTransition() {
        guard let pendingTransition else { return }
        collectionView.visibleCells
            .compactMap { $0 as? SeatCollectionCell }
            .forEach { $0.completeTransition() }
        currentPresentation = pendingTransition.destinationPresentation
        currentItems = pendingTransition.destinationItems
        itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        seatLayout.apply(pendingTransition.destinationConfiguration)
        collectionDataSource.applySnapshot(itemIDs: currentItems.map(\.id))
        self.pendingTransition = nil
        setNeedsQuickLayout()
        setSeatInteractionEnabled(true)
        accessibilityElementsHidden = false
        updateAccessibilityElements()
        collectionView.layoutIfNeeded()
    }

    /// 立即提交当前过渡的最终合法 Presentation。
    func finishTransitionImmediately() {
        guard pendingTransition != nil else { return }
        UIView.performWithoutAnimation {
            animatePreparedTransition()
            completePreparedTransition()
            layoutIfNeeded()
        }
    }

    /// 统一设置麦位集合视图是否接受用户操作。
    func setSeatInteractionEnabled(_ isEnabled: Bool) {
        collectionView.isUserInteractionEnabled = isEnabled
    }

    /// 返回用户当前可见 Cell 的实时送礼动画锚点。
    func giftTargetPoint(
        forUserID userID: RoomUserID,
        in view: UIView
    ) -> CGPoint? {
        let itemID = SeatCollectionItemID.user(userID)
        guard let cell = collectionDataSource.cell(for: itemID) else {
            Self.logger.notice(
                "Gift target disappeared for user \(userID.rawValue, privacy: .public)."
            )
            return nil
        }
        return cell.giftTargetPoint(in: view)
    }

    /// 在指定用户当前可见的麦位上播放抵达反馈；用户已不可见时跳过。
    func playGiftArrival(
        forUserID userID: RoomUserID,
        gift: Gift,
        color: UIColor,
        style: GiftEffectStyle? = nil
    ) {
        let itemID = SeatCollectionItemID.user(userID)
        guard let cell = collectionDataSource.cell(for: itemID) else {
            Self.logger.notice(
                "Skipped gift arrival for missing user \(userID.rawValue, privacy: .public)."
            )
            return
        }
        cell.playGiftArrival(gift: gift, color: color, style: style)
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        accessibilityIdentifier = "liveRoom.seat.stage"
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.alwaysBounceVertical = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.isPrefetchingEnabled = false
        collectionView.accessibilityIdentifier = "liveRoom.seat.collection"
        _ = collectionDataSource
    }

    /// 提交完整舞台数据、几何配置和非动画集合快照，并刷新辅助功能顺序。
    private func commit(presentation: SeatStagePresentation) {
        pkDecoration.ifLoaded?.reloadLocalizedContent()
        pkDecorationAlpha = 1
        let items = makeItems(for: presentation)
        let configuration = makeConfiguration(
            presentation: presentation,
            items: items
        )
        currentPresentation = presentation
        currentItems = items
        itemsByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        seatLayout.apply(configuration)
        collectionDataSource.applySnapshot(
            itemIDs: items.map(\.id),
            reconfigureExisting: true
        )
        updateCollectionHeight(configuration.contentSize.height, notify: true)
        accessibilityValue = String(items.count)
        setNeedsQuickLayout()
        collectionView.layoutIfNeeded()
        updateAccessibilityElements()
    }

    /// 将当前可见麦位转换为使用稳定用户或空位标识的集合条目。
    private func makeItems(
        for presentation: SeatStagePresentation
    ) -> [SeatCollectionItem] {
        presentation.visibleSlots
            .sorted { $0.address < $1.address }
            .map(SeatCollectionItem.init)
    }

    /// 结合当前尺寸参数、容器宽度和布局方向计算舞台几何配置。
    private func makeConfiguration(
        presentation: SeatStagePresentation,
        items: [SeatCollectionItem]
    ) -> SeatCollectionLayoutConfiguration {
        let availableWidth = max(
            0,
            bounds.width - layoutMetrics.stageHorizontalPadding * 2
        )
        return SeatCollectionGeometry.configuration(
            presentation: presentation,
            items: items,
            metrics: layoutMetrics,
            availableWidth: availableWidth,
            direction: effectiveUserInterfaceLayoutDirection
        )
    }

    /// 合并源与目标条目几何，为仅在另一端存在的条目提供透明缩小状态。
    private func unionConfiguration(
        itemIDs: [SeatCollectionItemID],
        primary: SeatCollectionLayoutConfiguration,
        secondary: SeatCollectionLayoutConfiguration
    ) -> SeatCollectionLayoutConfiguration {
        var states: [
            SeatCollectionItemID: SeatCollectionLayoutState
        ] = [:]
        for itemID in itemIDs {
            if let state = primary.states[itemID] {
                states[itemID] = state
            // 仅在另一端存在的条目保留几何位置，以透明和缩小状态参与入场或离场。
            } else if let fallback = secondary.states[itemID] {
                states[itemID] = SeatCollectionLayoutState(
                    frame: fallback.frame,
                    alpha: 0,
                    transform: CGAffineTransform(scaleX: 0.86, y: 0.86)
                )
            }
        }
        return SeatCollectionLayoutConfiguration(
            itemIDs: itemIDs,
            states: states,
            contentSize: primary.contentSize
        )
    }

    /// 在宽度、方向或尺寸参数变化时结束旧转场并重新提交布局。
    private func updateLayoutEnvironmentIfNeeded(force: Bool = false) {
        let layoutWidth = bounds.width
        let resolvedMetrics = SeatLayoutMetrics.resolve(
            availableWidth: layoutWidth,
            prefersCompactHeight: prefersCompactHeight
        )
        let direction = effectiveUserInterfaceLayoutDirection
        let widthChanged = lastLayoutWidth.map {
            abs($0 - layoutWidth) > 0.5
        } ?? true
        guard force
            || widthChanged
            || layoutMetrics != resolvedMetrics
            || lastLayoutDirection != direction
        else { return }
        if pendingTransition != nil {
            finishTransitionImmediately()
        }
        layoutMetrics = resolvedMetrics
        lastLayoutWidth = layoutWidth
        lastLayoutDirection = direction
        guard let currentPresentation else { return }
        let configuration = makeConfiguration(
            presentation: currentPresentation,
            items: currentItems
        )
        itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        seatLayout.apply(configuration)
        collectionDataSource.applySnapshot(
            itemIDs: currentItems.map(\.id),
            reconfigureExisting: true
        )
        updateCollectionHeight(configuration.contentSize.height, notify: true)
        setNeedsQuickLayout()
    }

    /// 在高度变化超过半点时更新舞台布局，并按需通知宿主。
    private func updateCollectionHeight(_ height: CGFloat, notify: Bool) {
        // 忽略亚像素测量抖动，避免宿主布局和集合高度相互触发无效刷新。
        guard abs(collectionHeight - height) > 0.5 else { return }
        collectionHeight = height
        setNeedsQuickLayout()
        if notify {
            layoutMetricsDidChange?()
        }
    }

    /// 按舞台条目顺序重建辅助功能可访问的单元格列表。
    private func updateAccessibilityElements() {
        collectionView.layoutIfNeeded()
        accessibilityElements = currentItems.compactMap { item in
            collectionDataSource.cell(for: item.id)
        }
    }
}

#if DEBUG
/// 创建展示指定房型和观众席状态的麦位舞台的预览控制器。
@MainActor
private func makeSeatStagePreview(
    mode: RoomMode,
    audienceState: AudienceSeatState
) -> UIViewController {
    let view = SeatStageView()
    let snapshot = VoiceRoomViewModel.makeDefaultStageSnapshot(
        roomMode: mode,
        audienceSeatState: audienceState
    )
    if case let .success(presentation) = SeatLayoutResolver.resolve(
        snapshot: snapshot
    ) {
        view.apply(presentation: presentation)
    }
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view.resizable(axis: .horizontal).padding(16)
        }
    }
}

@available(iOS 17.0, *)
#Preview("派对九麦舞台") {
    makeSeatStagePreview(
        mode: .party,
        audienceState: .enabled
    )
}

@available(iOS 17.0, *)
#Preview("个播收起舞台") {
    makeSeatStagePreview(
        mode: .individual,
        audienceState: .disabled
    )
}

@available(iOS 17.0, *)
#Preview("个播五麦舞台") {
    makeSeatStagePreview(
        mode: .individual,
        audienceState: .enabled
    )
}
@available(iOS 17.0, *)
#Preview("厅 PK 双房舞台") {
    makeSeatStagePreview(mode: .pk(styleID: "room.nine"), audienceState: .enabled)
}
#endif
