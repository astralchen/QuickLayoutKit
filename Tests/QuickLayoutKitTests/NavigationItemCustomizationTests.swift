import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct NavigationItemCustomizationTests {
    @available(iOS 16.0, *)
    @Test func renamingReplacesAndReleasesOnlyItsOwnHandler() {
        let item = UINavigationItem()
        var edits: [String] = []
        item.navigationTitle("First") { edits.append($0) }
        weak var previousHandler = item.renameDelegate
        item.renameDelegate?.navigationItem(item, didEndRenamingWith: "Second")
        item.navigationTitle("Updated") { edits.append("Updated " + $0) }
        #expect(previousHandler == nil)
        item.renameDelegate?.navigationItem(item, didEndRenamingWith: "Third")
        #expect(edits == ["Second", "Updated Third"])
        item.navigationTitle("Read only", onRename: nil)
        #expect(item.renameDelegate == nil)
        final class AppDelegate: UINavigationItemRenameDelegate {
            func navigationItem(_ navigationItem: UINavigationItem, didEndRenamingWith title: String) {}
        }
        let external = AppDelegate()
        item.navigationTitle("Editable") { _ in }
        previousHandler = item.renameDelegate
        item.renameDelegate = external
        item.navigationTitle("Externally managed", onRename: nil)
        #expect(item.renameDelegate === external)
        #expect(previousHandler == nil)
    }

    @available(iOS 16.0, *)
    @Test func documentAndBackActionCanBeInstalledAndRemoved() {
        let item = UINavigationItem()
        let url = URL(fileURLWithPath: "/tmp/Example.txt")
        let properties = UIDocumentProperties(url: url)
        let action = UIAction(title: "Back") { _ in }
        item.navigationDocument(url)
        #expect(item.documentProperties != nil)
        item.navigationDocument(properties).navigationBarBackAction(action)
        #expect(item.documentProperties === properties)
        #expect(item.backAction?.identifier == action.identifier)
        item.navigationDocument(nil).navigationBarBackAction(nil)
        #expect(item.documentProperties == nil)
        #expect(item.backAction == nil)
    }

    @available(iOS 16.0, *)
    @Test func groupsReplaceTheirOwnPositionAndOverflowCanBeCleared() {
        let page = UIViewController()
        let item = page.navigationItem
        func group() -> UIBarButtonItemGroup {
            UIBarButtonItemGroup(barButtonItems: [UIBarButtonItem()], representativeItem: nil)
        }
        let leading = group(), center = group(), trailing = group(), pinned = group()
        let oldButton = UIBarButtonItem()
        page.toolbar(placement: .topBarLeading) { oldButton }
        item.toolbar(id: "editor").toolbarRole(.editor)
            .toolbar(placement: .topBarLeading) { leading }
            .toolbar(placement: .center) { center }
            .toolbar(placement: .topBarTrailing) { trailing }
            .toolbar(placement: .topBarPinnedTrailing) { pinned }
        #expect(item.customizationIdentifier == "editor")
        #expect(item.leadingItemGroups == [leading])
        #expect(item.leftBarButtonItem !== oldButton)
        #expect(item.centerItemGroups == [center])
        #expect(item.trailingItemGroups == [trailing])
        #expect(item.pinnedTrailingGroup === pinned)
        item.toolbarOverflowMenu { UIAction(title: "Share") { _ in } }
        #expect(item.additionalOverflowItems != nil)
        item.toolbarOverflowMenu {}
        #expect(item.additionalOverflowItems == nil)
        item.toolbar(placement: .topBarTrailing) {}.toolbar(placement: .topBarPinnedTrailing) { nil }
        #expect(item.trailingItemGroups.isEmpty)
        #expect(item.pinnedTrailingGroup == nil)
        #expect(item.centerItemGroups == [center])
    }

    @available(iOS 17.0, *)
    @Test func toolbarTitleDisplayModeMatchesNavigationTitleDisplayMode() {
        let item = UINavigationItem()
        item.toolbarTitleDisplayMode(.inlineLarge)
        #expect(item.largeTitleDisplayMode == .inline)
        item.toolbarTitleDisplayMode(.inline)
        #expect(item.largeTitleDisplayMode == .never)
    }

    @available(iOS 26.0, *)
    @Test func largeAndAttributedTitlesAndSubtitleViewsUseTheirNativeSlots() {
        let page = UIViewController()
        let item = page.navigationItem
        let rich = AttributedString("Attributed")
        item.navigationTitle(attributed: rich).navigationSubtitle(attributed: rich)
            .navigationLargeSubtitle(attributed: rich)
        #expect(item.attributedTitle == rich)
        #expect(item.attributedSubtitle == rich)
        #expect(item.largeAttributedSubtitle == rich)
        let subtitle = UILabel(), largeSubtitle = UILabel()
        page.toolbar(placement: .subtitle) { subtitle }
            .toolbar(placement: .largeSubtitle) { largeSubtitle }
            .toolbar(placement: .largeTitle) { "Expanded" }
        #expect(item.subtitleView === subtitle)
        #expect(item.largeSubtitleView === largeSubtitle)
        #expect(item.largeTitle == "Expanded")
        page.toolbar(placement: .largeTitle) { nil }
            .toolbar(placement: .subtitle) { nil }
            .toolbar(placement: .largeSubtitle) { nil }
        item.navigationLargeSubtitle(attributed: nil).navigationLargeSubtitle("Detail")
        #expect(item.largeTitle == nil)
        #expect(item.subtitleView == nil)
        #expect(item.largeSubtitleView == nil)
        #expect(item.largeSubtitle == "Detail")
    }

    @available(iOS 26.0, *)
    @Test func searchPlacementAndIndependentIntegrationPreferences() {
        let page = UIViewController()
        let item = page.navigationItem
        let search = UISearchController(searchResultsController: nil)
        item.searchable(search, placement: .integratedCentered)
            .searchToolbarIntegration(false).searchExternalIntegration(true)
        #expect(item.preferredSearchBarPlacement == .integratedCentered)
        item.searchable(search, placement: .integrated)
        #expect(item.preferredSearchBarPlacement == .integrated)
        item.searchable(search, placement: .integratedButton)
        #expect(item.preferredSearchBarPlacement == .integratedButton)
        item.searchToolbarBehavior(.automatic)
        #expect(item.preferredSearchBarPlacement == .automatic)
        item.searchToolbarBehavior(.minimize)
        #expect(item.preferredSearchBarPlacement == .integratedButton)
        #expect(!item.searchBarPlacementAllowsToolbarIntegration)
        #expect(item.searchBarPlacementAllowsExternalIntegration)
        item.searchToolbarIntegration(true)
        page.toolbar(placement: .bottomBar) { item.searchBarPlacementBarButtonItem }
        #expect(page.toolbarItems?.first === item.searchBarPlacementBarButtonItem)
        #expect(item.searchController === search)
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    @Test func minimizationModifiersPreserveSiblingSettings() {
        let item = UINavigationItem()
        item.toolbarMinimizationBehavior(.onScrollDown)
            .toolbarMinimizationRestoration(.atScrollEdge)
            .toolbarMinimizationSafeAreaAdjustment(.disabled)
        #expect(item.navigationBarMinimization.minimizationBehavior == .onScrollDown)
        #expect(item.navigationBarMinimization.restorationBehavior == .atScrollEdge)
        #expect(item.navigationBarMinimization.safeAreaAdjustment == .disabled)
    }
    #endif

    #if compiler(>=6.4.1)
    @available(iOS 27.1, *)
    @Test func verticalCompressionMapsToTheItem() {
        let item = UINavigationItem().toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        #expect(item.verticalBarCompressionBehavior == .prefersBarItems)
    }
    #endif

    #if compiler(>=6.4.2)
    @available(iOS 27.2, *)
    @Test func titleAlignmentCanReturnToAutomatic() {
        let item = UINavigationItem().toolbarTitleAlignment(.center)
        #expect(item.titleAlignment == .center)
        item.toolbarTitleAlignment(.automatic)
        #expect(item.titleAlignment == .automatic)
    }
    #endif
}
