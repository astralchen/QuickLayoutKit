//
//  LiveRoomSeatStageView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import OSLog
import QuickLayout
import QuickLayoutKit
import UIKit

/// 直播间麦位舞台容器。
///
/// 舞台使用不可滚动的 CollectionView 统一承载所有房型。业务 Presentation 只决定
/// Item 与客户端布局家族；具体 Frame 由 `LiveRoomSeatCollectionGeometry` 计算。
final class LiveRoomSeatStageView: LiveRoomCardView {

    private struct PendingTransition {
        let destinationPresentation: LiveRoomSeatStagePresentation
        let destinationItems: [LiveRoomSeatCollectionItem]
        let destinationConfiguration: LiveRoomSeatCollectionLayoutConfiguration
        let destinationUnionConfiguration: LiveRoomSeatCollectionLayoutConfiguration
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "LiveRoomSeatStageView"
    )

    private let seatLayout = LiveRoomSeatCollectionLayout()
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: seatLayout
    )
    private lazy var collectionDataSource = LiveRoomSeatCollectionDataSource(
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

    private var currentPresentation: LiveRoomSeatStagePresentation?
    private var currentItems: [LiveRoomSeatCollectionItem] = []
    private var itemsByID: [
        LiveRoomSeatCollectionItemID: LiveRoomSeatCollectionItem
    ] = [:]
    private var pendingTransition: PendingTransition?
    private var frozenSourceConfiguration: LiveRoomSeatCollectionLayoutConfiguration?
    private var layoutMetrics = LiveRoomSeatLayoutMetrics.regular
    private var prefersCompactHeight = false
    private var collectionHeight: CGFloat = 0
    private var lastLayoutDirection: UIUserInterfaceLayoutDirection?

    var layoutMetricsDidChange: (() -> Void)?
    var seatDidSelect: ((LiveRoomSeatAssignment) -> Void)?

    /// 测试与页面诊断使用；舞台本身仍不允许滚动。
    var seatCollectionView: UICollectionView { collectionView }

    var transitioningUserIDs: Set<LiveRoomUserID> {
        guard let pendingTransition else { return [] }
        return Set(
            pendingTransition.destinationItems.compactMap { item in
                if case let .user(userID) = item.id { return userID }
                return nil
            }
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func layoutSubviews() {
        updateLayoutEnvironmentIfNeeded()
        super.layoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    @LayoutBuilder
    override var body: Layout {
        collectionView
            .resizable(axis: .horizontal)
            .frame(height: collectionHeight)
            .padding(.horizontal, layoutMetrics.stageHorizontalPadding)
            .padding(.vertical, layoutMetrics.stageVerticalPadding)
    }

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
    func apply(presentation: LiveRoomSeatStagePresentation) {
        if pendingTransition != nil {
            finishTransitionImmediately()
        }
        commit(presentation: presentation)
    }

    /// 合并不会改变 Item 身份和几何位置的数据更新。
    ///
    /// 动画中的分数、音频状态和用户资料只刷新目标内容，不中断 CollectionView
    /// 与公屏正在共享的时间线。
    func applyDataUpdate(presentation: LiveRoomSeatStagePresentation) {
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

    /// 为场景级 Coordinator 准备一段真实 Cell 的几何过渡。
    ///
    /// 准备阶段会安装 source/destination Item 并集，但 Collection Layout 仍停在
    /// source Frame；同时舞台向 QuickLayout 报告目标高度，供 Controller 测量终点。
    @discardableResult
    func prepareTransition(
        to presentation: LiveRoomSeatStagePresentation
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
        let sourceConfiguration = frozenSourceConfiguration
            ?? makeConfiguration(
                presentation: sourcePresentation,
                items: sourceItems
            )
        frozenSourceConfiguration = nil
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

        pendingTransition = PendingTransition(
            destinationPresentation: presentation,
            destinationItems: destinationItems,
            destinationConfiguration: destinationConfiguration,
            destinationUnionConfiguration: destinationUnion
        )
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
        seatLayout.apply(pendingTransition.destinationUnionConfiguration)
        collectionView.layoutIfNeeded()
        collectionView.visibleCells
            .compactMap { $0 as? LiveRoomSeatCollectionCell }
            .forEach { $0.animateToDestination() }
    }

    /// 收敛过渡并移除 source-only Item。
    func completePreparedTransition() {
        guard let pendingTransition else { return }
        collectionView.visibleCells
            .compactMap { $0 as? LiveRoomSeatCollectionCell }
            .forEach { $0.completeTransition() }
        currentPresentation = pendingTransition.destinationPresentation
        currentItems = pendingTransition.destinationItems
        itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        seatLayout.apply(pendingTransition.destinationConfiguration)
        collectionDataSource.applySnapshot(itemIDs: currentItems.map(\.id))
        self.pendingTransition = nil
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

    /// 将被替换动画的 presentation frame 冻结成下一段动画的 source 几何。
    ///
    /// 中断时只保留最新合法 Presentation 的 Item；已离场的旧 Item 立即清理，仍在
    /// 场用户的 Cell Frame 和透明度从 presentation layer 连续承接。
    func freezeTransitionAtCurrentPresentation() {
        guard let pendingTransition else { return }
        collectionView.layoutIfNeeded()
        let destinationIDs = pendingTransition.destinationItems.map(\.id)
        var states: [
            LiveRoomSeatCollectionItemID: LiveRoomSeatCollectionLayoutState
        ] = [:]
        for itemID in destinationIDs {
            guard let cell = collectionDataSource.cell(for: itemID) else {
                if let fallback = pendingTransition
                    .destinationConfiguration.states[itemID] {
                    states[itemID] = fallback
                }
                continue
            }
            let presentationLayer = cell.layer.presentation() ?? cell.layer
            states[itemID] = LiveRoomSeatCollectionLayoutState(
                frame: presentationLayer.frame,
                alpha: CGFloat(presentationLayer.opacity)
            )
        }

        collectionView.visibleCells
            .compactMap { $0 as? LiveRoomSeatCollectionCell }
            .forEach {
                $0.layer.removeAllAnimations()
                $0.completeTransition()
            }
        currentPresentation = pendingTransition.destinationPresentation
        currentItems = pendingTransition.destinationItems
        itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        let frozenConfiguration = LiveRoomSeatCollectionLayoutConfiguration(
            itemIDs: destinationIDs,
            states: states,
            contentSize: pendingTransition.destinationConfiguration.contentSize
        )
        seatLayout.apply(frozenConfiguration)
        collectionDataSource.applySnapshot(itemIDs: destinationIDs)
        self.pendingTransition = nil
        frozenSourceConfiguration = frozenConfiguration
        accessibilityElementsHidden = false
        setSeatInteractionEnabled(true)
        UIView.performWithoutAnimation {
            collectionView.layoutIfNeeded()
        }
        updateAccessibilityElements()
    }

    func setSeatInteractionEnabled(_ isEnabled: Bool) {
        collectionView.isUserInteractionEnabled = isEnabled
    }

    /// 返回用户当前可见 Cell 的实时送礼动画锚点。
    func giftTargetPoint(
        forUserID userID: LiveRoomUserID,
        in view: UIView
    ) -> CGPoint? {
        let itemID = LiveRoomSeatCollectionItemID.user(userID)
        guard let cell = collectionDataSource.cell(for: itemID) else {
            Self.logger.notice(
                "Gift target disappeared for user \(userID.rawValue, privacy: .public)."
            )
            return nil
        }
        return cell.giftTargetPoint(in: view)
    }

    func playGiftArrival(
        forUserID userID: LiveRoomUserID,
        gift: LiveRoomGift,
        color: UIColor
    ) {
        let itemID = LiveRoomSeatCollectionItemID.user(userID)
        guard let cell = collectionDataSource.cell(for: itemID) else {
            Self.logger.notice(
                "Skipped gift arrival for missing user \(userID.rawValue, privacy: .public)."
            )
            return
        }
        cell.playGiftArrival(gift: gift, color: color)
    }

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

    private func commit(presentation: LiveRoomSeatStagePresentation) {
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

    private func makeItems(
        for presentation: LiveRoomSeatStagePresentation
    ) -> [LiveRoomSeatCollectionItem] {
        presentation.visibleSlots
            .sorted { $0.position < $1.position }
            .map(LiveRoomSeatCollectionItem.init)
    }

    private func makeConfiguration(
        presentation: LiveRoomSeatStagePresentation,
        items: [LiveRoomSeatCollectionItem]
    ) -> LiveRoomSeatCollectionLayoutConfiguration {
        let availableWidth = max(
            0,
            bounds.width - layoutMetrics.stageHorizontalPadding * 2
        )
        return LiveRoomSeatCollectionGeometry.configuration(
            presentation: presentation,
            items: items,
            metrics: layoutMetrics,
            availableWidth: availableWidth,
            direction: effectiveUserInterfaceLayoutDirection
        )
    }

    private func unionConfiguration(
        itemIDs: [LiveRoomSeatCollectionItemID],
        primary: LiveRoomSeatCollectionLayoutConfiguration,
        secondary: LiveRoomSeatCollectionLayoutConfiguration
    ) -> LiveRoomSeatCollectionLayoutConfiguration {
        var states: [
            LiveRoomSeatCollectionItemID: LiveRoomSeatCollectionLayoutState
        ] = [:]
        for itemID in itemIDs {
            if let state = primary.states[itemID] {
                states[itemID] = state
            } else if let fallback = secondary.states[itemID] {
                states[itemID] = LiveRoomSeatCollectionLayoutState(
                    frame: fallback.frame,
                    alpha: 0,
                    transform: CGAffineTransform(scaleX: 0.86, y: 0.86)
                )
            }
        }
        return LiveRoomSeatCollectionLayoutConfiguration(
            itemIDs: itemIDs,
            states: states,
            contentSize: primary.contentSize
        )
    }

    private func updateLayoutEnvironmentIfNeeded(force: Bool = false) {
        let resolvedMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: bounds.width,
            prefersCompactHeight: prefersCompactHeight
        )
        let direction = effectiveUserInterfaceLayoutDirection
        guard force
            || layoutMetrics != resolvedMetrics
            || lastLayoutDirection != direction
        else { return }
        if pendingTransition != nil {
            finishTransitionImmediately()
        }
        layoutMetrics = resolvedMetrics
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

    private func updateCollectionHeight(_ height: CGFloat, notify: Bool) {
        guard abs(collectionHeight - height) > 0.5 else { return }
        collectionHeight = height
        setNeedsQuickLayout()
        if notify {
            layoutMetricsDidChange?()
        }
    }

    private func updateAccessibilityElements() {
        collectionView.layoutIfNeeded()
        accessibilityElements = currentItems.compactMap { item in
            collectionDataSource.cell(for: item.id)
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomSeatStagePreview(
    mode: LiveRoomBusinessMode,
    audienceState: LiveRoomAudienceSeatState,
    size: CGSize
) -> UIViewController {
    let view = LiveRoomSeatStageView()
    let snapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
        businessMode: mode,
        audienceSeatState: audienceState
    )
    if case let .success(presentation) = LiveRoomSeatLayoutResolver.resolve(
        snapshot: snapshot
    ) {
        view.apply(presentation: presentation)
    }
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: size.width, height: size.height)
    }
}

#Preview("派对九麦舞台") {
    makeLiveRoomSeatStagePreview(
        mode: .party,
        audienceState: .enabled,
        size: CGSize(width: 390, height: 520)
    )
}

#Preview("个播收起舞台") {
    makeLiveRoomSeatStagePreview(
        mode: .individual,
        audienceState: .disabled,
        size: CGSize(width: 390, height: 260)
    )
}

#Preview("个播五麦舞台") {
    makeLiveRoomSeatStagePreview(
        mode: .individual,
        audienceState: .enabled,
        size: CGSize(width: 390, height: 420)
    )
}
#endif
