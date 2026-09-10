//
//  MainViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import ListKit
import QuickLayout
import QuickLayoutKit

final class MainViewController: LocalizedQuickLayoutHostingController, UIKitLocalizationPreparing {

    override var localizedTitleKey: String? { "main.title" }

    private(set) var collectionView: UICollectionView

    private let viewModel: MainViewModel
    private let router: any MainRouting
    private var currentLocalizationUpdate = Localization.currentUIKitUpdate
    private var renderGeneration = 0
    private var latestState: MainViewModel.State?
    private struct VisibleAnchor {
        let sectionID: String
        let routeID: String
        let offsetFromViewportTop: CGFloat
        let offsetFromViewportLeading: CGFloat
    }
    private var pendingVisibleAnchor: VisibleAnchor?
    private weak var anchorCollectionView: UICollectionView?
    private var isApplyingLocalization = false
    private var isRestoringVisibleAnchor = false
    private var completedRenderGeneration: Int?
    private lazy var reusableLocalizationContext = UIKitLocalizationContext {
        [weak self] in
        self?.currentLocalizationUpdate.snapshot
            ?? Localization.localizationController.currentSnapshot
    }
    private var adapter: CollectionListAdapter<String>!
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var searchInputBinding = Localization.reusableContext
        .makeTextInputBinding(to: searchController.searchBar)

    convenience init() {
        self.init(
            viewModel: MainViewModel(),
            router: MainRouter()
        )
    }

    init(
        viewModel: MainViewModel,
        router: any MainRouting
    ) {
        self.viewModel = viewModel
        self.router = router
        collectionView = Self.makeCollectionView(
            semanticContentAttribute: Localization
                .currentLayoutDirection
                .semanticContentAttribute
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = MainViewModel()
        router = MainRouter()
        collectionView = Self.makeCollectionView(
            semanticContentAttribute: Localization
                .currentLayoutDirection
                .semanticContentAttribute
        )
        super.init(coder: coder)
    }

    override var body: Layout {
        collectionView
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    override func viewDidLoad() {
        configureCollectionView()
        super.viewDidLoad()
        configureNavigation()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (controller: MainViewController, _: UITraitCollection) in
            controller.collectionView.collectionViewLayout.invalidateLayout()
        }
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true

        let selectedItems = collectionView.indexPathsForSelectedItems ?? []
        guard !selectedItems.isEmpty else { return }
        let deselect = { [weak self] in
            guard let self else { return }
            selectedItems.forEach {
                self.collectionView.deselectItem(at: $0, animated: animated)
            }
        }
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in
                deselect()
            }, completion: { [weak self] context in
                guard context.isCancelled, let self else { return }
                selectedItems.forEach {
                    self.collectionView.selectItem(at: $0, animated: false, scrollPosition: [])
                }
            })
        } else {
            deselect()
        }
    }

    private func configureNavigation() {
        setContentScrollView(collectionView, for: .top)
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = Localization.text("main.search.placeholder")
        searchController.searchBar.accessibilityIdentifier = "main.search"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.preferredSearchBarPlacement = .stacked
        definesPresentationContext = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restorePendingVisibleItemIfNeeded()
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInsetAdjustmentBehavior = .automatic

        // 每个 collection view 拥有独立的 ListKit adapter。局部重建列表时不能把
        // 旧 diffable data source 或 delegate 带到新实例。
        adapter = CollectionListAdapter<String>(
            collectionView: collectionView
        )
        collectionView.collectionViewLayout = makeCollectionViewLayout()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        searchController.searchBar.placeholder = Localization.text("main.search.placeholder")
        viewModel.reloadLocalizedContent()
    }

    func prepareForLocalization(_ update: UIKitLocalizationUpdate) {
        // 原列表或已滚动的新列表以当前阅读位置为准，避免初始化锚点覆盖后续滚动。
        // 新列表仍停留在初始顶部、尚未恢复时，继续保留旧列表的稳定条目锚点。
        let hasScrolledContent = collectionView.contentOffset.y
            + collectionView.adjustedContentInset.top > 1
        if anchorCollectionView === collectionView || hasScrolledContent {
            pendingVisibleAnchor = nil
        }
        captureVisibleAnchorIfNeeded()
        completedRenderGeneration = nil
    }

    override func applyLocalization(_ update: UIKitLocalizationUpdate) {
        captureVisibleAnchorIfNeeded()
        currentLocalizationUpdate = update
        // 同一次语言更新中的方向和文案回调只累积最终状态，结束后统一提交列表。
        isApplyingLocalization = true
        super.applyLocalization(update)
        isApplyingLocalization = false
        if let latestState {
            render(latestState)
        }
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        if currentLocalizationUpdate.layoutDirection != direction {
            currentLocalizationUpdate = Localization
                .layoutDirectionUpdate(direction)
        }
        let update = UIKitLocalizationUpdate(
            snapshot: currentLocalizationUpdate.snapshot,
            reasons: [.layoutDirection]
        )
        if collectionView.semanticContentAttribute
            != update.semanticContentAttribute {
            rebuildCollectionView(for: update)
        }
        // collectionView 是 HostingController 的 QuickLayout 根内容，也是列表方向
        // 边界。它已在创建时获得最新 semantic；这里继续刷新可见 reusable 内容和
        // compositional layout 缓存。
        collectionView.applyLocalization(
            update,
            preservingVisibleItem: true,
            rebuildingLayoutWith: { [unowned self] in
                makeCollectionViewLayout()
            }
        )
        super.reloadLayoutDirection(direction)
        searchController.searchBar.semanticContentAttribute = update.semanticContentAttribute
        searchInputBinding.refresh()
    }

    private func bindViewModel() {
        viewModel.bind(
            stateDidChange: { [weak self] state in
                self?.render(state)
            },
            routeDidSelect: { [weak self] route in
                guard let self else { return }
                self.searchController.searchBar.resignFirstResponder()
                self.router.navigate(to: route, from: self)
            }
        )
    }

    private func render(_ state: MainViewModel.State) {
        latestState = state
        guard !isApplyingLocalization else { return }
        completedRenderGeneration = nil
        if state.sections.isEmpty {
            var empty = UIContentUnavailableConfiguration.search()
            empty.text = Localization.text("main.search.empty.title")
            empty.secondaryText = Localization.text("main.search.empty.description")
            contentUnavailableConfiguration = empty
        } else {
            contentUnavailableConfiguration = nil
        }
        renderGeneration += 1
        let generation = renderGeneration
        let sections = state.sections.map(makeSection)
        adapter.apply(
            sections,
            transaction: .disabled
        ) { [weak self] _ in
            guard let self, generation == renderGeneration else { return }
            // apply completion 时可能刚创建新的 cell/header。使用最终 revision
            // 重新进入公开 configuration 与 UIKit self-sizing 边界。
            collectionView.applyLocalization(
                UIKitLocalizationUpdate(
                    snapshot: currentLocalizationUpdate.snapshot,
                    reasons: [.layoutDirection, .configuration]
                ),
                preservingVisibleItem: true
            )
            // 等待 Controller 完成下一次容器布局；此时新列表的 safe area、
            // adjustedContentInset 和 self-sizing attributes 才是最终值。
            completedRenderGeneration = generation
            view.setNeedsLayout()
            // 下一轮主线程任务中，导航栏与新列表已完成挂载和内容边距调整。
            Task { @MainActor [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.view.layoutIfNeeded()
                self.restorePendingVisibleItemIfNeeded()
            }
        }
    }

    private func rebuildCollectionView(
        for update: UIKitLocalizationUpdate
    ) {
        captureVisibleAnchorIfNeeded()
        completedRenderGeneration = nil
        collectionView = Self.makeCollectionView(
            semanticContentAttribute: update.semanticContentAttribute
        )
        configureCollectionView()

        // QuickLayout body 的视图身份发生变化；立即提交一次 body diff，让旧列表离层，
        // 新列表在首次物化滚动指示器前继承正确方向。
        UIView.performWithoutAnimation {
            setNeedsQuickLayout()
            quickLayoutIfNeeded()
        }
        // 新列表加入视图层级后再绑定，让 UIKit 跟随其滚动更新导航栏。
        setContentScrollView(collectionView, for: .top)

        if let latestState {
            render(latestState)
        }
    }

    private func captureVisibleAnchorIfNeeded() {
        guard pendingVisibleAnchor == nil,
              let state = latestState,
              let anchor = collectionView.captureLocalizationAnchor(),
              state.sections.indices.contains(anchor.indexPath.section),
              state.sections[anchor.indexPath.section].routes.indices.contains(anchor.indexPath.item)
        else { return }
        let section = state.sections[anchor.indexPath.section]
        anchorCollectionView = collectionView
        pendingVisibleAnchor = VisibleAnchor(
            sectionID: section.id,
            routeID: section.routes[anchor.indexPath.item].id,
            offsetFromViewportTop: anchor.offsetFromViewportTop,
            offsetFromViewportLeading: anchor.offsetFromViewportLeading
        )
    }

    private func restorePendingVisibleItemIfNeeded() {
        guard !isApplyingLocalization,
              !isRestoringVisibleAnchor,
              completedRenderGeneration == renderGeneration,
              let anchor = pendingVisibleAnchor,
              let state = latestState else { return }
        guard let section = state.sections.firstIndex(where: { $0.id == anchor.sectionID }),
              let item = state.sections[section].routes.firstIndex(where: { $0.id == anchor.routeID }) else {
            // 搜索结果中已不存在原条目时，放弃旧位置，避免恢复到其他条目。
            pendingVisibleAnchor = nil
            return
        }
        let resolvedAnchor = UICollectionViewLocalizationAnchor(
            indexPath: IndexPath(item: item, section: section),
            offsetFromViewportTop: anchor.offsetFromViewportTop,
            offsetFromViewportLeading: anchor.offsetFromViewportLeading
        )
        isRestoringVisibleAnchor = true
        defer { isRestoringVisibleAnchor = false }
        UIView.performWithoutAnimation {
            guard collectionView.restoreLocalizationAnchor(resolvedAnchor) else { return }
            // 恢复滚动会触发大标题折叠，进而再次改变导航栏和列表的内容边距。
            // 完成容器联动后再对齐一次；防止中间布局回调重复恢复同一锚点。
            navigationController?.view.setNeedsLayout()
            navigationController?.view.layoutIfNeeded()
            if collectionView.restoreLocalizationAnchor(resolvedAnchor) {
                pendingVisibleAnchor = nil
            }
        }
    }

    private func makeSection(
        _ section: MainViewModel.State.Section
    ) -> ListSection<String> {
        // 列表长期保存配置闭包，只捕获独立上下文，避免反向持有控制器。
        let localizationContext = reusableLocalizationContext
        return ListSection(section.id) {
            ForEach(section.routes, id: \.id) { routeState in
                Row(
                    model: routeState,
                    cell: UICollectionViewListCell.self
                ) { cell, routeState, _ in
                    localizationContext
                        .prepareForConfiguration(cell)
                    Self.configure(cell, with: routeState)
                }
                .refreshID(routeState.title)
                .onSelect { [weak self] routeState, _ in
                    self?.viewModel.select(routeState.route)
                }
                .onDisplay { cell, _ in
                    localizationContext
                        .restoreOnAttachment(cell)
                }
            }
        } header: {
            Header(
                MainMenuSectionHeaderView.self,
                id: "\(section.id).header"
            ) { header, _ in
                localizationContext
                    .prepareForConfiguration(header)
                header.configure(
                    title: section.title,
                    identifier: section.id
                )
            }
            .refreshID(section.title)
            .onDisplay { header, _ in
                localizationContext
                    .restoreOnAttachment(header)
            }
        }
        .selectionMode(.single)
    }

    private static func configure(
        _ cell: UICollectionViewListCell,
        with routeState: MainViewModel.State.Route
    ) {
        var content = cell.defaultContentConfiguration()
        content.text = routeState.title
        content.textProperties.color = .label
        content.textProperties.numberOfLines = 0
        content.image = UIImage(systemName: routeState.route.iconSystemName)
        content.imageProperties.tintColor = routeState.route.menuIconColor
        content.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
        content.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 30)
        content.directionalLayoutMargins.top = 14
        content.directionalLayoutMargins.bottom = 14
        cell.contentConfiguration = content
        cell.accessories = [.disclosureIndicator()]
        cell.accessibilityIdentifier = routeState.route.titleKey
        cell.accessibilityLabel = routeState.title
        cell.accessibilityTraits = .button

        cell.backgroundConfiguration = .listCell()
    }

    private func makeCollectionViewLayout()
        -> UICollectionViewCompositionalLayout {
        // UIKit 负责 inset grouped 的圆角、分隔线和自适应分组标题空间；
        // ListKit 继续管理数据、复用注册与路由事件。
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private static func makeCollectionView(
        semanticContentAttribute: UISemanticContentAttribute
    ) -> UICollectionView {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        // UIScrollView 的 indicator side 在首次物化时解析。必须在列表进入视图层级
        // 之前写入方向；运行时切换则由 Owner 局部重建列表实例。
        collectionView.semanticContentAttribute = semanticContentAttribute
        return collectionView
    }
}

extension MainViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != viewModel.searchQuery else { return }
        pendingVisibleAnchor = nil
        viewModel.updateSearchQuery(query)
    }
}

#Preview {
    UINavigationController(rootViewController: MainViewController())
}
