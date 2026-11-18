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

final class MainViewController: LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? { "app.tab.examples" }

    var selectedRoute: MainRoute? {
        didSet { if isViewLoaded { updateSelectedRoute() } }
    }

    private var isExpandedSidebar: Bool {
        splitViewController.map { !$0.isCollapsed } ?? false
    }
    private var lastExpandedSidebar: Bool?

    /// 使用容器的实际状态，兼容 iOS 15；不把 size class 当作分栏状态。
    /// 转场完成、重新显示以及布局时都会调用，只有状态变化才更新已有 cell。
    func updateSplitPresentation() {
        guard isViewLoaded else { return }
        updateNavigationTitlePresentation()
        let expanded = isExpandedSidebar
        guard lastExpandedSidebar != expanded else { return }
        lastExpandedSidebar = expanded
        for case let cell as UICollectionViewListCell in collectionView.visibleCells {
            updateDisclosureAccessory(cell)
        }
        updateSelectedRoute()
    }

    private func updateDisclosureAccessory(_ cell: UICollectionViewListCell) {
        cell.accessories = isExpandedSidebar ? [] : [.disclosureIndicator()]
    }

    /// Restore selection by route identity after filtering or rebuilding the list.
    func updateSelectedRoute() {
        guard isViewLoaded, let state = latestState else { return }
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: false)
        }
        guard isExpandedSidebar, let selectedRoute else { return }
        for (section, group) in state.sections.enumerated() {
            if let item = group.routes.firstIndex(where: { $0.route == selectedRoute }) {
                collectionView.selectItem(at: IndexPath(item: item, section: section), animated: false, scrollPosition: [])
                break
            }
        }
    }

    private var collectionLayoutDirection: UIUserInterfaceLayoutDirection?
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
    private var adapter: CollectionListAdapter<String>!
    private let searchController = UISearchController(searchResultsController: nil)
    private let clearSearchButton = LocalizedButton(type: .system)

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
        collectionView = Self.makeCollectionView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = MainViewModel()
        router = MainRouter()
        collectionView = Self.makeCollectionView()
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
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                (controller: MainViewController, _: UITraitCollection) in
                controller.collectionView.collectionViewLayout.invalidateLayout()
            }
        }
        bindViewModel()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0),
           previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        updateSplitPresentation()

        if splitViewController is ExampleSplitViewController {
            updateSelectedRoute()
            return
        }
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

    override var keyCommands: [UIKeyCommand]? {
        let search = UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(focusSearch))
        search.discoverabilityTitle = Localization.text("app.action.search")
        return (super.keyCommands ?? []) + [search]
    }

    @objc private func focusSearch() {
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
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
        if #available(iOS 16.0, *) {
            navigationItem.preferredSearchBarPlacement = .stacked
        }
        definesPresentationContext = true
        configureSearchClearAction()
    }

    private func configureSearchClearAction() {
        let field = searchController.searchBar.searchTextField
        // 当前系统的 iPad 原生清除按钮会同时取消 UISearchController 的呈现。
        // 目录需要连续筛选：通过公开 accessory API 提供独立的清空文本动作，
        // 保留原生输入与取消搜索，不替换内部 delegate，也不重新请求焦点。
        field.clearButtonMode = .never
        clearSearchButton.frame.size = CGSize(width: 44, height: 44)
        clearSearchButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearSearchButton.setPreferredSymbolConfiguration(.init(textStyle: .body), forImageIn: .normal)
        clearSearchButton.tintColor = .secondaryLabel
        clearSearchButton.accessibilityIdentifier = "main.search.clear"
        clearSearchButton.accessibilityLabel = Localization.text("main.search.clear")
        clearSearchButton.addTarget(self, action: #selector(clearSearchQuery), for: .touchUpInside)
        field.rightView = clearSearchButton
        updateSearchClearVisibility()
    }

    @objc private func clearSearchQuery() {
        searchController.searchBar.text = ""
        updateSearchResults(for: searchController)
    }

    private func updateSearchClearVisibility() {
        searchController.searchBar.searchTextField.rightViewMode =
            (searchController.searchBar.text ?? "").isEmpty ? .never : .always
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSplitPresentation()
        restorePendingVisibleItemIfNeeded()
    }

    private func updateNavigationTitlePresentation() {
        // 展开的目录侧栏使用原生行内标题，避免大标题与侧栏工具按钮重叠。
        // 跟随真实分栏的折叠状态，单列导航仍保留原有大标题体验。
        let isSidebar = isExpandedSidebar
        let mode: UINavigationItem.LargeTitleDisplayMode = isSidebar ? .never : .always
        if navigationItem.largeTitleDisplayMode != mode {
            navigationItem.largeTitleDisplayMode = mode
        }
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInsetAdjustmentBehavior = .automatic

        // 列表与 adapter 保持身份，语言和方向切换只更新内容与布局。
        adapter = CollectionListAdapter<String>(
            collectionView: collectionView
        )
        collectionView.collectionViewLayout = makeCollectionViewLayout()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        searchController.searchBar.placeholder = Localization.text("main.search.placeholder")
        clearSearchButton.accessibilityLabel = Localization.text("main.search.clear")
        viewModel.reloadLocalizedContent()
    }

    private func captureLocalizationPosition() {
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

    override func applyLocalization(_ update: LocalizationUpdate) {
        captureLocalizationPosition()
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
        super.reloadLayoutDirection(direction)
        if collectionLayoutDirection != direction {
            collectionLayoutDirection = direction
            captureVisibleAnchorIfNeeded()
            collectionView.setCollectionViewLayout(makeCollectionViewLayout(), animated: false)
            for case let cell as UICollectionViewListCell in collectionView.visibleCells {
                Self.updateParagraphAlignment(cell, direction: direction)
            }
            view.setNeedsLayout()
        } else {
            collectionView.collectionViewLayout.invalidateLayout()
        }
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
        if #available(iOS 17.0, *) {
            if state.sections.isEmpty {
                var empty = UIContentUnavailableConfiguration.search()
                empty.text = Localization.text("main.search.empty.title")
                empty.secondaryText = Localization.text("main.search.empty.description")
                contentUnavailableConfiguration = empty
            } else {
                contentUnavailableConfiguration = nil
            }
        } else if state.sections.isEmpty {
            var empty = UIListContentConfiguration.subtitleCell()
            empty.text = Localization.text("main.search.empty.title")
            empty.secondaryText = Localization.text("main.search.empty.description")
            empty.textProperties.alignment = .center
            empty.textProperties.numberOfLines = 0
            empty.secondaryTextProperties.alignment = .center
            empty.secondaryTextProperties.numberOfLines = 0
            collectionView.backgroundView = UIListContentView(configuration: empty)
        } else {
            collectionView.backgroundView = nil
        }
        renderGeneration += 1
        let generation = renderGeneration
        let sections = state.sections.map(makeSection)
        adapter.apply(
            sections,
            transaction: .disabled
        ) { [weak self] _ in
            guard let self, generation == renderGeneration else { return }
            collectionView.setNeedsLayout()
            // 等待 Controller 完成下一次容器布局；此时新列表的 safe area、
            // adjustedContentInset 和 self-sizing attributes 才是最终值。
            completedRenderGeneration = generation
            updateSelectedRoute()
            view.setNeedsLayout()
            // 下一轮主线程任务中，导航栏与新列表已完成挂载和内容边距调整。
            Task { @MainActor [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.view.layoutIfNeeded()
                self.restorePendingVisibleItemIfNeeded()
            }
        }
    }


    private func captureVisibleAnchorIfNeeded() {
        guard pendingVisibleAnchor == nil,
              let state = latestState,
              let anchor = collectionView.captureReadingAnchor(),
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
        let resolvedAnchor = CollectionReadingAnchor(
            indexPath: IndexPath(item: item, section: section),
            offsetFromViewportTop: anchor.offsetFromViewportTop,
            offsetFromViewportLeading: anchor.offsetFromViewportLeading
        )
        isRestoringVisibleAnchor = true
        defer { isRestoringVisibleAnchor = false }
        UIView.performWithoutAnimation {
            guard collectionView.restoreReadingAnchor(resolvedAnchor) else { return }
            navigationController?.view.setNeedsLayout()
            navigationController?.view.layoutIfNeeded()
            if collectionView.restoreReadingAnchor(resolvedAnchor) {
                pendingVisibleAnchor = nil
            }
        }
    }

    private func makeSection(
        _ section: MainViewModel.State.Section
    ) -> ListSection<String> {
        return ListSection(section.id) {
            ForEach(section.routes, id: \.id) { routeState in
                Row(
                    model: routeState,
                    cell: UICollectionViewListCell.self
                ) { [weak self] cell, routeState, _ in
                    Self.configure(cell, with: routeState, direction: self?.currentLocalizationUpdate.layoutDirection ?? Localization.currentUIKitDirection)
                    self?.updateDisclosureAccessory(cell)
                }
                .refreshID(routeState.title)
                .onSelect { [weak self] routeState, _ in
                    self?.viewModel.select(routeState.route)
                }
                .onAppear { [weak self] cell, _ in
                    // 复用或预取的 cell 可能在另一种分栏状态下完成配置。
                    self?.updateDisclosureAccessory(cell)
                    if let self {
                        Self.updateParagraphAlignment(cell, direction: collectionView.effectiveUserInterfaceLayoutDirection)
                    }
                }
            }
        } supplementaries: {
            SectionSupplementary(
                MainMenuSectionHeaderView.self,
                kind: UICollectionView.elementKindSectionHeader,
                elementID: "\(section.id).header"
            ) { header, _ in
                header.configure(
                    title: section.title,
                    identifier: section.id
                )
            }
            .refreshID(section.title)
        }
        .selectionMode(.single)
    }

    private static func configure(
        _ cell: UICollectionViewListCell,
        with routeState: MainViewModel.State.Route,
        direction: UIUserInterfaceLayoutDirection
    ) {
        var content = cell.defaultContentConfiguration()
        // 目录标题属于 App 文案；原生列表仍管理图标、附件与复用，仅明确段落的 leading 对齐。
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = direction == .rightToLeft ? .right : .left
        content.attributedText = NSAttributedString(string: routeState.title, attributes: [.paragraphStyle: paragraph])
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

        if #available(iOS 18.0, *) {
            cell.backgroundConfiguration = .listCell()
        } else {
            cell.backgroundConfiguration = .listGroupedCell()
        }
    }

    /// 原生列表管理图标与附件；已缓存的富文本段落需要在有效方向改变后更新。
    private static func updateParagraphAlignment(_ cell: UICollectionViewListCell, direction: UIUserInterfaceLayoutDirection) {
        guard var content = cell.contentConfiguration as? UIListContentConfiguration,
              let text = content.attributedText, text.length > 0 else { return }
        let alignment: NSTextAlignment = direction == .rightToLeft ? .right : .left
        let paragraph = (text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        guard paragraph.alignment != alignment else { return }
        paragraph.alignment = alignment
        let updated = NSMutableAttributedString(attributedString: text)
        updated.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: updated.length))
        content.attributedText = updated
        cell.contentConfiguration = content
    }

    private func makeCollectionViewLayout()
        -> UICollectionViewCompositionalLayout {
        // UIKit 负责 inset grouped 的圆角、分隔线和自适应分组标题空间；
        // ListKit 继续管理数据、复用注册与路由事件。
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private static func makeCollectionView() -> UICollectionView {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        return collectionView
    }
}

extension MainViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateSearchClearVisibility()
        let query = (searchController.searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != viewModel.searchQuery else { return }
        pendingVisibleAnchor = nil
        viewModel.updateSearchQuery(query)
    }
}

@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: MainViewController())
}
