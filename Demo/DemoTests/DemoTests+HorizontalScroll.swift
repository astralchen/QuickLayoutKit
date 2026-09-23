import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test(arguments: [240.0, 358.0, 623.0, 624.0, 812.0, 919.0, 920.0, 1215.0, 1216.0, 1512.0])
    func horizontalCarouselFitsMaximumCardsAtMinimumWidth(viewportWidth: Double) {
        let width = CGFloat(viewportWidth)
        let count = HorizontalCarouselLayoutMetrics.visibleCardCount(for: width)
        let cardWidth = HorizontalCarouselLayoutMetrics.cardWidth(for: width)
        let minimum = HorizontalCarouselLayoutMetrics.preferredMinimumCardWidth
        let spacing = HorizontalCarouselLayoutMetrics.spacing
        let preview = HorizontalCarouselLayoutMetrics.nextCardPreviewWidth

        // 覆盖列数切换前后：当前列数满足最小宽度，再多一列则放不下。
        #expect(cardWidth >= min(minimum, max(0, width - spacing - preview)))
        #expect(cardWidth <= HorizontalCarouselLayoutMetrics.maximumCardWidth)
        #expect(CGFloat(count + 1) * (minimum + spacing) + preview > width)
        let remaining = width - CGFloat(count) * (cardWidth + spacing)
        #expect(remaining >= preview - 0.01)
        if cardWidth < HorizontalCarouselLayoutMetrics.maximumCardWidth {
            #expect(abs(remaining - preview) < 0.01)
        }
    }

    @Test func horizontalScrollDemoStartsFromRightInRTL() {
        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let firstCardFrame = viewController.views[0].convert(
            viewController.views[0].bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )
        #expect(firstCardFrame.maxX <= visibleRect.maxX)
        #expect(firstCardFrame.maxX > visibleRect.maxX - 80)
    }

    @Test func horizontalScrollDemoPreparesRTLStartBeforeAppearAnimation() {
        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLayoutDirection(.rightToLeft)

        viewController.beginAppearanceTransition(true, animated: true)
        viewController.endAppearanceTransition()

        #expect(viewController.scrollView.contentOffset.x > 0)
    }

    @Test func horizontalScrollDemoUsesViewportRelativeCards() {
        Localization.setLocale(identifier: "en-US")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.pageScrollView.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let firstCard = viewController.views[0]
        let contentViewportWidth = viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.left
            - viewController.scrollView.adjustedContentInset.right
        let expectedWidth = HorizontalCarouselLayoutMetrics.cardWidth(
            for: contentViewportWidth
        )
        let expectedCornerRadius = min(24, max(12, expectedWidth * 0.08))
        let portraitHeight = firstCard.bounds.height
        let portraitCardHeights = viewController.views.map(\.bounds.height)
        let portraitNaturalHeight = viewController.views.map {
            $0.sizeThatFits(
                CGSize(width: $0.bounds.width, height: .infinity)
            ).height
        }.max() ?? 0
        let secondCard = viewController.views[1]
        let secondCardFrame = secondCard.convert(
            secondCard.bounds,
            to: viewController.scrollView
        )
        let visibleTrailingEdge = viewController.scrollView.contentOffset.x
            + viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.right
        let visibleSecondCardWidth = visibleTrailingEdge
            - secondCardFrame.minX

        #expect(viewController.scrollView.contentInset.left == 16)
        #expect(viewController.scrollView.contentInset.right == 16)
        #expect(viewController.scrollView.contentOffset.x == -16)
        #expect(
            HorizontalCarouselLayoutMetrics.visibleCardCount(
                for: contentViewportWidth
            ) == 1
        )
        #expect(abs(firstCard.bounds.width - expectedWidth) < 1)
        #expect(firstCard.bounds.width < contentViewportWidth)
        #expect(
            abs(
                visibleSecondCardWidth
                    - HorizontalCarouselLayoutMetrics.nextCardPreviewWidth
            ) < 1
        )
        #expect(portraitHeight > 0)
        #expect(
            (portraitCardHeights.max() ?? 0)
                - (portraitCardHeights.min() ?? 0) < 1
        )
        #expect((portraitCardHeights.min() ?? 0) >= portraitNaturalHeight - 1)
        #expect(
            viewController.views.allSatisfy { cardView in
                (cardView.subviews.map(\.frame.minY).min() ?? 0) < 1
            }
        )
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(abs(firstCard.layer.cornerRadius - expectedCornerRadius) < 1)

        viewController.view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.pageScrollView.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let landscapeViewportWidth = viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.left
            - viewController.scrollView.adjustedContentInset.right
        let expectedLandscapeWidth = HorizontalCarouselLayoutMetrics.cardWidth(
            for: landscapeViewportWidth
        )
        let landscapeCardHeights = viewController.views.map(\.bounds.height)
        let landscapeNaturalHeight = viewController.views.map {
            $0.sizeThatFits(
                CGSize(width: $0.bounds.width, height: .infinity)
            ).height
        }.max() ?? 0

        #expect(
            HorizontalCarouselLayoutMetrics.visibleCardCount(
                for: landscapeViewportWidth
            ) == 2
        )
        #expect(abs(firstCard.bounds.width - expectedLandscapeWidth) < 1)
        #expect(firstCard.bounds.height > 0)
        #expect(
            (landscapeCardHeights.max() ?? 0)
                - (landscapeCardHeights.min() ?? 0) < 1
        )
        #expect(
            (landscapeCardHeights.min() ?? 0) >= landscapeNaturalHeight - 1
        )
        #expect(
            viewController.views.allSatisfy { cardView in
                (cardView.subviews.map(\.frame.minY).min() ?? 0) < 1
            }
        )
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(firstCard.layer.cornerRadius == 24)
        #expect(
            viewController.pageScrollView.contentSize.height
                > viewController.pageScrollView.bounds.height
        )
    }

    @Test func horizontalDestinationCardHeightFollowsItsContent() {
        let cardView = HorizontalDestinationCardView(palette: .lakeside)
        #expect(cardView.quickLayoutHorizontalFlexibility == .fullyFlexible)
        #expect(cardView.quickLayoutVerticalFlexibility == .fixedSize)
        let baseContent = HorizontalDestinationCardContent(
            tag: "2 day trip",
            title: "Lakeside weekend",
            location: "Hangzhou",
            summary: "A short destination summary.",
            rating: "4.9",
            price: "$120",
            priceCaption: "From",
            accessibilityHint: "Open destination"
        )
        cardView.configure(baseContent)

        let shortHeight = cardView.sizeThatFits(
            CGSize(width: 280, height: CGFloat.infinity)
        ).height

        cardView.configure(
            HorizontalDestinationCardContent(
                tag: baseContent.tag,
                title: "A lakeside weekend with a deliberately longer title",
                location: baseContent.location,
                summary: Array(
                    repeating: "Localized details should determine height.",
                    count: 5
                ).joined(separator: " "),
                rating: baseContent.rating,
                price: baseContent.price,
                priceCaption: baseContent.priceCaption,
                accessibilityHint: baseContent.accessibilityHint
            )
        )

        let longHeight = cardView.sizeThatFits(
            CGSize(width: 280, height: CGFloat.infinity)
        ).height

        #expect(shortHeight > 0)
        #expect(longHeight > shortHeight)
    }

    @Test func horizontalScrollDemoHasContentOnFirstNavigationLayout() throws {
        Localization.setLocale(identifier: "en-US")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let rootViewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: rootViewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
        }

        let viewController = HorizontalScrollViewViewController()
        navigationController.pushViewController(
            viewController,
            animated: false
        )
        window.layoutIfNeeded()

        #expect(viewController.pageScrollView.bounds.width > 0)
        #expect(viewController.scrollView.bounds.height > 0)
        #expect(viewController.views.first?.bounds.height ?? 0 > 0)
    }

    @Test func horizontalScrollDemoKeepsLandscapeContentInsideSafeArea() throws {
        Localization.setLocale(identifier: "en-US")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 47,
            bottom: 21,
            right: 59
        )
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 844, height: 390)
        )
        defer {
            window.isHidden = true
        }

        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let safeAreaInsets = viewController.view.safeAreaInsets
        let pageFrame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        let carouselFrame = viewController.scrollView.convert(
            viewController.scrollView.bounds,
            to: viewController.view
        )

        #expect(pageFrame.approximatelyEquals(viewController.view.bounds))
        #expect(abs(carouselFrame.minX - pageFrame.minX) < 1)
        #expect(abs(carouselFrame.maxX - pageFrame.maxX) < 1)
        #expect(
            viewController.scrollView.adjustedContentInset.left
                >= safeAreaInsets.left + 16
        )
        #expect(
            viewController.scrollView.adjustedContentInset.right
                >= safeAreaInsets.right + 16
        )

        let ltrFirstCard = try #require(viewController.views.first)
        let ltrFirstCardFrame = ltrFirstCard.convert(
            ltrFirstCard.bounds,
            to: viewController.view
        )
        #expect(ltrFirstCardFrame.minX >= safeAreaInsets.left + 16 - 1)

        let labels = viewController.view.allSubviews(of: UILabel.self)
        let headlineLabel = try #require(
            labels.first {
                $0.text == Localization.text("horizontal.explore.headline")
            }
        )
        let footerLabel = try #require(
            labels.first {
                $0.text == Localization.text("horizontal.explore.hint")
            }
        )
        let headlineFrame = headlineLabel.convert(
            headlineLabel.bounds,
            to: viewController.view
        )
        #expect(headlineFrame.minX >= safeAreaInsets.left + 20 - 1)
        #expect(
            headlineFrame.maxX
                <= viewController.view.bounds.maxX
                    - safeAreaInsets.right
                    - 20
                    + 1
        )

        viewController.pageScrollView.scrollTo(.bottom, animated: false)
        viewController.pageScrollView.layoutIfNeeded()
        let footerFrame = footerLabel.convert(
            footerLabel.bounds,
            to: viewController.view
        )
        #expect(footerFrame.minX >= safeAreaInsets.left + 20 - 1)
        #expect(
            footerFrame.maxY
                <= viewController.view.bounds.maxY
                    - safeAreaInsets.bottom
                    + 1
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let firstCard = try #require(viewController.views.first)
        let firstCardFrame = firstCard.convert(
            firstCard.bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )
        let expectedTrailingEdge = visibleRect.maxX
            - viewController.scrollView.adjustedContentInset.right
        let artworkView = try #require(
            firstCard.allSubviews(of: QuickLayoutLinearGradientView.self).first
        )
        let artworkFrame = artworkView.convert(artworkView.bounds, to: firstCard)

        #expect(firstCard.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(firstCardFrame.maxX <= expectedTrailingEdge + 1)
        #expect(firstCardFrame.maxX >= expectedTrailingEdge - 1)
        #expect(abs(artworkFrame.minX - firstCard.bounds.minX) < 1)
        #expect(abs(artworkFrame.width - firstCard.bounds.width) < 1)
        #expect(abs(artworkFrame.minY - firstCard.bounds.minY) < 1)

        let rtlPageFrame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        #expect(rtlPageFrame.approximatelyEquals(pageFrame))
    }

    @Test func horizontalScrollDemoModelsLocalizedDestinationDiscovery() throws {
        Localization.setLocale(identifier: "en-US")
        defer {
            Localization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 402, height: 874)
        )
        defer {
            window.isHidden = true
        }

        let firstCard = try #require(viewController.views.first)
        let englishLabels = viewController.view.allSubviews(of: UILabel.self)
        let measuredCardHeight = firstCard.sizeThatFits(
            CGSize(
                width: firstCard.bounds.width,
                height: CGFloat.infinity
            )
        ).height

        #expect(viewController.views.count == 5)
        #expect(firstCard.bounds.height > 146)
        #expect(abs(firstCard.bounds.height - measuredCardHeight) < 1)
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(
            firstCard.accessibilityIdentifier
                == "horizontal.destination.lakeside"
        )
        #expect(firstCard.accessibilityTraits.contains(.button))
        #expect(
            firstCard.destinationTitle
                == Localization.text(
                    "horizontal.explore.destination.lakeside.title"
                )
        )
        #expect(
            englishLabels.contains {
                $0.text == Localization.text("horizontal.explore.headline")
            }
        )
        #expect(
            englishLabels.contains {
                $0.text == Localization.text(
                    "horizontal.explore.page",
                    1,
                    viewController.views.count
                )
            }
        )

        let secondCard = viewController.views[1]
        let secondCardFrame = secondCard.convert(
            secondCard.bounds,
            to: viewController.scrollView
        )
        viewController.scrollView.setContentOffset(
            CGPoint(
                x: secondCardFrame.midX
                    - viewController.scrollView.bounds.width / 2,
                y: viewController.scrollView.contentOffset.y
            ),
            animated: false
        )
        viewController.scrollViewDidScroll(viewController.scrollView)

        #expect(
            englishLabels.contains {
                $0.text == Localization.text(
                    "horizontal.explore.page",
                    2,
                    viewController.views.count
                )
            }
        )

        Localization.setLocale(identifier: "ar")
        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.scrollView.setNeedsLayout()
        viewController.views.forEach { $0.setNeedsLayout() }
        window.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        viewController.views.forEach { $0.layoutIfNeeded() }

        let firstCardFrame = viewController.views[0].convert(
            viewController.views[0].bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )

        #expect(
            viewController.views[0].destinationTitle
                == Localization.text(
                    "horizontal.explore.destination.lakeside.title"
                )
        )
        #expect(
            viewController.views[0].effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(firstCardFrame.maxX <= visibleRect.maxX)
        #expect(firstCardFrame.maxX > visibleRect.maxX - 80)
    }
}
