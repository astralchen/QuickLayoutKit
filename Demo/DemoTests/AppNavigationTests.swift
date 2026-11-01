import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct AppNavigationTests {
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
        #expect(routes.count == 26)
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
        let split = try #require(tabs.featureControllers[.examples] as? DemoSplitViewController)
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
        let split = try #require(tabs.featureControllers[.examples] as? DemoSplitViewController)
        #expect(await waitForCondition { !split.isCollapsed })
        split.select(.counter)
        let detail = try #require(split.detailNavigationController.viewControllers.first)
        tabs.traitOverrides.horizontalSizeClass = .compact
        window.frame.size = CGSize(width: 390, height: 768)
        window.layoutIfNeeded()
        #expect(await waitForCondition { split.isCollapsed && detail.view.window === window })
        #expect(split.selectedRoute == .counter)
        split.show(.primary)
        #expect(await waitForCondition { split.menuController.view.window === window })
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
