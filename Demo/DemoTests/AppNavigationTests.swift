import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct AppNavigationTests {
    @Test func catalogClearActionPreservesFirstResponderAndSearchPresentation() async throws {
        let tabs = AppTabBarController(viewModel: AppNavigationViewModel(chatAvailable: false))
        let window = try makeVisibleTestWindow(rootViewController: tabs, size: CGSize(width: 1024, height: 768))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let split = try #require(tabs.featureControllers[.examples] as? ExampleSplitViewController)
        split.select(.frame)
        let detail = try #require(split.detailNavigationController.viewControllers.first)
        split.show(.primary)
        let search = try #require(split.menuController.navigationItem.searchController)
        let field = search.searchBar.searchTextField
        search.isActive = true
        field.becomeFirstResponder()
        try #require(await waitForCondition { field.isFirstResponder && search.isActive })
        let clear = try #require(field.rightView as? UIButton)
        for query in ["Frame", "Counter", "Geometry"] {
            field.insertText(query)
            #expect(await waitForCondition { search.searchBar.text == query && field.rightViewMode == .always })
            clear.sendActions(for: .touchUpInside)
            #expect(await waitForCondition {
                (search.searchBar.text ?? "").isEmpty && field.rightViewMode == .never
            })
            #expect(field.isFirstResponder)
            #expect(search.isActive)
            #expect(field.clearButtonMode == .never)
            #expect(split.selectedRoute == .frame)
            #expect(split.detailNavigationController.viewControllers.first === detail)
            // 下一轮直接输入，不再次 becomeFirstResponder；也不重建搜索宿主。
        }
    }

    @Test func tabsExcludeUnavailableChatAndIgnoreRepeatedSelections() {
        let model = AppNavigationViewModel(chatAvailable: false)
        var changes = 0
        model.bind { _ in changes += 1 }
        #expect(model.state.items.map(\.id) == [.examples, .voiceRoom])
        model.select(.chat)
        model.select(.examples)
        #expect(changes == 1)
        model.select(.voiceRoom)
        #expect(changes == 2)
        model.reloadLocalizedContent()
        #expect(model.state.selectedTab == .voiceRoom)
    }

    @Test func nativeTabSelectionCommitsBeforeUpdatingViewModel() throws {
        let tabs = AppTabBarController(viewModel: AppNavigationViewModel(chatAvailable: false))
        tabs.loadViewIfNeeded()
        let room = try #require(tabs.featureControllers[.voiceRoom])
        #expect(tabs.tabBarController(tabs, shouldSelect: room))
        #expect(tabs.selectedFeature == .examples)
        // 模拟 UIKit 在 shouldSelect 返回 true 后提交选择，再通知 didSelect。
        tabs.selectedViewController = room
        tabs.tabBarController(tabs, didSelect: room)
        #expect(tabs.selectedFeature == .voiceRoom)
        #expect(tabs.selectedViewController === room)
        #expect(tabs.tabBarController(tabs, shouldSelect: room))
        tabs.tabBarController(tabs, didSelect: room)
        #expect(tabs.selectedViewController === room)
        tabs.select(.examples)
        #expect(tabs.selectedViewController === tabs.featureControllers[.examples])
    }

    @Test func catalogContainsEachExampleExactlyOnce() {
        let catalog = MainViewModel().state.sections
        let routes = catalog.flatMap(\.routes).map(\.route)
        #expect(catalog.count == 6)
        #expect(routes.count == Set(routes).count)
        #expect(catalog.first { $0.id == "main.section.layout" }?.routes.contains { $0.route == .arrangement } == true)
        #expect(Set(routes) == Set(MainRoute.allCases.filter { AppTab(route: $0) == nil }))
    }

    @Test func selectionRejectsRootFeaturesAndKeepsIdentity() {
        let model = ExampleNavigationViewModel()
        #expect(!model.select(.chat))
        #expect(!model.select(.voiceRoom))
        #expect(model.selectedRoute == nil)
        #expect(model.select(.frame))
        #expect(!model.select(.frame))
        #expect(model.selectedRoute == .frame)
    }

    @Test func splitPreservesDetailAndSearchAcrossTabChanges() throws {
        let tabs = AppTabBarController(viewModel: AppNavigationViewModel(chatAvailable: false))
        let window = try makeVisibleTestWindow(rootViewController: tabs, size: CGSize(width: 1024, height: 768))
        defer { window.isHidden = true }
        let split = try #require(tabs.featureControllers[.examples] as? ExampleSplitViewController)
        split.select(.frame)
        let detail = try #require(split.detailNavigationController.viewControllers.first)
        let search = try #require(split.menuController.navigationItem.searchController)
        search.searchBar.text = "frame"
        split.menuController.updateSearchResults(for: search)
        split.select(.frame)
        #expect(split.detailNavigationController.viewControllers.first === detail)
        tabs.select(.voiceRoom)
        tabs.select(.examples)
        #expect(split.detailNavigationController.viewControllers.first === detail)
        #expect(search.searchBar.text == "frame")
        #expect(split.splitViewController(split, topColumnForCollapsingToProposedTopColumn: .primary) == .secondary)
        split.select(.counter)
        #expect(split.detailNavigationController.viewControllers.count == 1)
        #expect(split.selectedRoute == .counter)
    }

    @Test(.enabled("Expanded split-view transitions require iPad") {
        await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad }
    })
    func splitCollapseAndExpansionPreserveSelectedController() async throws {
        guard #available(iOS 17.0, *) else { return }
        let tabs = AppTabBarController(viewModel: AppNavigationViewModel(chatAvailable: false))
        tabs.traitOverrides.horizontalSizeClass = .regular
        let window = try makeVisibleTestWindow(rootViewController: tabs, size: CGSize(width: 1024, height: 768))
        defer { window.isHidden = true }
        let split = try #require(tabs.featureControllers[.examples] as? ExampleSplitViewController)
        #expect(await waitForCondition { !split.isCollapsed })
        #expect(split.menuController.navigationItem.largeTitleDisplayMode == .never)
        let menu = split.menuController
        let search = try #require(menu.navigationItem.searchController)
        let counterQuery = Localization.text(MainRoute.counter.titleKey)
        search.searchBar.text = counterQuery
        menu.updateSearchResults(for: search)
        let collection = menu.collectionView
        let first = IndexPath(item: 0, section: 0)
        #expect(await waitForCondition {
            (collection.cellForItem(at: first) as? UICollectionViewListCell)?.accessories.isEmpty == true
        })
        split.select(.counter)
        #expect(await waitForCondition { collection.indexPathsForSelectedItems == [first] })
        let detail = try #require(split.detailNavigationController.viewControllers.first)
        tabs.traitOverrides.horizontalSizeClass = .compact
        window.frame.size = CGSize(width: 390, height: 768)
        window.layoutIfNeeded()
        #expect(await waitForCondition { split.isCollapsed && detail.view.window === window })
        #expect(split.selectedRoute == .counter)
        #expect(collection.indexPathsForSelectedItems?.isEmpty == true)
        split.show(.primary)
        #expect(await waitForCondition { split.menuController.view.window === window })
        #expect(split.menuController.navigationItem.largeTitleDisplayMode == .always)
        #expect(await waitForCondition {
            (collection.cellForItem(at: first) as? UICollectionViewListCell)?.accessories.count == 1
        })
        #expect(collection.indexPathsForSelectedItems?.isEmpty == true)
        split.select(.counter)
        #expect(await waitForCondition { detail.view.window === window })
        tabs.traitOverrides.horizontalSizeClass = .regular
        window.frame.size = CGSize(width: 1024, height: 768)
        window.layoutIfNeeded()
        #expect(await waitForCondition {
            !split.isCollapsed && split.menuController.view.window === window && detail.view.window === window
        })
        #expect(split.detailNavigationController.viewControllers.first === detail)
        #expect(split.selectedRoute == .counter)
        #expect(split.menuController.navigationItem.largeTitleDisplayMode == .never)
        #expect(await waitForCondition {
            (collection.cellForItem(at: first) as? UICollectionViewListCell)?.accessories.isEmpty == true
                && collection.indexPathsForSelectedItems == [first]
        })
        #expect(menu.collectionView === collection)
        #expect(search.searchBar.text == counterQuery)

        // 筛选掉当前选择再恢复：新配置/复用的 cell 也必须遵循展开状态。
        search.searchBar.text = Localization.text(MainRoute.geometry.titleKey)
        menu.updateSearchResults(for: search)
        #expect(await waitForCondition {
            collection.indexPathsForSelectedItems?.isEmpty == true
                && (collection.cellForItem(at: first) as? UICollectionViewListCell)?.accessories.isEmpty == true
        })
        search.searchBar.text = counterQuery
        menu.updateSearchResults(for: search)
        #expect(await waitForCondition { collection.indexPathsForSelectedItems == [first] })
        #expect(split.detailNavigationController.viewControllers.first === detail)
    }

    @Test func standaloneMenuKeepsDisclosureWithoutSidebarSelection() async throws {
        let menu = MainViewController()
        let navigation = UINavigationController(rootViewController: menu)
        let window = try makeVisibleTestWindow(rootViewController: navigation, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        menu.selectedRoute = .safeAreaPadding
        #expect(await waitForCondition {
            let cells = menu.collectionView.visibleCells.compactMap { $0 as? UICollectionViewListCell }
            return !cells.isEmpty && cells.allSatisfy { $0.accessories.count == 1 }
        })
        #expect(menu.collectionView.indexPathsForSelectedItems?.isEmpty == true)
        #expect(menu.navigationItem.largeTitleDisplayMode == .always)
    }

    @Test func composerReflowsAgainstContentViewportInsteadOfWindow() {
        guard #available(iOS 26.0, *) else { return }
        let composer = ComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        composer.textView.text = String(repeating: "Long draft line\n", count: 30)
        composer.updateAvailableViewportHeight(700)
        let expanded = composer.currentInputHeight
        composer.updateAvailableViewportHeight(200)
        #expect(composer.currentInputHeight <= 84)
        #expect(composer.currentInputHeight < expanded)
        #expect(composer.textView.isScrollEnabled)
        composer.updateAvailableViewportHeight(700)
        #expect(composer.currentInputHeight == expanded)
    }

    @Test func detachedSheetDoesNotCountAsBottomObstruction() {
        let safe = CGRect(x: 0, y: 24, width: 1024, height: 720)
        #expect(!BottomObstructionCoordinator.isBottomAttached(
            CGRect(x: 240, y: 180, width: 540, height: 500), to: safe))
        #expect(BottomObstructionCoordinator.isBottomAttached(
            CGRect(x: 16, y: 440, width: 992, height: 320), to: safe))
        #expect(!BottomObstructionCoordinator.isBottomAttached(
            CGRect(x: 0, y: 200, width: 1024, height: 240), to: safe))
    }

    @Test func rootChatSurvivesSwitchWithoutPermanentCleanup() async throws {
        guard #available(iOS 26.0, *) else { return }
        let tabs = AppTabBarController()
        let window = try makeVisibleTestWindow(rootViewController: tabs, size: CGSize(width: 768, height: 1024))
        defer { window.isHidden = true }
        tabs.select(.chat)
        let nav = try #require(tabs.featureControllers[.chat] as? UINavigationController)
        nav.loadViewIfNeeded()
        let chat = try #require(nav.viewControllers.first as? ChatViewController)
        chat.loadViewIfNeeded()
        #expect(await waitForCondition { !chat.isRestoringDraft })
        chat.composerView.textView.text = "Draft preserved"
        tabs.select(.examples)
        #expect(!chat.hasCleanedUpChat)
        tabs.select(.chat)
        #expect(nav.viewControllers.first === chat)
        #expect(chat.composerView.textView.text == "Draft preserved")
    }
}
