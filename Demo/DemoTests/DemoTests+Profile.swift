import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func profileComposesMeasuredSectionViewsWithoutIntrinsicSizeAssumptions() throws {
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        scrollView.layoutIfNeeded()

        let sections: [ProfileSectionView] = [
            try #require(
                viewController.view.allSubviews(of: ProfileHeroView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileStatsView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileAboutView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActivityView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileSkillsView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActionsView.self).first
            )
        ]

        #expect(sections.count == 6)
        #expect(sections.allSatisfy { $0.bounds.width > 0 })
        #expect(sections.allSatisfy { $0.bounds.height > 0 })
        #expect(
            sections.allSatisfy {
                $0.quickLayoutSemanticDirectionBehavior
                    == .followEnclosingContainer
            }
        )

        let heroView = try #require(sections.first as? ProfileHeroView)
        #expect(heroView.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(heroView.intrinsicContentSize.height == UIView.noIntrinsicMetric)
        #expect(heroView.quickLayoutHorizontalFlexibility == nil)
        #expect(heroView.quickLayoutVerticalFlexibility == nil)
        #expect(heroView.quick_flexibility(for: .horizontal) == .partial)
        #expect(heroView.quick_flexibility(for: .vertical) == .partial)
        let measuredHeroSize = heroView.sizeThatFits(
            CGSize(
                width: heroView.bounds.width,
                height: CGFloat.infinity
            )
        )
        #expect(abs(heroView.bounds.height - measuredHeroSize.height) < 1)
        #expect(heroView.layer.shadowPath != nil)
    }

    @Test func profileKeepsLandscapeSectionsInsideTheSafeViewport() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let viewController = ProfileViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        navigationController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 47,
            bottom: 21,
            right: 59
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer {
            window.isHidden = true
        }

        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let sections = viewController.view.allSubviews(
            of: ProfileSectionView.self
        )
        let safeAreaInsets = viewController.view.safeAreaInsets
        let scrollFrame = scrollView.convert(
            scrollView.bounds,
            to: viewController.view
        )

        #expect(scrollFrame.approximatelyEquals(viewController.view.bounds))
        #expect(sections.count >= 6)
        #expect(safeAreaInsets.left >= 47)
        #expect(safeAreaInsets.right >= 59)
        #expect(scrollView.contentInset.left >= 16)
        #expect(scrollView.contentInset.right >= 16)
        #expect(
            scrollView.adjustedContentInset.left
                >= safeAreaInsets.left + 16
        )
        #expect(
            scrollView.adjustedContentInset.right
                >= safeAreaInsets.right + 16
        )
        #expect(
            sections.allSatisfy { section in
                let frame = section.convert(
                    section.bounds,
                    to: viewController.view
                )
                return frame.minX >= safeAreaInsets.left + 16 - 1
                    && frame.maxX <= viewController.view.bounds.maxX
                        - safeAreaInsets.right - 16 + 1
            }
        )
    }

    @Test func profileCardTitlesShareTheSameLogicalLeadingEdge() throws {
        Localization.setLocale(identifier: "ar")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 1200
        )
        viewController.view.layoutIfNeeded()

        Localization.setLocale(identifier: "en-US")
        viewController.applyLocalization(
            .initial(
                snapshot: Localization.localizationController.currentSnapshot
            )
        )

        let cards: [ProfileCardView] = [
            try #require(
                viewController.view.allSubviews(of: ProfileAboutView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActivityView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileSkillsView.self).first
            )
        ]
        let titleTexts = [
            Localization.text("profile.section.about"),
            Localization.text("profile.section.activity"),
            Localization.text("profile.section.skills")
        ]
        let titleLabels = try titleTexts.map { title in
            try #require(
                viewController.view.allSubviews(of: UILabel.self).first {
                    $0.text == title
                }
            )
        }
        let aboutView = try #require(cards.first as? ProfileAboutView)
        aboutView.configure(
            title: titleTexts[0],
            body: "Short localized body."
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        let ltrLeadingEdges = zip(cards, titleLabels).map { card, label in
            label.convert(label.bounds, to: card).minX
        }

        #expect(cards.allSatisfy { abs($0.bounds.width - 370) < 0.001 })
        #expect(ltrLeadingEdges.allSatisfy { abs($0 - 16) < 0.001 })

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        let rtlLeadingEdges = zip(cards, titleLabels).map { card, label in
            card.bounds.maxX - label.convert(label.bounds, to: card).maxX
        }

        #expect(rtlLeadingEdges.allSatisfy { abs($0 - 16) < 0.001 })
    }

    @Test func profileSectionOwnedButtonsRecoverTheirDirectionRoundTrip() throws {
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        let actionsView = try #require(
            viewController.view
                .allSubviews(of: ProfileActionsView.self)
                .first
        )
        actionsView.layoutIfNeeded()
        let buttons = actionsView.allSubviews(of: UIButton.self)

        #expect(actionsView.semanticContentAttribute == .forceRightToLeft)
        #expect(buttons.count == 2)
        #expect(
            buttons.allSatisfy {
                $0.semanticContentAttribute == .forceRightToLeft
                    && $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        actionsView.layoutIfNeeded()

        #expect(actionsView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            buttons.allSatisfy {
                $0.semanticContentAttribute == .forceLeftToRight
                    && $0.effectiveUserInterfaceLayoutDirection == .leftToRight
            }
        )
    }

    @Test func profileSkillFlowReusesAndMirrorsItsFirstChipRoundTrip() throws {
        let firstSkillTitle = Localization.text("profile.skill.uikit")
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        scrollView.layoutIfNeeded()
        let skillLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text == firstSkillTitle
            }
        )
        let chip = try #require(skillLabel.superview)
        let skillCloud = try #require(chip.superview)
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()
        let ltrChipFrame = chip.convert(chip.bounds, to: skillCloud)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()
        let rtlChipFrame = chip.convert(chip.bounds, to: skillCloud)

        #expect(skillLabel.superview === chip)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(chip.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(skillCloud.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlChipFrame.minX > ltrChipFrame.minX)
        #expect(
            isHorizontalMirror(
                rtlChipFrame,
                of: ltrChipFrame,
                in: skillCloud.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()

        #expect(chip.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            chip.convert(chip.bounds, to: skillCloud)
                .approximatelyEquals(ltrChipFrame)
        )
    }
}
