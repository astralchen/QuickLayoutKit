import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func mainMenuUsesNativeListContentAndDisclosureAccessories() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()
        let expectedSections = MainViewModel().state.sections

        #expect(main.view is QuickLayoutView)
        #expect(main.collectionView.superview === main.view)
        #expect(main.view.allSubviews(of: QuickLayoutScrollView.self).isEmpty)
        #expect(main.collectionView.numberOfSections == expectedSections.count)
        for (index, section) in expectedSections.enumerated() {
            #expect(main.collectionView.numberOfItems(inSection: index) == section.routes.count)
        }

        let cell = try mainMenuCell(at: IndexPath(item: 0, section: 0), in: main)
        let configuration = try #require(cell.contentConfiguration as? UIListContentConfiguration)
        #expect(configuration.text == "横向滚动")
        #expect(configuration.image != nil)
        #expect(configuration.textProperties.numberOfLines == 0)
        #expect(cell.accessories.count == 1)
        #expect(cell.accessibilityIdentifier == "demo.horizontalScroll.title")
        #expect(!cell.allSubviews(of: UIListContentView.self).isEmpty)
        for route in MainRoute.allCases {
            #expect(UIImage(systemName: route.iconSystemName) != nil)
        }
    }

    @Test func mainMenuReloadsRouteTitlesAfterLanguageChange() throws {
        Localization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            testWindow.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }

        let chineseTitles = try [0, 1, 4].map { item in
            try mainMenuConfiguration(
                at: IndexPath(item: item, section: 2),
                in: main
            ).text
        }

        #expect(chineseTitles == ["语言中心", "UIKit 本地化", "SwiftUI 桥接"])

        Localization.setLocale(identifier: "ar")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(.rightToLeft)
        main.view.layoutIfNeeded()

        let arabicConfiguration = try mainMenuConfiguration(
            at: IndexPath(item: 0, section: 2),
            in: main
        )
        let arabicCell = try #require(
            main.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 2)
            ) as? UICollectionViewListCell
        )

        #expect(
            arabicConfiguration.text
                == Localizer.live.text("demo.localizationOverview.title")
        )
        #expect(
            arabicCell.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }

    @Test func allLoadedUIKitDemoButtonsUseConfigurations() throws {
        Localization.setLocale(identifier: "en-US")
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            Localization.setLocale(identifier: "en-US")
        }

        let source = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: source
        )
        let testWindow = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }

        let router = MainRouter()
        var inspectedButtonCount = 0

        // SwiftUI owns the implementation behind SwiftUI.Button; this guard
        // covers the UIKit buttons authored by the Demo target.
        for route in MainRoute.allCases where route != .swiftUIBridge {
            router.navigate(to: route, from: source)
            let destination = try #require(
                navigationController.topViewController
            )
            destination.view.frame = navigationController.view.bounds
            destination.view.setNeedsLayout()
            navigationController.view.layoutIfNeeded()
            destination.view.layoutIfNeeded()

            let buttons = destination.view.allSubviews(of: UIButton.self)
            inspectedButtonCount += buttons.count
            for button in buttons {
                #expect(
                    button.configuration != nil,
                    "\(route) contains a legacy UIButton"
                )
            }

            navigationController.popViewController(animated: false)
        }

        #expect(inspectedButtonCount > 0)
    }

    @Test func mainMenuSectionHeaderMeasuresMultilineAccessibilityText() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let main = MainViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 320, height: 844),
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        defer { window.isHidden = true }
        let indexPath = IndexPath(item: 0, section: 0)
        #expect(await waitForCondition {
            window.layoutIfNeeded()
            main.view.layoutIfNeeded()
            main.collectionView.layoutIfNeeded()
            let header = main.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: indexPath
            )
            return (header?.bounds.height ?? 0) > 80
        })
        let header = try #require(main.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
        ) as? MainMenuSectionHeaderView)
        let textGuide = try #require(header.listContentView.textLayoutGuide)
        let textFrame = header.listContentView.convert(textGuide.layoutFrame, to: header)
        #expect(textFrame.minY >= 0)
        #expect(textFrame.maxY <= header.bounds.height + 1)
        let cell = try #require(main.collectionView.cellForItem(at: indexPath))
        #expect(cell.frame.minY >= header.frame.maxY - 1)
    }

    @Test func mainMenuSectionHeadersFollowNativeListDirection() throws {
        Localization.setLocale(identifier: "ar")
        defer { Localization.setLocale(identifier: "en-US") }
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.reloadLayoutDirection(.rightToLeft)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let header = try #require(main.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? MainMenuSectionHeaderView)
        #expect(header.listContentView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(header.accessibilityTraits.contains(.header))
        #expect((header.listContentView.configuration as? UIListContentConfiguration)?.text == Localization.text("main.section.quicklayout"))

        Localization.setLocale(identifier: "zh-Hans")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(.leftToRight)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()
        let restored = try #require(main.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? MainMenuSectionHeaderView)
        #expect(restored.listContentView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect((restored.listContentView.configuration as? UIListContentConfiguration)?.text == "QuickLayout 示例")
    }

    @Test func mainMenuRebuildsAndMirrorsItsNativeListContentRoundTrip() throws {
        let main = MainViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }
        main.reloadLayoutDirection(.leftToRight)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let leftToRightCollectionView = main.collectionView
        let leftToRightAnchor = try #require(
            leftToRightCollectionView.captureLocalizationAnchor()
        )
        let ltrCell = try mainMenuCell(at: indexPath, in: main)
        let contentView = try #require(
            ltrCell
                .allSubviews(of: UIListContentView.self)
                .first
        )
        let ltrTitleFrame = (try #require(contentView.textLayoutGuide)).layoutFrame
        let ltrImageFrame = (try #require(contentView.imageLayoutGuide)).layoutFrame

        main.reloadLayoutDirection(.rightToLeft)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()
        let rightToLeftCollectionView = main.collectionView
        let rightToLeftAnchor = try #require(
            rightToLeftCollectionView.captureLocalizationAnchor()
        )
        let rtlCell = try mainMenuCell(at: indexPath, in: main)
        let rtlContentView = try #require(
            rtlCell
                .allSubviews(of: UIListContentView.self)
                .first
        )
        let rtlTitleFrame = (try #require(rtlContentView.textLayoutGuide)).layoutFrame
        let rtlImageFrame = (try #require(rtlContentView.imageLayoutGuide)).layoutFrame

        #expect(rightToLeftCollectionView !== leftToRightCollectionView)
        #expect(leftToRightCollectionView.superview == nil)
        #expect(rightToLeftAnchor.indexPath == leftToRightAnchor.indexPath)
        #expect(
            abs(
                rightToLeftAnchor.offsetFromViewportTop
                    - leftToRightAnchor.offsetFromViewportTop
            ) < 1
        )
        #expect(
            rightToLeftCollectionView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(rtlCell.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlContentView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlTitleFrame.midX < rtlImageFrame.midX)
        #expect(ltrTitleFrame.midX > ltrImageFrame.midX)
        #expect(rtlImageFrame.minX > ltrImageFrame.minX)

        main.reloadLayoutDirection(.leftToRight)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()
        let returnedCollectionView = main.collectionView
        let returnedAnchor = try #require(
            returnedCollectionView.captureLocalizationAnchor()
        )
        let restoredCell = try mainMenuCell(at: indexPath, in: main)
        let restoredContentView = try #require(
            restoredCell
                .allSubviews(of: UIListContentView.self)
                .first
        )

        #expect(returnedCollectionView !== rightToLeftCollectionView)
        #expect(rightToLeftCollectionView.superview == nil)
        #expect(returnedAnchor.indexPath == leftToRightAnchor.indexPath)
        #expect(
            abs(
                returnedAnchor.offsetFromViewportTop
                    - leftToRightAnchor.offsetFromViewportTop
            ) < 1
        )
        #expect(
            returnedCollectionView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(restoredCell.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            restoredContentView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(
            (try #require(restoredContentView.textLayoutGuide)).layoutFrame.approximatelyEquals(ltrTitleFrame)
        )
    }

    @Test func mainMenuSearchRoutesTheFilteredItemAndClearsItsEmptyState() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let router = RecordingMainRouter()
        let main = MainViewController(viewModel: MainViewModel(), router: router)
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let search = try #require(main.navigationItem.searchController)
        search.searchBar.text = Localization.text("demo.counter.title")
        main.updateSearchResults(for: search)
        #expect(await waitForCondition {
            main.collectionView.numberOfSections == 1
                && main.collectionView.numberOfItems(inSection: 0) == 1
        })
        main.view.layoutIfNeeded()
        #expect(main.collectionView.numberOfSections == 1)
        #expect(main.collectionView.numberOfItems(inSection: 0) == 1)
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try mainMenuCell(at: indexPath, in: main)
        #expect(cell.accessibilityIdentifier == "demo.counter.title")
        main.collectionView.delegate?.collectionView?(main.collectionView, didSelectItemAt: indexPath)
        #expect(router.routes == [.counter])

        search.searchBar.text = "does-not-exist"
        main.updateSearchResults(for: search)
        #expect(await waitForCondition { main.collectionView.numberOfSections == 0 })
        #expect(main.collectionView.numberOfSections == 0)
        if #available(iOS 17.0, *) {
            #expect(main.contentUnavailableConfiguration != nil)
        } else {
            #expect(main.collectionView.backgroundView != nil)
        }
        search.searchBar.text = ""
        main.updateSearchResults(for: search)
        #expect(await waitForCondition { main.collectionView.numberOfSections == 3 })
        #expect(main.collectionView.numberOfSections == 3)
        if #available(iOS 17.0, *) {
            #expect(main.contentUnavailableConfiguration == nil)
        } else {
            #expect(main.collectionView.backgroundView == nil)
        }
    }

    @Test func mainMenuClearsSelectionWhenReturningToTheCatalog() throws {
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.layoutIfNeeded()
        let indexPath = IndexPath(item: 0, section: 0)
        _ = try mainMenuCell(at: indexPath, in: main)
        main.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        main.viewWillAppear(false)
        #expect(main.collectionView.indexPathsForSelectedItems?.isEmpty != false)
    }

    @Test func mainMenuSelectionRoutesThroughListKit() throws {
        let router = RecordingMainRouter()
        let main = MainViewController(
            viewModel: MainViewModel(),
            router: router
        )
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        _ = try mainMenuCell(at: indexPath, in: main)
        main.collectionView.delegate?.collectionView?(
            main.collectionView,
            didSelectItemAt: indexPath
        )

        #expect(router.routes == [.horizontalScroll])
    }
}

@MainActor
private func mainMenuCell(
    at indexPath: IndexPath,
    in viewController: MainViewController
) throws -> UICollectionViewListCell {
    viewController.collectionView.scrollToItem(
        at: indexPath,
        at: .centeredVertically,
        animated: false
    )
    viewController.collectionView.setNeedsLayout()
    viewController.collectionView.layoutIfNeeded()
    return try #require(
        viewController.collectionView.cellForItem(at: indexPath)
            as? UICollectionViewListCell
    )
}

@MainActor
private func mainMenuConfiguration(
    at indexPath: IndexPath,
    in viewController: MainViewController
) throws -> UIListContentConfiguration {
    let cell = try mainMenuCell(at: indexPath, in: viewController)
    return try #require(
        cell.contentConfiguration as? UIListContentConfiguration
    )
}

@MainActor
private final class RecordingMainRouter: MainRouting {

    private(set) var routes: [MainRoute] = []

    func navigate(
        to route: MainRoute,
        from sourceViewController: UIViewController
    ) {
        routes.append(route)
    }
}
