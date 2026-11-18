import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension ApplicationTests {

    @Test func arabicDiagnosticScreensRenderLocalizedText() throws {
        Localization.setLocale(identifier: "ar")
        defer { Localization.setLocale(identifier: "en") }

        let navigation = DirectionalNavigationViewController()
        let navigationHost = UINavigationController(rootViewController: navigation)
        let navigationWindow = try makeVisibleTestWindow(rootViewController: navigationHost)
        defer { navigationWindow.isHidden = true }
        layout(navigation, in: navigationHost)
        let navigationTexts = navigation.view
            .allSubviews(of: UILabel.self)
            .compactMap(\.text)
            .map(\.removingBidiIsolationMarks)
        #expect(
            navigationTexts.contains(
                "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
            )
        )

        let gesture = SemanticGestureViewController()
        let gestureHost = UINavigationController(rootViewController: gesture)
        let gestureWindow = try makeVisibleTestWindow(rootViewController: gestureHost)
        defer { gestureWindow.isHidden = true }
        layout(gesture, in: gestureHost)
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
        #expect(keyboardView.diagnosticsLabel.text?.contains("لم يصل أي إشعار للوحة المفاتيح بعد") == true)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil, userInfo: [
            UIResponder.keyboardFrameEndUserInfoKey: CGRect.zero,
        ])
        let keyboardDiagnostics = try #require(
            keyboardView.diagnosticsLabel.text
        ).removingBidiIsolationMarks
        #expect(keyboardDiagnostics.contains("آخر حدث: willHide"))
        #expect(keyboardDiagnostics.contains("مرئية على الشاشة: لا"))
        #expect(keyboardDiagnostics.contains("الإطار الأصلي:"))
        #expect(keyboardDiagnostics.contains("منطقة التقاطع:"))
        #expect(keyboardDiagnostics.contains("الارتفاع:"))
        #expect(!keyboardDiagnostics.contains("event:"))
        #expect(!keyboardDiagnostics.contains("raw:"))
        #expect(!keyboardDiagnostics.contains("intersection:"))
        #expect(!keyboardDiagnostics.contains("height:"))
    }

    @Test func directionalNavigationKeepsSystemBackButtonWithItems() {
        let root = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: root
        )
        let destination = DirectionalNavigationViewController()

        navigationController.pushViewController(destination, animated: false)
        destination.loadViewIfNeeded()

        #expect(navigationController.viewControllers.count == 2)
        #expect(destination.navigationItem.leftBarButtonItem != nil)
        #expect(destination.navigationItem.leftItemsSupplementBackButton)
        #expect(!destination.navigationItem.hidesBackButton)
    }

    @Test func localizationUpdateSeparatesContentAndDirectionChanges() {
        let leftToRightChange = LocalizationUpdate(
            snapshot: LocalizationSnapshot(
                locale: AppLocale(identifier: "zh-Hans"),
                followsSystemLocale: false,
                revision: 0
            ),
            previousSnapshot: LocalizationSnapshot(
                locale: AppLocale(identifier: "en"),
                followsSystemLocale: false,
                revision: 1
            )
        )
        let rightToLeftChange = LocalizationUpdate(
            snapshot: LocalizationSnapshot(
                locale: AppLocale(identifier: "ar"),
                followsSystemLocale: false,
                revision: 0
            ),
            previousSnapshot: LocalizationSnapshot(
                locale: AppLocale(identifier: "en"),
                followsSystemLocale: false,
                revision: 1
            )
        )

        #expect(leftToRightChange.requiresLocalizedContentRefresh)
        #expect(!leftToRightChange.requiresLayoutDirectionRefresh)
        #expect(rightToLeftChange.requiresLocalizedContentRefresh)
        #expect(rightToLeftChange.requiresLayoutDirectionRefresh)
    }

    /// 真实按钮位置由 TabLocalizationUITests 验证；此处只访问公开的导航项状态。
    @Test func languageMenuKeepsTrailingItemAcrossDirectionChanges() throws {
        let viewController = UIViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
            Localization.setLocale(identifier: "en")
        }
        Localization.setLocale(identifier: "zh-Hans")
        Localization.installLanguageMenu(on: viewController)
        let languageItem = try #require(viewController.navigationItem.rightBarButtonItem)
        for locale in ["zh-Hans", "ar", "zh-Hans"] {
            Localization.setLocale(identifier: locale)
            Localization.reloadLanguageMenu(on: viewController)
            navigationController.navigationBar.semanticContentAttribute = locale == "ar"
                ? .forceRightToLeft : .forceLeftToRight
            navigationController.view.layoutIfNeeded()
            #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
            #expect(viewController.navigationItem.leftBarButtonItem == nil)
            #expect(!viewController.navigationItem.hidesBackButton)
            #expect(languageItem.accessibilityIdentifier == "demo.language.menu")
            #expect(languageItem.accessibilityLabel == Localization.text("language.menu.accessibility"))
            #expect(languageItem.menu != nil)
        }
    }

    @Test func registeredNavigationPreviewReceivesLanguageMenuSelections() async throws {
        Localization.setLocale(identifier: "en")

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
            Localization.setLocale(identifier: "en")
        }

        #expect(profileViewController.title == "Profile")
        Localization.register(window: window)

        Localization.setLocale(identifier: "ar")
        let appliedArabic = await waitForCondition {
            profileViewController.title
                == Localization.text("demo.profile.title")
                && window.effectiveUserInterfaceLayoutDirection == .rightToLeft
                && profileViewController.view.effectiveUserInterfaceLayoutDirection
                    == .rightToLeft
        }
        #expect(appliedArabic)

        Localization.setLocale(identifier: "zh-Hans")
        let appliedChinese = await waitForCondition {
            profileViewController.title
                == Localization.text("demo.profile.title")
                && window.effectiveUserInterfaceLayoutDirection == .leftToRight
                && profileViewController.view.effectiveUserInterfaceLayoutDirection
                    == .leftToRight
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
        [rootViewController.view, inheritedContainer, inheritedLabel].forEach {
            $0.semanticContentAttribute = .forceRightToLeft
        }
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
        [rootViewController.view, inheritedContainer, inheritedLabel].forEach {
            $0.semanticContentAttribute = .forceLeftToRight
        }
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
