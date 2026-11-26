import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct NavigationToolbarTests {
    @Test func titleAndBackButtonModifiersUpdateTheNavigationItem() {
        let page = UIViewController()
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = false
        let item = page.navigationItem
        let result = item.navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden()

        #expect(result === item)
        #expect(item.title == "Editor")
        #expect(item.largeTitleDisplayMode == .always)
        #expect(!navigation.navigationBar.prefersLargeTitles)
        #expect(item.hidesBackButton)
        item.navigationBarTitleDisplayMode(.inline)
        #expect(item.largeTitleDisplayMode == .never)
        if #available(iOS 17.0, *) {
            item.navigationBarTitleDisplayMode(.inlineLarge)
            #expect(item.largeTitleDisplayMode == .inline)
            #expect(!navigation.navigationBar.prefersLargeTitles)
        }
        item.navigationTitle(nil).navigationBarTitleDisplayMode(.automatic).navigationBarBackButtonHidden(false)
        #expect(item.title == nil)
        #expect(item.largeTitleDisplayMode == .automatic)
        #expect(!item.hidesBackButton)
    }

    @Test func changingOneTopBarPlacementPreservesItsNeighbors() {
        let page = UIViewController()
        let item = page.navigationItem
        let titleView = UISegmentedControl()
        let leading = UIBarButtonItem()
        let first = UIBarButtonItem()
        let second = UIBarButtonItem()
        item.navigationTitle("Editor")
        item.navigationBarLeadingItemsSupplementBackButton()
        page.toolbar(placement: .principal) { titleView }
            .toolbar(placement: .topBarLeading) { leading }
            .toolbar(placement: .topBarTrailing) {
                first
                second
            }
        #expect(item.rightBarButtonItems == [first, second])
        page.toolbar(placement: .topBarTrailing) { second }
        #expect(item.rightBarButtonItems == [second])
        page.toolbar(placement: .topBarTrailing) {}
        #expect(item.rightBarButtonItems?.isEmpty != false)
        #expect(item.leftBarButtonItem === leading)
        #expect(item.leftItemsSupplementBackButton)
        #expect(item.titleView === titleView)
        let replacement = UILabel()
        page.toolbar(placement: .title) { replacement }
        #expect(item.titleView === replacement)
        page.toolbar(placement: .title) { nil }
        #expect(item.titleView == nil)
        #expect(item.title == "Editor")
        item.navigationBarLeadingItemsSupplementBackButton(false)
        #expect(!item.leftItemsSupplementBackButton)
        #expect(item.leftBarButtonItem === leading)
    }

    @Test func searchDrawerCanChangeModesAndReuseOrRemoveTheSearchController() {
        let item = UINavigationItem()
        let search = UISearchController(searchResultsController: nil)
        search.searchBar.text = "saved"
        search.searchBar.placeholder = "Original"
        item.searchable(search, placement: .navigationBarDrawer(displayMode: .always))
        #expect(item.searchController === search)
        #expect(!item.hidesSearchBarWhenScrolling)
        #expect(search.searchBar.placeholder == "Original")
        if #available(iOS 16.0, *) { #expect(item.preferredSearchBarPlacement == .stacked) }
        item.searchable(search, placement: .navigationBarDrawer, prompt: "Find")
        #expect(item.hidesSearchBarWhenScrolling)
        #expect(search.searchBar.placeholder == "Find")
        item.searchable(search)
        if #available(iOS 16.0, *) { #expect(item.preferredSearchBarPlacement == .automatic) }
        #expect(search.searchBar.text == "saved")
        item.searchable(nil)
        #expect(item.searchController == nil)
    }

    @Test func forwardsBackButtonAnimationPreferenceToUIKit() {
        final class RecordingItem: UINavigationItem {
            var lastAnimated: Bool?
            override func setHidesBackButton(_ hidesBackButton: Bool, animated: Bool) {
                lastAnimated = animated
                super.setHidesBackButton(hidesBackButton, animated: animated)
            }
        }
        let item = RecordingItem(title: "Detail")
        item.navigationBarBackButtonHidden(animated: true)
        #expect(item.hidesBackButton)
        #expect(item.lastAnimated == true)
        item.navigationBarBackButtonHidden(false)
        #expect(!item.hidesBackButton)
        #expect(item.lastAnimated == false)
    }

    @available(iOS 16.0, *)
    @Test func titleMenuReceivesSuggestedActionsAndCanBeRemoved() throws {
        let item = UINavigationItem()
        let suggested = UIAction(title: "Rename") { _ in }
        let extra = UIAction(title: "Share") { _ in }
        item.toolbarTitleMenu { actions in UIMenu(children: actions + [extra]) }
        let menu = try #require(item.titleMenuProvider?([suggested]))
        #expect(menu.children.map(\.title) == ["Rename", "Share"])
        item.toolbarTitleMenu(nil)
        #expect(item.titleMenuProvider == nil)
    }

    @available(iOS 16.0, *)
    @Test func toolbarRolesUseNativeNavigationItemStyles() {
        let item = UINavigationItem()
        item.toolbarRole(.editor)
        #expect(item.style == .editor)
        item.toolbarRole(.browser)
        #expect(item.style == .browser)
        item.toolbarRole(.navigationStack)
        #expect(item.style == .navigator)
    }

    @available(iOS 26.0, *)
    @Test func subtitleCanBeChangedAndClearedIndependentlyOfTitle() {
        let item = UINavigationItem(title: "Library")
        item.navigationSubtitle("Favorites")
        #expect(item.subtitle == "Favorites")
        item.navigationSubtitle(nil)
        #expect(item.subtitle == nil)
        #expect(item.title == "Library")
    }

    @Test func backButtonTitleBelongsToThePreviousNavigationItem() {
        let root = UIViewController()
        let detail = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        root.navigationItem.navigationBarBackButtonTitle("Library").navigationBarBackButtonDisplayMode(.minimal)
        navigation.pushViewController(detail, animated: false)
        #expect(navigation.navigationBar.backItem === root.navigationItem)
        #expect(root.navigationItem.backButtonTitle == "Library")
        #expect(root.navigationItem.backButtonDisplayMode == .minimal)
        #expect(!detail.navigationItem.hidesBackButton)
        root.navigationItem.navigationBarBackButtonTitle(nil).navigationBarBackButtonDisplayMode(.default)
        #expect(root.navigationItem.backButtonTitle == nil)
        #expect(root.navigationItem.backButtonDisplayMode == .default)
    }

    @Test func navigationAppearanceCanBeAppliedAndClearedAcrossAllMetrics() {
        let item = UINavigationItem()
        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .systemRed
        item.navigationBarAppearance(appearance)
        #expect(item.standardAppearance?.backgroundColor == .systemRed)
        #expect(item.compactAppearance?.backgroundColor == .systemRed)
        #expect(item.scrollEdgeAppearance?.backgroundColor == .systemRed)
        #expect(item.compactScrollEdgeAppearance?.backgroundColor == .systemRed)
        item.navigationBarAppearance(nil)
        #expect(item.standardAppearance == nil)
        #expect(item.compactAppearance == nil)
        #expect(item.scrollEdgeAppearance == nil)
        #expect(item.compactScrollEdgeAppearance == nil)
    }

    @Test func emptyExpressionsAndOptionalItemsContributeOnlyPresentButtons() {
        let bar = UIToolbar()
        let first = UIBarButtonItem()
        let last: UIBarButtonItem? = UIBarButtonItem()
        let missing: UIBarButtonItem? = nil
        bar.items {
            ()
            first
            nil
            missing
            first.isEnabled = false
            last
        }
        #expect(bar.items == [first] + [last].compactMap { $0 })
        #expect(!first.isEnabled)
        bar.items { () }
        #expect(bar.items?.isEmpty != false)
    }

    @Test func bottomItemsBelongToEachPageAndPreserveToolbarVisibility() {
        let root = UIViewController()
        let detail = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let rootAction = UIBarButtonItem()
        let detailAction = UIBarButtonItem()
        root.toolbar(placement: .bottomBar) { rootAction }
        detail.toolbar(placement: .bottomBar) { detailAction }
        #expect(navigation.isToolbarHidden)
        navigation.setToolbarHidden(false, animated: false)
        navigation.pushViewController(detail, animated: false)
        #expect(navigation.topViewController?.toolbarItems == [detailAction])
        detail.toolbar(placement: .bottomBar) {}
        #expect(detail.toolbarItems?.isEmpty != false)
        #expect(!navigation.isToolbarHidden)
        navigation.popViewController(animated: false)
        #expect(navigation.topViewController?.toolbarItems == [rootAction])
    }

    @Test func pageToolbarItemsForwardAnimationBeforeJoiningAStack() {
        final class Page: UIViewController {
            var animations: [Bool] = []
            override func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?, animated: Bool) {
                animations.append(animated)
                super.setToolbarItems(toolbarItems, animated: animated)
            }
        }
        let page = Page()
        let item = UIBarButtonItem()
        let missing: UIBarButtonItem? = nil
        let result = page.toolbarItems(animated: true) {
            missing
            item
        }
        #expect(result === page)
        #expect(page.toolbarItems == [item])
        page.toolbarItems {}
        #expect(page.toolbarItems?.isEmpty != false)
        #expect(page.animations == [true, false])
        page.setToolbarItems(nil, animated: false)
        #expect(page.toolbarItems == nil)
    }

    @Test func containerToolbarConfiguresOnlyTheTopPage() {
        let navigation = UINavigationController()
        var evaluated = false
        navigation.toolbar { evaluated = true }
        #expect(!evaluated)
        let root = UIViewController()
        let detail = UIViewController()
        let first = UIBarButtonItem()
        let second = UIBarButtonItem()
        navigation.setViewControllers([root], animated: false)
        let result = navigation.toolbar { first }.toolbarVisibility(.visible)
        #expect(result === navigation)
        #expect(!navigation.isToolbarHidden)
        navigation.pushViewController(detail, animated: false)
        navigation.toolbar(animated: true) { second }
        #expect(root.toolbarItems == [first])
        #expect(detail.toolbarItems == [second])
        navigation.toolbar {}
        #expect(detail.toolbarItems?.isEmpty != false)
        #expect(!navigation.isToolbarHidden)
        navigation.popViewController(animated: false)
        #expect(navigation.topViewController?.toolbarItems == [first])
        navigation.toolbarVisibility(.hidden, for: .navigationBar)
        #expect(navigation.isNavigationBarHidden)
        #expect(!navigation.isToolbarHidden)
        navigation.toolbarVisibility(.visible, for: .navigationBar).toolbarVisibility(.hidden)
        #expect(navigation.isToolbarHidden)
        #expect(!navigation.isNavigationBarHidden)
    }

    @Test func managedToolbarAppearanceAndHidingConditions() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let appearance = UIToolbarAppearance()
        appearance.backgroundColor = .red
        navigation.toolbarAppearance(appearance)
        let bar = navigation.toolbar!
        #expect(bar.standardAppearance.backgroundColor == .red)
        #expect(bar.compactAppearance?.backgroundColor == .red)
        #expect(bar.scrollEdgeAppearance?.backgroundColor == .red)
        #expect(bar.compactScrollEdgeAppearance?.backgroundColor == .red)
        navigation.barsHidingBehavior([.onSwipe, .whenKeyboardAppears])
        #expect(navigation.hidesBarsOnSwipe && navigation.hidesBarsWhenKeyboardAppears)
        navigation.barsHidingBehavior([.onTap, .whenVerticallyCompact])
        #expect(!navigation.hidesBarsOnSwipe && !navigation.hidesBarsWhenKeyboardAppears)
        #expect(navigation.hidesBarsOnTap && navigation.hidesBarsWhenVerticallyCompact)
        navigation.barsHidingBehavior([])
        #expect(!navigation.hidesBarsOnTap && !navigation.hidesBarsWhenVerticallyCompact)
    }

    @Test func standaloneToolbarEvaluatesConditionsAndLoopsInOrder() {
        let bar = UIToolbar()
        let previous = UIBarButtonItem()
        let next = UIBarButtonItem()
        let space = UIBarButtonItem.flexibleSpace()
        let actions = [UIBarButtonItem(), UIBarButtonItem()]
        for includePrevious in [true, false] {
            let optional = includePrevious ? space : nil
            bar.items(animated: false) {
                if includePrevious {
                    previous
                } else {
                    next
                }
                if let optional { optional }
                for item in actions { item }
            }
            let expected = (includePrevious ? [previous, space] : [next]) + actions
            #expect(bar.items == expected)
        }
        bar.items {}
        #expect(bar.items?.isEmpty != false)
    }
}
