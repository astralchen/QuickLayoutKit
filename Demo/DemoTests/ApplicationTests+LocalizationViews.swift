import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension ApplicationTests {

    @Test func semanticGestureContentCanLayoutAfterControllerDeallocation() throws {
        weak var releasedController: SemanticGestureViewController?
        let scrollView: QuickLayoutScrollView = try autoreleasepool {
            let controller = SemanticGestureViewController()
            releasedController = controller
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 744, height: 1133)
            controller.view.layoutIfNeeded()
            let scroll = try #require(
                controller.view.allSubviews(of: QuickLayoutScrollView.self).first
            )
            scroll.layoutIfNeeded()
            scroll.removeFromSuperview()
            return scroll
        }
        #expect(releasedController == nil)

        let hint = try #require(scrollView.allSubviews(of: UILabel.self).first {
            $0.accessibilityIdentifier == "localization.demo.body"
        })
        let content = try #require(hint.superview as? QuickLayoutView)
        for width in [320.0, 720.0] {
            let size = content.sizeThatFits(CGSize(width: width, height: .infinity))
            #expect(size.width.isFinite)
            #expect(size.height.isFinite)
            #expect(size.height >= 180)
            scrollView.frame.size = CGSize(width: width, height: 544)
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            #expect(hint.frame.width > 0)
        }
    }

    /// 页面内容应跟随安全区而非整窗宽度，覆盖侧栏两侧与窄窗口。
    @Test func localizationPagesRespectDetailViewport() throws {
        let pages: [(UIViewController, String)] = [
            (UIKitLocalizationShowcaseViewController(), "uikit.showcase.subtitle"),
            (DirectionalNavigationViewController(), "navigation.body"),
            (SemanticGestureViewController(), "gesture.hint"),
            (LocalizationBoundaryViewController(), "boundary.body"),
        ]
        for (controller, key) in pages {
            let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 744, height: 1133))
            defer { window.isHidden = true }
            for (width, left, right) in [(744.0, 268.0, 0.0), (1133.0, 0.0, 320.0), (390.0, 0.0, 0.0)] {
                window.frame.size.width = width
                controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
                window.layoutIfNeeded()
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                let scroll = try #require(controller.view.allSubviews(of: QuickLayoutScrollView.self).first)
                scroll.layoutIfNeeded()
                let label = try #require(controller.view.allSubviews(of: UILabel.self).first { $0.text == Localization.text(key) })
                label.superview?.layoutIfNeeded()
                let frame = label.convert(label.bounds, to: controller.view)
                let safe = controller.view.safeAreaLayoutGuide.layoutFrame
                #expect(frame.width > 0)
                #expect(frame.minX >= safe.minX + 19)
                #expect(frame.maxX <= safe.maxX - 19)
                #expect(frame.width <= 721)
                #expect(frame.minY >= safe.minY)
            }
        }
    }

    @Test func overviewPageReflectsArabicDirection() {
        Localization.setLocale(identifier: "ar")
        let viewController = LocalizationOverviewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let labels = viewController.view.allSubviews(of: UILabel.self).compactMap(\.text)

        #expect(labels.contains { $0.contains("RTL") })
        #expect(viewController.view.semanticContentAttribute == .forceRightToLeft)

        Localization.setLocale(identifier: "en-US")
    }

    @Test func uikitShowcaseAppliesCollectionDirection() throws {
        Localization.setLocale(identifier: "ar")
        let viewController = UIKitLocalizationShowcaseViewController()
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.rightToLeft)
        // 声明式宿主在首次布局时挂载 body，而非在 viewDidLoad 中立即 addSubview。
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(viewController.view.allSubviews(of: UICollectionView.self).first)

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)

        Localization.setLocale(identifier: "en-US")
    }

    @Test func localizationOverviewMirrorsItsReusedLeadingContent() throws {
        var usesRightToLeftLayout = false
        let localizer = Localizer { key, _ in key }
        let languageIdentifier = "test.system"
        let service = LocalizationOverviewService(
            snapshot: {
                LocalizationOverviewService.Snapshot(
                    currentLanguageSummary: "System",
                    usesRightToLeftLayout: usesRightToLeftLayout,
                    selectedIdentifier: languageIdentifier,
                    languages: [
                        LocalizationOverviewService.Language(
                            identifier: languageIdentifier,
                            nativeName: "",
                            localizedName: "System",
                            isFollowSystemOption: true
                        )
                    ]
                )
            },
            selectLanguage: { _ in }
        )
        let viewController = LocalizationOverviewViewController(
            viewModel: LocalizationOverviewViewModel(
                localizer: localizer,
                service: service
            )
        )
        let testWindow = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let bodyLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text == "localization.overview.body"
            }
        )
        let languageButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == languageIdentifier
            }
        )
        let ltrBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let ltrButtonTitleFrame = try #require(languageButton.titleLabel).convert(
            languageButton.titleLabel!.bounds,
            to: languageButton
        )
        let ltrButtonImageFrame = try #require(languageButton.imageView).convert(
            languageButton.imageView!.bounds,
            to: languageButton
        )
        let ltrConfiguration = try #require(languageButton.configuration)
        let expectedTitle = try #require(ltrConfiguration.title)

        #expect(ltrConfiguration.image != nil)
        #expect(languageButton.titleLabel?.text == expectedTitle)
        #expect(languageButton.imageView?.image != nil)
        #expect(ltrButtonTitleFrame.midX < ltrButtonImageFrame.midX)
        #expect(bodyLabel.effectiveUserInterfaceLayoutDirection == .leftToRight)

        usesRightToLeftLayout = true
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        languageButton.layoutIfNeeded()

        let updatedButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == languageIdentifier
            }
        )
        let rtlBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let rtlButtonTitleFrame = try #require(updatedButton.titleLabel).convert(
            updatedButton.titleLabel!.bounds,
            to: updatedButton
        )
        let rtlButtonImageFrame = try #require(updatedButton.imageView).convert(
            updatedButton.imageView!.bounds,
            to: updatedButton
        )
        let rtlConfiguration = try #require(updatedButton.configuration)

        #expect(updatedButton === languageButton)
        #expect(rtlConfiguration.title == expectedTitle)
        #expect(rtlConfiguration.image != nil)
        #expect(updatedButton.titleLabel?.text == expectedTitle)
        #expect(updatedButton.imageView?.image != nil)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(bodyLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(updatedButton.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlButtonTitleFrame.midX > rtlButtonImageFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlBodyFrame,
                of: ltrBodyFrame,
                in: scrollView.contentSize.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlButtonTitleFrame,
                of: ltrButtonTitleFrame,
                in: updatedButton.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlButtonImageFrame,
                of: ltrButtonImageFrame,
                in: updatedButton.bounds.width
            )
        )
        #expect(
            viewController.view.allSubviews(of: UILabel.self).contains {
                $0.text == "language.direction: RTL"
            }
        )

        usesRightToLeftLayout = false
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        languageButton.layoutIfNeeded()

        let returnedBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let returnedButtonTitleFrame = try #require(languageButton.titleLabel)
            .convert(languageButton.titleLabel!.bounds, to: languageButton)
        let returnedButtonImageFrame = try #require(languageButton.imageView)
            .convert(languageButton.imageView!.bounds, to: languageButton)

        #expect(languageButton.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(returnedBodyFrame.approximatelyEquals(ltrBodyFrame))
        #expect(returnedButtonTitleFrame.approximatelyEquals(ltrButtonTitleFrame))
        #expect(returnedButtonImageFrame.approximatelyEquals(ltrButtonImageFrame))
    }

    @Test func formFieldMirrorsTheSameIconAndTextFieldAcrossDirectionChanges() {
        let viewController = ScrollViewWithKeyboardViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let fieldView = viewController.nameFieldView
        let iconView = fieldView.iconView
        let textField = fieldView.textField
        fieldView.layoutIfNeeded()
        let ltrIconFrame = iconView.convert(iconView.bounds, to: fieldView)
        let ltrTextFieldFrame = textField.convert(textField.bounds, to: fieldView)

        #expect(ltrIconFrame.midX < ltrTextFieldFrame.midX)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        fieldView.layoutIfNeeded()

        let rtlIconFrame = iconView.convert(iconView.bounds, to: fieldView)
        let rtlTextFieldFrame = textField.convert(textField.bounds, to: fieldView)

        #expect(fieldView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(fieldView.semanticContentAttribute == .forceRightToLeft)
        #expect(iconView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(textField.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlIconFrame.midX > rtlTextFieldFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlIconFrame,
                of: ltrIconFrame,
                in: fieldView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTextFieldFrame,
                of: ltrTextFieldFrame,
                in: fieldView.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        fieldView.layoutIfNeeded()

        #expect(fieldView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            iconView.convert(iconView.bounds, to: fieldView)
                .approximatelyEquals(ltrIconFrame)
        )
        #expect(
            textField.convert(textField.bounds, to: fieldView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
    }

    @Test func semanticSectionsMirrorOnlyTheUnspecifiedQuickLayoutRows() throws {
        let viewController = SemanticContentViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 390, height: 1600)
        )
        defer { testWindow.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let unspecifiedRow = viewController.unspecifiedSection.example2
        let forcedLTRRow = viewController.ltrSection.example2
        let forcedRTLRow = viewController.rtlSection.example2
        [unspecifiedRow, forcedLTRRow, forcedRTLRow].forEach {
            $0.layoutIfNeeded()
        }

        let unspecifiedLeading = unspecifiedRow.leadingBackgroundView
        let forcedLTRLeading = forcedLTRRow.leadingBackgroundView
        let forcedRTLLeading = forcedRTLRow.leadingBackgroundView
        let ltrUnspecifiedFrame = unspecifiedLeading.convert(
            unspecifiedLeading.bounds,
            to: unspecifiedRow
        )
        let ltrForcedLTRFrame = forcedLTRLeading.convert(
            forcedLTRLeading.bounds,
            to: forcedLTRRow
        )
        let ltrForcedRTLFrame = forcedRTLLeading.convert(
            forcedRTLLeading.bounds,
            to: forcedRTLRow
        )

        #expect(
            ltrUnspecifiedFrame.midX
                < unspecifiedRow.trailingBackgroundView.frame.midX
        )
        #expect(
            ltrForcedLTRFrame.midX
                < forcedLTRRow.trailingBackgroundView.frame.midX
        )
        #expect(
            ltrForcedRTLFrame.midX
                > forcedRTLRow.trailingBackgroundView.frame.midX
        )

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        [unspecifiedRow, forcedLTRRow, forcedRTLRow].forEach {
            $0.layoutIfNeeded()
        }

        let rtlUnspecifiedFrame = unspecifiedLeading.convert(
            unspecifiedLeading.bounds,
            to: unspecifiedRow
        )
        let rtlForcedLTRFrame = forcedLTRLeading.convert(
            forcedLTRLeading.bounds,
            to: forcedLTRRow
        )
        let rtlForcedRTLFrame = forcedRTLLeading.convert(
            forcedRTLLeading.bounds,
            to: forcedRTLRow
        )

        #expect(unspecifiedRow.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(unspecifiedRow.semanticContentAttribute == .forceRightToLeft)
        #expect(forcedLTRRow.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(forcedRTLRow.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(
            rtlUnspecifiedFrame.midX
                > unspecifiedRow.trailingBackgroundView.frame.midX
        )
        #expect(
            rtlForcedLTRFrame.midX
                < forcedLTRRow.trailingBackgroundView.frame.midX
        )
        #expect(
            rtlForcedRTLFrame.midX
                > forcedRTLRow.trailingBackgroundView.frame.midX
        )
        #expect(
            isHorizontalMirror(
                rtlUnspecifiedFrame,
                of: ltrUnspecifiedFrame,
                in: unspecifiedRow.bounds.width
            )
        )
        #expect(rtlForcedLTRFrame.approximatelyEquals(ltrForcedLTRFrame))
        #expect(rtlForcedRTLFrame.approximatelyEquals(ltrForcedRTLFrame))

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        unspecifiedRow.layoutIfNeeded()

        #expect(unspecifiedRow.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            unspecifiedLeading.convert(unspecifiedLeading.bounds, to: unspecifiedRow)
                .approximatelyEquals(ltrUnspecifiedFrame)
        )
    }

    @Test func semanticGestureUsesDirectionalLayout() {
        Localization.setLocale(identifier: "ar")

        let physicalRight = DirectionalLayout.semanticHorizontalDirection(
            translationX: 20,
            layoutDirection: Localization.currentLayoutDirection
        )
        let isBackSwipe = DirectionalLayout.isBackSwipe(
            translationX: -20,
            layoutDirection: Localization.currentLayoutDirection
        )

        #expect(physicalRight == .leading)
        #expect(isBackSwipe)

        Localization.setLocale(identifier: "en-US")
    }
}
