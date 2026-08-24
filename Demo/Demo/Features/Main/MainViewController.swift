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

final class MainViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "main.title" }

    private(set) var collectionView: UICollectionView

    private let viewModel: MainViewModel
    private let router: any DemoRouting
    private var currentLocalizationUpdate = DemoLocalization.currentUIKitUpdate
    private var renderGeneration = 0
    private var latestState: MainViewModel.State?
    private var pendingVisibleAnchor: UICollectionViewLocalizationAnchor?
    private lazy var reusableLocalizationContext = UIKitLocalizationContext {
        [weak self] in
        self?.currentLocalizationUpdate.snapshot
            ?? DemoLocalization.localizationController.currentSnapshot
    }
    private var adapter: CollectionListAdapter<String>!

    convenience init() {
        self.init(
            viewModel: MainViewModel(),
            router: DemoRouter()
        )
    }

    init(
        viewModel: MainViewModel,
        router: any DemoRouting
    ) {
        self.viewModel = viewModel
        self.router = router
        collectionView = Self.makeCollectionView(
            semanticContentAttribute: DemoLocalization
                .currentLayoutDirection
                .semanticContentAttribute
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = MainViewModel()
        router = DemoRouter()
        collectionView = Self.makeCollectionView(
            semanticContentAttribute: DemoLocalization
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
        bindViewModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restorePendingVisibleItemIfNeeded()
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
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
        viewModel.reloadLocalizedContent()
    }

    override func applyLocalization(_ update: UIKitLocalizationUpdate) {
        currentLocalizationUpdate = update
        super.applyLocalization(update)
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        if currentLocalizationUpdate.layoutDirection != direction {
            currentLocalizationUpdate = DemoLocalization
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
    }

    private func bindViewModel() {
        viewModel.bind(
            stateDidChange: { [weak self] state in
                self?.render(state)
            },
            routeDidSelect: { [weak self] route in
                guard let self else { return }
                self.router.navigate(to: route, from: self)
            }
        )
    }

    private func render(_ state: MainViewModel.State) {
        latestState = state
        renderGeneration += 1
        let generation = renderGeneration
        let sections = state.sections.map(makeSection)
        adapter.apply(
            sections,
            transaction: .disabled
        ) { [weak self] _ in
            guard let self, generation == renderGeneration else { return }
            // apply completion 时可能刚创建新的 cell/header。使用最终 revision
            // 重新进入公开 configuration 与 QuickLayout self-sizing 边界。
            collectionView.applyLocalization(
                UIKitLocalizationUpdate(
                    snapshot: currentLocalizationUpdate.snapshot,
                    reasons: [.layoutDirection, .configuration]
                ),
                preservingVisibleItem: true
            )
            // 等待 Controller 完成下一次容器布局；此时新列表的 safe area、
            // adjustedContentInset 和 self-sizing attributes 才是最终值。
            view.setNeedsLayout()
        }
    }

    private func rebuildCollectionView(
        for update: UIKitLocalizationUpdate
    ) {
        if let visibleAnchor = collectionView.captureLocalizationAnchor() {
            pendingVisibleAnchor = visibleAnchor
        }

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

        if let latestState {
            render(latestState)
        }
    }

    private func restorePendingVisibleItemIfNeeded() {
        guard let anchor = pendingVisibleAnchor else { return }
        guard collectionView.numberOfSections > 0 else { return }
        guard anchor.indexPath.section < collectionView.numberOfSections,
              anchor.indexPath.item < collectionView.numberOfItems(
                inSection: anchor.indexPath.section
              ) else {
            pendingVisibleAnchor = nil
            return
        }
        if collectionView.restoreLocalizationAnchor(anchor) {
            pendingVisibleAnchor = nil
        }
    }

    private func makeSection(
        _ section: MainViewModel.State.Section
    ) -> ListSection<String> {
        ListSection(section.id) {
            ForEach(section.routes, id: \.id) { routeState in
                Row(
                    model: routeState,
                    cell: UICollectionViewListCell.self
                ) { cell, routeState, _ in
                    self.reusableLocalizationContext
                        .prepareForConfiguration(cell)
                    self.configure(cell, with: routeState)
                }
                .refreshID(routeState.title)
                .onSelect { [weak self] routeState, _ in
                    self?.viewModel.select(routeState.route)
                }
                .onDisplay { cell, _ in
                    self.reusableLocalizationContext
                        .restoreOnAttachment(cell)
                }
            }
        } layout: {
            ListLayout(
                itemHeight: .estimated(52),
                spacing: 10,
                contentInsets: .init(
                    top: 8,
                    leading: 16,
                    bottom: 18,
                    trailing: 16
                )
            )
        } header: {
            Header(
                MainMenuSectionHeaderView.self,
                id: "\(section.id).header"
            ) { header, _ in
                self.reusableLocalizationContext
                    .prepareForConfiguration(header)
                header.configure(
                    title: section.title,
                    identifier: section.id
                )
            }
            .refreshID(section.title)
            .layout(height: .estimated(36))
            .onDisplay { header, _ in
                self.reusableLocalizationContext
                    .restoreOnAttachment(header)
            }
        }
        .selectionMode(.single)
    }

    private func configure(
        _ cell: UICollectionViewListCell,
        with routeState: MainViewModel.State.Route
    ) {
        cell.contentConfiguration = MainMenuContentConfiguration(
            title: routeState.title,
            accessibilityIdentifier: routeState.route.titleKey
        )
        cell.accessories = []
        cell.accessibilityIdentifier = routeState.route.titleKey
        cell.accessibilityLabel = routeState.title
        cell.accessibilityTraits = .button

        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .clear
        cell.backgroundConfiguration = backgroundConfiguration
    }

    private func makeCollectionViewLayout()
        -> UICollectionViewCompositionalLayout {
        adapter.makeCompositionalLayout(
            configuration: ListCompositionalLayoutConfiguration(
                scrollDirection: .vertical,
                interSectionSpacing: 0,
                contentInsetsReference: .safeArea
            )
        )
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


#Preview {
    UINavigationController(rootViewController: MainViewController())
}
