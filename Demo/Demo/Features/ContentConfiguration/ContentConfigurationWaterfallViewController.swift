import OSLog
import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class ContentConfigurationWaterfallViewController: LocalizedQuickLayoutHostingController, UICollectionViewDelegate {
    private static let logger = Logger(subsystem: "Demo.ContentConfiguration", category: "ContentConfigurationWaterfallViewController")

    override var localizedTitleKey: String? { "demo.contentConfiguration.waterfall.title" }

    private(set) var collectionView: UICollectionView!
    private(set) lazy var waterfallLayout = UICollectionViewWaterfallLayout(sectionProvider: { [weak self] _, environment in
        self?.makeSection(environment: environment)
    })
    private(set) var items: [ContentConfigurationWaterfallItem] = []
    var laneCount: Int { waterfallLayout.resolvedLaneCount(in: 0) ?? 0 }
    private let directionControl = WaterfallDirectionControl(items: ["", ""])
    private let laneCountLabel = LocalizedLabel()
    private let controlsBackground: UIVisualEffectView = {
        if #available(iOS 26.0, *) {
            let background = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            background.cornerConfiguration = .uniformCorners(radius: .fixed(0))
            return background
        }
        return UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    }()
    private var pendingScrollAnchorID: Int?
    private let localizer: Localizer
    private var currentDirection: UIUserInterfaceLayoutDirection = .leftToRight
    private var renderGeneration = 0
    private(set) var snapshotApplicationCount = 0
    private var isApplyingSnapshot = false
    private var pendingRenderReason: String?
    var itemLengthDimension: NSCollectionLayoutDimension = .estimated(240) {
        didSet { waterfallLayout.invalidateSectionConfigurations(reason: "item-length") }
    }
    private var itemsByID: [Int: ContentConfigurationWaterfallItem] = [:]
    private var itemIndices: [Int: Int] = [:]
    private var configuredSizing: [Int: UICollectionViewWaterfallLayout.ItemSizing] = [:]
    #if DEBUG
    /// 仅 UI 回归显式启用时采集滚动期间的安全区、inset 和偏移，不改变正常界面。
    private let recordsScrollDiagnostics = ProcessInfo.processInfo.arguments.contains("-waterfall-scroll-diagnostics")
    private var scrollDiagnostics: [[CGFloat]] = []
    private var hasStartedScrollDiagnostics = false
    #endif

    private lazy var cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> {
        [weak self] cell, indexPath, id in
        guard let self, let item = self.itemsByID[id] else { return }
        self.configure(cell, item: item, at: indexPath)
        cell.accessibilityIdentifier = "waterfall.cell.\(id)"
        cell.accessibilityHint = self.localizer.text("demo.contentConfiguration.waterfall.toggle")
    }

    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<ContentConfigurationWaterfallHeader>(elementKind: UICollectionView.elementKindSectionHeader) {
        [weak self] header, _, path in
        guard let self, let id = self.dataSource.snapshot().sectionIdentifiers.dropFirst(path.section).first else { return }
        header.configure(title: self.localizer.text("demo.contentConfiguration.waterfall.section", id + 1), direction: self.currentDirection)
    }

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Int> = {
        // 注册必须在 provider 外创建；在 provider 中首次访问 lazy 属性也会触发 UIKit 断言。
        let registration = cellRegistration
        let header = headerRegistration
        let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            collection, indexPath, id in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
        source.supplementaryViewProvider = { collection, kind, path in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collection.dequeueConfiguredReusableSupplementary(using: header, for: path)
        }
        return source
    }()

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: Localizer) {
        self.localizer = localizer
        super.init(nibName: nil, bundle: nil)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: waterfallLayout)
    }

    required init?(coder: NSCoder) {
        localizer = .live
        super.init(coder: coder)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: waterfallLayout)
    }

    override var body: Layout {
        collectionView
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    directionControl
                        .resizable(axis: .horizontal)
                        .frame(maxWidth: 320)
                    laneCountLabel
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .safeAreaPadding(.horizontal, 0)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] height in
                    self?.additionalSafeAreaInsets.top = height
                }
                // 列表继承完整安全区，工具栏位于自身预留的空间内。
                .padding(.top, max(0, view.safeAreaInsets.top - additionalSafeAreaInsets.top))
                .background { controlsBackground.resizable() }
            }
    }

    override func viewDidLoad() {
        waterfallLayout.sizingInvalidationHandler = { [weak self] in self?.viewIfLoaded?.setNeedsLayout() }
        waterfallLayout.itemMetadataProvider = { [weak self] path in
            guard let self, let id = self.dataSource.itemIdentifier(for: path),
                  let item = self.itemsByID[id] else {
                return .init(identifier: AnyHashable(path))
            }
            return .init(identifier: id, contentVersion: item.revision)
        }
        waterfallLayout.configuration.interSectionSpacing = 12
        waterfallLayout.register(ContentConfigurationWaterfallBackground.self, forDecorationViewOfKind: ContentConfigurationWaterfallBackground.elementKind)
        directionControl.selectedSegmentIndex = 0
        directionControl.accessibilityIdentifier = "waterfall.direction"
        directionControl.addTarget(self, action: #selector(directionChanged), for: .valueChanged)
        laneCountLabel.font = .preferredFont(forTextStyle: .footnote)
        laneCountLabel.adjustsFontForContentSizeCategory = true
        laneCountLabel.numberOfLines = 0
        laneCountLabel.textAlignment = .center
        laneCountLabel.textColor = .secondaryLabel
        laneCountLabel.accessibilityIdentifier = "waterfall.laneCount"
        controlsBackground.isUserInteractionEnabled = false
        controlsBackground.accessibilityIdentifier = "waterfall.controlsBackground"
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.accessibilityIdentifier = "waterfall.collection"
        collectionView.delegate = self
        // 两个滚动方向都保留安全区，避免横向模式下首行或末行进入系统栏区域。
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.isDirectionalLockEnabled = true
        // 先配置控件，再由宿主应用初始语言和方向并附加 body。
        super.viewDidLoad()
        setContentScrollView(collectionView, for: .top)
        view.backgroundColor = .systemGroupedBackground
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                (controller: ContentConfigurationWaterfallViewController, _: UITraitCollection) in
                controller.invalidateContent(reason: "dynamic-type")
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0), collectionView != nil,
           previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateContent(reason: "dynamic-type")
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        guard collectionView != nil else { return }
        updateControls()
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = ContentConfigurationWaterfallItem.samples(localizer: localizer).map { sample in
            var item = sample
            item.isExpanded = previous[item.id]?.isExpanded ?? false
            item.revision = (previous[item.id]?.revision ?? -1) + 1
            return item
        }
        render(reason: "content/language")
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        currentDirection = direction
        invalidateContent(reason: "direction")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reconfigureSizingIfNeeded(reason: "container-size")
        restorePendingScrollAnchor()
        #if DEBUG
        recordScrollDiagnostics()
        #endif
    }

    func setScrollDirection(_ direction: UICollectionView.ScrollDirection) {
        guard direction != waterfallLayout.configuration.scrollDirection else { return }
        let visibleRect = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        pendingScrollAnchorID = collectionView.indexPathsForVisibleItems.sorted().first(where: { path in
            waterfallLayout.layoutAttributesForItem(at: path)?.frame.intersects(visibleRect) == true
        }).flatMap { dataSource.itemIdentifier(for: $0) }
        waterfallLayout.configuration.scrollDirection = direction
        updateControls()
        configuredSizing.removeAll()
        view.setNeedsLayout()
    }

    /// provider 只读取原生容器环境；测量策略与几何布局共用返回的 section 快照。
    private func makeSection(environment: NSCollectionLayoutEnvironment) -> UICollectionViewWaterfallLayout.Section {
        var section = UICollectionViewWaterfallLayout.Section()
        section.interItemSpacing = 12
        section.interLaneSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        section.itemLengthDimension = itemLengthDimension
        let horizontal = waterfallLayout.configuration.scrollDirection == .horizontal
        let minimum = UIFontMetrics(forTextStyle: .body).scaledValue(for: horizontal ? 200 : 160, compatibleWith: environment.traitCollection)
        section.lanes = [.adaptive(minimum: minimum)]
        let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: environment.traitCollection)
        // 横向标题在固定宽度内换行，避免大字号挤占首屏内容。
        let headerLength: CGFloat = horizontal ? 100 : max(44, font.lineHeight + 24)
        section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: horizontal ? .absolute(headerLength) : .fractionalWidth(1),
                heightDimension: horizontal ? .fractionalHeight(1) : .absolute(headerLength)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: horizontal ? .leading : .top
        )]
        let background = NSCollectionLayoutDecorationItem.background(elementKind: ContentConfigurationWaterfallBackground.elementKind)
        background.contentInsets = horizontal
            ? NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
            : NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        section.decorationItems = [background]
        return section
    }

    private func updateControls() {
        let horizontal = waterfallLayout.configuration.scrollDirection == .horizontal
        directionControl.selectedSegmentIndex = horizontal ? 1 : 0
        directionControl.setTitle(localizer.text("demo.contentConfiguration.waterfall.vertical"), forSegmentAt: 0)
        directionControl.setTitle(localizer.text("demo.contentConfiguration.waterfall.horizontal"), forSegmentAt: 1)
        directionControl.accessibilityLabel = localizer.text("demo.contentConfiguration.waterfall.scrollDirection")
        directionControl.setTitleTextAttributes([.font: UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)], for: .normal)
        let countText = localizer.text(horizontal ? "demo.contentConfiguration.waterfall.automaticRows" : "demo.contentConfiguration.waterfall.automaticColumns", laneCount)
        if laneCountLabel.text != countText {
            laneCountLabel.text = countText
            viewIfLoaded?.setNeedsLayout()
        }
        collectionView.showsHorizontalScrollIndicator = horizontal
        collectionView.showsVerticalScrollIndicator = !horizontal
        collectionView.alwaysBounceHorizontal = horizontal
        collectionView.alwaysBounceVertical = !horizontal
    }

    private func restorePendingScrollAnchor() {
        guard let id = pendingScrollAnchorID, let path = dataSource.indexPath(for: id) else { return }
        guard waterfallLayout.sizingForItem(at: path).constraint != .zero else { return }
        pendingScrollAnchorID = nil
        guard let attributes = waterfallLayout.layoutAttributesForItem(at: path) else { return }
        let horizontal = waterfallLayout.configuration.scrollDirection == .horizontal
        let adjusted = collectionView.adjustedContentInset
        let section = waterfallLayout.section(at: path.section)
        let header = section.boundarySupplementaryItems.first
        let headerLength = path.item == 0 ? (horizontal ? header?.layoutSize.widthDimension.dimension : header?.layoutSize.heightDimension.dimension) ?? 0 : 0
        var offset = CGPoint(x: -adjusted.left, y: -adjusted.top)
        if horizontal {
            let desired = currentDirection == .rightToLeft
                ? attributes.frame.maxX + section.contentInsets.leading + headerLength - collectionView.bounds.width + adjusted.right
                : attributes.frame.minX - section.contentInsets.leading - headerLength - adjusted.left
            let maximum = max(-adjusted.left, waterfallLayout.collectionViewContentSize.width - collectionView.bounds.width + adjusted.right)
            offset.x = max(-adjusted.left, min(desired, maximum))
        } else {
            let desired = attributes.frame.minY - section.contentInsets.top - headerLength - adjusted.top
            let maximum = max(-adjusted.top, waterfallLayout.collectionViewContentSize.height - collectionView.bounds.height + adjusted.bottom)
            offset.y = max(-adjusted.top, min(desired, maximum))
        }
        // 定位到逻辑起始边并保留 section 边距；旧交叉轴偏移在方向改变后归零。
        collectionView.setContentOffset(offset, animated: false)
    }

    func toggleItem(id: Int) {
        guard let index = itemIndices[id] else { return }
        items[index].isExpanded.toggle()
        items[index].revision += 1
        render(reason: "expand/collapse", reconfigureIDs: [id])
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        toggleItem(id: id)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? UICollectionViewListCell,
              let id = dataSource.itemIdentifier(for: indexPath), let item = itemsByID[id] else { return }
        // 预取 cell 可能在几何失效期间以空配置创建，且错过只刷新可见项的尺寸通知。
        // 真正进入屏幕时重新读取已提交的尺寸策略，避免把空内容带回复用展示周期。
        configure(cell, item: item, at: indexPath)
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        viewIfLoaded?.setNeedsLayout()
        reconfigureSizingIfNeeded(reason: "adjusted-insets")
    }

    #if DEBUG
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 首次挂载时工具栏尚未测量；手势诊断从实际开始拖动时采样。
        hasStartedScrollDiagnostics = true
        recordScrollDiagnostics()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { recordScrollDiagnostics() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { publishScrollDiagnostics() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { publishScrollDiagnostics() }

    private func recordScrollDiagnostics() {
        guard recordsScrollDiagnostics, hasStartedScrollDiagnostics, scrollDiagnostics.count < 4_000 else { return }
        let systemTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        scrollDiagnostics.append([systemTop, collectionView.contentInset.top,
                                  collectionView.adjustedContentInset.top, collectionView.contentOffset.y,
                                  CGFloat(collectionView.visibleCells.filter { $0.contentConfiguration == nil }.count)])
    }

    private func publishScrollDiagnostics() {
        guard recordsScrollDiagnostics else { return }
        let payload: [String: Any] = ["samples": scrollDiagnostics]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        collectionView.accessibilityValue = String(data: data, encoding: .utf8)
    }
    #endif

    private func configure(_ cell: UICollectionViewListCell, item: ContentConfigurationWaterfallItem, at path: IndexPath) {
        let latestSizing = waterfallLayout.sizingForItem(at: path)
        let current = cell.contentConfiguration as? ContentConfigurationWaterfallCard.Configuration
        // 导航栏动画中几何可能暂未提交。继续用已展示的约束渲染当前模型，
        // 避免清空内容后被 UIKit 当成新的自适应高度，进而反向补偿滚动位置。
        let sizing = latestSizing.constraint == .zero
            ? configuredSizing[item.id] ?? current?.sizing
            : latestSizing
        cell.backgroundConfiguration = .clear()
        guard let sizing, sizing.constraint.width > 0, sizing.constraint.height > 0 else { return }
        configuredSizing[item.id] = sizing
        if let current, current.item.id == item.id, current.item.revision == item.revision,
           current.sizing == sizing, current.isHighlighted == cell.isHighlighted { return }
        cell.contentConfiguration = ContentConfigurationWaterfallCard.Configuration(
            item: item, sizing: sizing, isHighlighted: cell.isHighlighted)
    }

    private func reconfigureSizingIfNeeded(reason: String) {
        guard isViewLoaded, !items.isEmpty, !isApplyingSnapshot else { return }
        updateControls()
        // A lane change only affects visible configurations, not the diffable data snapshot.
        for path in collectionView.indexPathsForVisibleItems {
            guard let id = dataSource.itemIdentifier(for: path), let item = itemsByID[id],
                  let cell = collectionView.cellForItem(at: path) as? UICollectionViewListCell else { continue }
            let sizing = waterfallLayout.sizingForItem(at: path)
            guard sizing.constraint.width > 0, sizing.constraint.height > 0 else { continue }
            if configuredSizing[id] != sizing || cell.contentConfiguration == nil {
                configure(cell, item: item, at: path)
            }
        }
    }

    @objc private func directionChanged() { setScrollDirection(directionControl.selectedSegmentIndex == 0 ? .vertical : .horizontal) }

    private func invalidateContent(reason: String) {
        waterfallLayout.invalidateSectionConfigurations(reason: reason)
        configuredSizing.removeAll()
        viewIfLoaded?.setNeedsLayout()
    }

    private func render(reason: String, reconfigureIDs: [Int]? = nil) {
        guard collectionView != nil else { return }
        guard !isApplyingSnapshot else {
            pendingRenderReason = reason
            return
        }
        isApplyingSnapshot = true
        #if DEBUG
        Self.logger.debug("[ContentWaterfall] configure reason=\(reason, privacy: .public)")
        #endif
        renderGeneration += 1
        let generation = renderGeneration
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        itemIndices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        configuredSizing = configuredSizing.filter { itemsByID[$0.key] != nil }
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections(Array(0..<4))
        for section in 0..<4 { snapshot.appendItems(items.filter { $0.id / 10 == section }.map(\.id), toSection: section) }
        snapshot.reconfigureItems(Array(Set(reconfigureIDs ?? items.map(\.id))).filter { existingIDs.contains($0) })
        snapshotApplicationCount += 1
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            // UIKit 的 completion 仍可能位于 apply 调用栈内；下一轮主队列再提交尺寸更新。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.renderGeneration == generation else { return }
                self.isApplyingSnapshot = false
                if let reason = self.pendingRenderReason {
                    self.pendingRenderReason = nil
                    self.render(reason: reason)
                } else {
                    self.collectionView.layoutIfNeeded()
                    self.reconfigureSizingIfNeeded(reason: "snapshot-completed")
                    for path in self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
                        guard let header = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: path) as? ContentConfigurationWaterfallHeader else { continue }
                        let id = self.dataSource.snapshot().sectionIdentifiers[path.section]
                        header.configure(title: self.localizer.text("demo.contentConfiguration.waterfall.section", id + 1), direction: self.currentDirection)
                    }
                    self.restorePendingScrollAnchor()
                }
            }
        }
    }
}


private final class WaterfallDirectionControl: UISegmentedControl {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var measured = super.sizeThatFits(size)
        measured.height = max(44, measured.height)
        return measured
    }
}

@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: ContentConfigurationWaterfallViewController())
}
