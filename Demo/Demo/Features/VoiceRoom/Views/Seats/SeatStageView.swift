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
/// Item 与客户端布局家族；具体 Frame 由 `SeatCollectionLayout` 根据容器环境计算。
final class SeatStageView: TranslucentCardView {

    /// 记录当前组件诊断信息的日志记录器。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "VoiceRoomSeatStageView"
    )

    /// 按需创建的 PK 房间标记装饰视图。
    private lazy var pkDecoration = LazyView { [unowned self] in
        let view = RoomPKDecorationView()
        view.sizeClass = layoutMetrics.sizeClass
        return view
    }
    /// 提交中的布局描述独立于 Cell 内容，确保相同身份的几何在 batch update 内才变化。
    private var layoutSection: SeatLayoutSection?
    private lazy var seatLayout = SeatCollectionLayout { [weak self] _, _ in
        self?.layoutSection
    }
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

    /// 当前 Snapshot 对应的舞台展示状态。
    private var currentPresentation: SeatStagePresentation?
    /// 当前 Snapshot 对应的可见麦位条目。
    private var currentItems: [SeatCollectionItem] = []
    /// 以稳定条目标识索引的当前及转场目标数据。
    private var itemsByID: [
        SeatCollectionItemID: SeatCollectionItem
    ] = [:]
    /// 原生更新串行运行；期间仅保留最新目标，不积累房型切换队列。
    private(set) var isApplyingUpdate = false
    private var pendingPresentation: SeatStagePresentation?
    private var updateGeneration = 0
    private var settlesImmediately = false
    private var needsEnvironmentUpdate = false
    private var savedClipping: (stage: Bool, collection: Bool)?
    /// 默认读取系统设置，允许测试覆盖减少动态效果路径。
    var isReduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled }
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

    private var showsPKDecoration: Bool {
        currentPresentation?.layoutID == .roomPKNine
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
        // QuickLayout 在 super 中同步父容器方向；再检查一次，避免沿用上一帧的方向。
        updateLayoutEnvironmentIfNeeded()
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

    /// 提交完整展示状态。Layout 自主管理麦位动画；外围高度及 PK 装饰立即更新。
    func apply(presentation: SeatStagePresentation, animated: Bool = false) {
        if isApplyingUpdate {
            if pendingPresentation == nil,
               !SeatTransitionDescriptor(from: currentPresentation, to: presentation).requiresTransition {
                refreshContent(presentation)
            } else {
                pendingPresentation = presentation
            }
            return
        }
        let geometryChanged = SeatTransitionDescriptor(from: currentPresentation, to: presentation).requiresTransition
        if currentPresentation != nil, !geometryChanged {
            refreshContent(presentation)
            return
        }
        submit(presentation, animated: animated && geometryChanged)
    }

    private func refreshContent(_ presentation: SeatStagePresentation) {
        currentPresentation = presentation
        currentItems = makeItems(for: presentation)
        itemsByID = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0) })
        for item in currentItems {
            collectionDataSource.cell(for: item.id)?.refresh(item: item, metrics: layoutMetrics)
        }
        pkDecoration.ifLoaded?.reloadLocalizedContent()
    }

    private var isVisibleForAnimation: Bool {
        guard window != nil else { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0 { return false }
            ancestor = view.superview
        }
        return true
    }

    private func submit(_ presentation: SeatStagePresentation, animated: Bool) {
        collectionView.layoutIfNeeded()
        seatLayout.finishUpdates()
        let oldIDs = currentItems.map(\.id)
        let items = makeItems(for: presentation)
        let section = makeSection(presentation: presentation, items: items)
        let canAnimate = animated && isVisibleForAnimation && UIView.areAnimationsEnabled
            && !isReduceMotionEnabled() && collectionView.bounds.width > 0
        currentPresentation = presentation
        currentItems = items
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        pkDecoration.ifLoaded?.reloadLocalizedContent()
        isApplyingUpdate = true
        settlesImmediately = !canAnimate
        updateGeneration &+= 1
        let generation = updateGeneration
        if canAnimate {
            savedClipping = (clipsToBounds, collectionView.clipsToBounds)
            clipsToBounds = false
            collectionView.clipsToBounds = false
            collectionView.isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }
        let completion: () -> Void = { [weak self] in
            self?.completeUpdate(generation: generation)
        }
        if oldIDs == section.itemIdentifiers {
            // reconfigure 不会动画自定义布局的尺寸；先更新内容，再单独提交几何。
            collectionDataSource.applySnapshot(itemIDs: oldIDs, reconfigureExisting: true) { [weak self] in
                guard let self, updateGeneration == generation else { return }
                collectionView.layoutIfNeeded()
                seatLayout.finishUpdates()
                let changes = { [self] in
                    seatLayout.invalidateLayout()
                    layoutSection = section
                }
                if canAnimate && !settlesImmediately {
                    collectionView.performBatchUpdates(changes) { _ in completion() }
                } else {
                    UIView.performWithoutAnimation {
                        changes()
                        collectionView.layoutIfNeeded()
                    }
                    completion()
                }
            }
        } else {
            // 由 Snapshot 的 UIKit 失效回调捕获旧几何；提前失效会在更新开始前丢掉退出 Cell。
            layoutSection = section
            collectionDataSource.applySnapshot(
                itemIDs: section.itemIdentifiers,
                reconfigureExisting: true,
                animated: canAnimate,
                completion: completion
            )
        }
        // 即使 UIKit 的 completion 同步调用，也只能发布当前状态的外围布局。
        if updateGeneration == generation {
            let currentSection = makeSection(presentation: presentation, items: currentItems)
            updateCollectionHeight(measuredHeight(for: currentSection), notify: true)
            accessibilityValue = String(currentItems.count)
            setNeedsQuickLayout()
        }
    }

    private func completeUpdate(generation: Int) {
        guard generation == updateGeneration, isApplyingUpdate else { return }
        collectionView.layoutIfNeeded()
        seatLayout.finishUpdates()
        isApplyingUpdate = false
        if let savedClipping {
            clipsToBounds = savedClipping.stage
            collectionView.clipsToBounds = savedClipping.collection
            self.savedClipping = nil
        }
        collectionView.isUserInteractionEnabled = true
        accessibilityElementsHidden = false
        updateAccessibilityElements()
        if needsEnvironmentUpdate {
            needsEnvironmentUpdate = false
            updateLayoutEnvironmentIfNeeded(force: true)
        }
        if let pending = pendingPresentation {
            pendingPresentation = nil
            apply(presentation: pending, animated: false)
        }
    }

    /// 停止可见动画；等待 UIKit 当前事务完成后才提交最新目标，避免重入 Snapshot。
    func finishUpdatesImmediately() {
        guard isApplyingUpdate else { return }
        settlesImmediately = true
        func removeAnimations(in view: UIView) {
            // 保留说话波形等循环动画，只结束当前 UIKit 几何动画。
            for key in view.layer.animationKeys() ?? [] {
                guard let animation = view.layer.animation(forKey: key) as? CAPropertyAnimation,
                      animation.repeatCount == 0, animation.repeatDuration == 0,
                      let property = animation.keyPath?.split(separator: ".").first,
                      ["position", "bounds", "transform", "opacity"].contains(String(property)) else { continue }
                view.layer.removeAnimation(forKey: key)
            }
            view.subviews.forEach { removeAnimations(in: $0) }
        }
        removeAnimations(in: collectionView)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishUpdatesImmediately() }
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
        let dataSource = collectionDataSource
        seatLayout.itemIdentifierProvider = { [weak dataSource] indexPath in
            dataSource?.itemIdentifier(for: indexPath)
        }
    }

    /// 将当前可见麦位转换为使用稳定用户或空位标识的集合条目。
    private func makeItems(
        for presentation: SeatStagePresentation
    ) -> [SeatCollectionItem] {
        presentation.visibleSlots
            .sorted { $0.address < $1.address }
            .map(SeatCollectionItem.init)
    }

    /// 将展示数据投影为分区规则；Frame 和转场属性由 Layout 生成。
    private func makeSection(
        presentation: SeatStagePresentation,
        items: [SeatCollectionItem]
    ) -> SeatLayoutSection {
        SeatLayoutSection(
            layoutID: presentation.layoutID,
            layoutFamily: presentation.layoutFamily,
            items: items.map(SeatLayoutItem.init),
            metrics: layoutMetrics
        )
    }

    /// 测量目标高度，供舞台和公屏立即更新外层布局。
    private func measuredHeight(for section: SeatLayoutSection) -> CGFloat {
        seatLayout.sizeThatFits(
            CGSize(width: max(0, bounds.width - layoutMetrics.stageHorizontalPadding * 2), height: 0),
            for: section,
            layoutDirection: effectiveUserInterfaceLayoutDirection
        ).height
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
        if isApplyingUpdate {
            needsEnvironmentUpdate = true
            finishUpdatesImmediately()
            return
        }
        layoutMetrics = resolvedMetrics
        lastLayoutWidth = layoutWidth
        lastLayoutDirection = direction
        collectionView.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        guard let currentPresentation else { return }
        let section = makeSection(
            presentation: currentPresentation,
            items: currentItems
        )
        itemsByID = Dictionary(
            uniqueKeysWithValues: currentItems.map { ($0.id, $0) }
        )
        seatLayout.invalidateLayout()
        layoutSection = section
        for item in currentItems {
            collectionDataSource.cell(for: item.id)?.refresh(item: item, metrics: layoutMetrics)
        }
        collectionView.layoutIfNeeded()
        seatLayout.finishUpdates()
        updateCollectionHeight(measuredHeight(for: section), notify: true)
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
