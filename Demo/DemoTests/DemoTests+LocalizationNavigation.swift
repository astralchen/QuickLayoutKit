import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func arabicDiagnosticScreensRenderLocalizedText() throws {
        Localization.setLocale(identifier: "ar")
        defer { Localization.setLocale(identifier: "en-US") }

        let navigation = DirectionalNavigationDemoViewController()
        navigation.loadViewIfNeeded()
        let navigationTexts = navigation.view
            .allSubviews(of: UILabel.self)
            .compactMap(\.text)
            .map(\.removingBidiIsolationMarks)
        #expect(
            navigationTexts.contains(
                "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
            )
        )

        let gesture = SemanticGestureDemoViewController()
        gesture.loadViewIfNeeded()
        let gestureTexts = gesture.view
            .allSubviews(of: UILabel.self)
            .compactMap(\.text)
            .map(\.removingBidiIsolationMarks)
        #expect(
            gestureTexts.contains(
                "لم يتم السحب\nالإزاحة الأفقية: 0\nإيماءة الرجوع: لا"
            )
        )

        let keyboardView = AnimatedKeyboardResponsiveView()
        let keyboardDiagnostics = try #require(
            keyboardView.diagnosticsLabel.text
        )
        #expect(keyboardDiagnostics.contains("الحدث:"))
        #expect(keyboardDiagnostics.contains("الإطار الأصلي:"))
        #expect(keyboardDiagnostics.contains("منطقة التقاطع:"))
        #expect(keyboardDiagnostics.contains("الارتفاع:"))
        #expect(!keyboardDiagnostics.contains("event:"))
        #expect(!keyboardDiagnostics.contains("raw:"))
        #expect(!keyboardDiagnostics.contains("intersection:"))
        #expect(!keyboardDiagnostics.contains("height:"))
    }

    @Test func directionalNavigationKeepsSystemBackButtonWithDemoItems() {
        let root = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: root
        )
        let destination = DirectionalNavigationDemoViewController()

        navigationController.pushViewController(destination, animated: false)
        destination.loadViewIfNeeded()

        #expect(navigationController.viewControllers.count == 2)
        #expect(destination.navigationItem.leftBarButtonItem != nil)
        #expect(destination.navigationItem.leftItemsSupplementBackButton)
        #expect(!destination.navigationItem.hidesBackButton)
    }

    @Test func localizationChangeSeparatesLocaleAndDirectionReasons() {
        let leftToRightChange = LocalizationChange(
            previous: LocalizationSnapshot(
                locale: .englishUS,
                followsSystemLocale: false,
                revision: 0
            ),
            current: LocalizationSnapshot(
                locale: .simplifiedChinese,
                followsSystemLocale: false,
                revision: 1
            )
        )
        let rightToLeftChange = LocalizationChange(
            previous: LocalizationSnapshot(
                locale: .englishUS,
                followsSystemLocale: false,
                revision: 0
            ),
            current: LocalizationSnapshot(
                locale: .arabic,
                followsSystemLocale: false,
                revision: 1
            )
        )

        #expect(leftToRightChange.localeChanged)
        #expect(!leftToRightChange.layoutDirectionChanged)
        #expect(rightToLeftChange.localeChanged)
        #expect(rightToLeftChange.layoutDirectionChanged)
    }

    @Test func languageMenuUsesUIKitMirroringAcrossDirectionChanges() throws {
        let viewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }

        Localization.setLocale(identifier: "zh-Hans")
        Localization.installLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceLeftToRight
        navigationController.view.layoutIfNeeded()

        let languageItem = viewController.navigationItem.rightBarButtonItem
        #expect(languageItem != nil)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        let leftToRightItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let leftToRightFrame = leftToRightItemView.convert(
            leftToRightItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            leftToRightFrame.midX
                > navigationController.navigationBar.bounds.midX
        )

        Localization.setLocale(identifier: "ar")
        Localization.reloadLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceRightToLeft
        navigationController.navigationBar.setNeedsLayout()
        navigationController.navigationBar.layoutIfNeeded()

        #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        #expect(!viewController.navigationItem.hidesBackButton)
        let rightToLeftItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let rightToLeftFrame = rightToLeftItemView.convert(
            rightToLeftItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            rightToLeftFrame.midX
                < navigationController.navigationBar.bounds.midX
        )

        Localization.setLocale(identifier: "zh-Hans")
        Localization.reloadLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceLeftToRight
        navigationController.navigationBar.setNeedsLayout()
        navigationController.navigationBar.layoutIfNeeded()

        #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        let returnedItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let returnedFrame = returnedItemView.convert(
            returnedItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            returnedFrame.midX
                > navigationController.navigationBar.bounds.midX
        )
    }

    @Test func plainNavigationPreviewReceivesLanguageMenuSelections() async throws {
        Localization.setLocale(identifier: "en-US")

        let profileViewController = ProfileViewController()
        let navigationController = UINavigationController(
            rootViewController: profileViewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )

        defer {
            Localization.unregister(window: window)
            window.isHidden = true
            Localization.setLocale(identifier: "en-US")
        }

        #expect(profileViewController.title == "Profile")

        Localization.setLocale(identifier: "ar")
        let appliedArabic = await waitForCondition {
            profileViewController.title
                == Localization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceRightToLeft
                && profileViewController.view.semanticContentAttribute
                    == .forceRightToLeft
        }
        #expect(appliedArabic)

        Localization.setLocale(identifier: "zh-Hans")
        let appliedChinese = await waitForCondition {
            profileViewController.title
                == Localization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceLeftToRight
                && profileViewController.view.semanticContentAttribute
                    == .forceLeftToRight
        }
        #expect(appliedChinese)
    }

    @Test func explicitViewTargetsFollowTheWindowDirectionRoundTrip() throws {
        let rootViewController = UIViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: rootViewController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }
        let inheritedContainer = UIView()
        let inheritedLabel = UILabel()
        inheritedContainer.addSubview(inheritedLabel)
        rootViewController.view.addSubview(inheritedContainer)
        window.semanticContentAttribute = .forceRightToLeft
        UIViewLayoutDirectionUpdater.apply(
            Localization.layoutDirectionUpdate(.rightToLeft),
            to: [rootViewController.view, inheritedContainer, inheritedLabel]
                .map {
                    UIViewLayoutDirectionTarget(
                        $0,
                        policy: .followApplication
                    )
                }
        )
        window.layoutIfNeeded()

        #expect(window.semanticContentAttribute == .forceRightToLeft)
        #expect(rootViewController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(inheritedContainer.semanticContentAttribute == .forceRightToLeft)
        #expect(inheritedLabel.semanticContentAttribute == .forceRightToLeft)
        #expect(
            inheritedLabel.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )

        window.semanticContentAttribute = .forceLeftToRight
        UIViewLayoutDirectionUpdater.apply(
            Localization.layoutDirectionUpdate(.leftToRight),
            to: [rootViewController.view, inheritedContainer, inheritedLabel]
                .map {
                    UIViewLayoutDirectionTarget(
                        $0,
                        policy: .followApplication
                    )
                }
        )
        window.layoutIfNeeded()

        #expect(window.semanticContentAttribute == .forceLeftToRight)
        #expect(inheritedContainer.semanticContentAttribute == .forceLeftToRight)
        #expect(inheritedLabel.semanticContentAttribute == .forceLeftToRight)
        #expect(
            inheritedLabel.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
    }
}
