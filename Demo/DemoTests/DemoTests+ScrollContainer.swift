import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func scrollViewInitializerConfiguresContentAndIndicators() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.vertical, showsIndicators: false) {
            first.frame(height: 120)
            second.frame(height: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.layoutIfNeeded()
        scrollView.scrollTo(.bottom, animated: false)

        #expect(scrollView.axis == .vertical)
        #expect(first.superview === scrollView)
        #expect(second.superview === scrollView)
        #expect(!scrollView.showsVerticalScrollIndicator)
        #expect(!scrollView.showsHorizontalScrollIndicator)
        #expect(scrollView.contentSize.height >= 240)
        #expect(scrollView.contentOffset.y > 0)
    }

    @Test func verticalScrollViewCentersContentOnItsCrossAxis() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(.vertical) {
            item.frame(width: 40, height: 40)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.semanticContentAttribute = .forceRightToLeft

        scrollView.layoutIfNeeded()

        #expect(item.frame.midX == scrollView.bounds.midX)
        #expect(scrollView.contentSize.width == scrollView.bounds.width)
    }

    @Test func horizontalScrollViewAppliesViewportHeightOnItsCrossAxis() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            item.frame(width: 40, height: 40)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(item.frame.midY == scrollView.bounds.midY)
        #expect(scrollView.contentSize.height == scrollView.bounds.height)
    }

    @Test func directVerticalScrollViewStacksAndCentersMultipleRootElements() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.vertical) {
            first.frame(width: 30, height: 140)
            second.frame(width: 50, height: 90)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 7,
            left: 0,
            bottom: 13,
            right: 0
        )
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(first.frame.maxY == second.frame.minY)
        #expect(first.frame.midX == scrollView.bounds.midX)
        #expect(second.frame.midX == scrollView.bounds.midX)
        #expect(scrollView.contentSize == CGSize(width: 100, height: 230))

        scrollView.scrollTo(.top, animated: false)
        #expect(scrollView.contentOffset.y == -7)

        scrollView.scrollTo(.bottom, animated: false)
        #expect(scrollView.contentOffset.y == 143)
    }

    @Test func directHorizontalScrollViewStacksAndCentersMultipleRootElements() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 140, height: 30)
            second.frame(width: 90, height: 50)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 11,
            bottom: 0,
            right: 17
        )
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(first.frame.maxX == second.frame.minX)
        #expect(first.frame.midY == scrollView.bounds.midY)
        #expect(second.frame.midY == scrollView.bounds.midY)
        #expect(scrollView.contentSize == CGSize(width: 230, height: 100))

        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == -11)

        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == 147)
    }

    @Test func scrollViewLayoutFunctionUpdatesExistingUIKitInstance() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        _ = ScrollView(scrollView, .horizontal, showsIndicators: false) {
            item.frame(width: 240)
        }
        scrollView.layoutIfNeeded()

        #expect(scrollView.axis == .horizontal)
        #expect(item.superview === scrollView)
        #expect(!scrollView.showsHorizontalScrollIndicator)
        #expect(scrollView.contentSize.width >= 240)
    }

    @Test func horizontalScrollEdgesFollowSemanticDirection() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.layoutIfNeeded()

        let leadingLTR = -scrollView.adjustedContentInset.left
        let trailingLTR = max(
            leadingLTR,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )

        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == leadingLTR)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == trailingLTR)

        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == trailingLTR)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == leadingLTR)
    }

    @Test func horizontalScrollViewAppliesRTLDirectionToContentLayout() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.semanticContentAttribute = .forceRightToLeft

        scrollView.layoutIfNeeded()

        #expect(first.frame.minX > second.frame.minX)
    }

    @Test func horizontalScrollViewDefersRTLBeginningUntilContentIsMeasured() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.axis = .horizontal
        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)

        _ = ScrollView(scrollView, .horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.layoutIfNeeded()

        let expectedOffset = max(
            -scrollView.adjustedContentInset.left,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        #expect(scrollView.contentOffset.x == expectedOffset)
    }

    @Test func pendingInitialScrollDoesNotAnimateInsideUIKitAnimationContext() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.axis = .horizontal
        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)

        _ = ScrollView(scrollView, .horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }

        UIView.animate(withDuration: 0.25) {
            scrollView.layoutIfNeeded()
        }

        let animationKeys = scrollView.layer.animationKeys() ?? []

        #expect(!animationKeys.contains("bounds"))
        #expect(!animationKeys.contains("position"))
    }

    @Test func scrollExamplesUseContentMargins() throws {
        let examples: [(
            viewController: UIViewController,
            contentInsets: UIEdgeInsets,
            indicatorInsets: UIEdgeInsets
        )] = [
            (
                LocalizationOverviewViewController(),
                UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20),
                UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            ),
            (
                ProfileViewController(),
                UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
                .zero
            ),
            (
                ViewControllerRepresentableDemoViewController(),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            ),
            (
                ScrollViewWithKeyboardViewController(),
                UIEdgeInsets(top: 20, left: 20, bottom: 10, right: 20),
                UIEdgeInsets(top: 20, left: 20, bottom: 10, right: 20)
            ),
            (
                SemanticContentDemoViewController(),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            ),
        ]

        for example in examples {
            let viewController = example.viewController
            viewController.loadViewIfNeeded()
            viewController.view.frame = CGRect(
                x: 0,
                y: 0,
                width: 390,
                height: 844
            )
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()

            let scrollView = try #require(
                viewController.view
                    .allSubviews(of: QuickLayoutScrollView.self)
                    .first
            )

            #expect(scrollView.contentInset == example.contentInsets)
            #expect(
                scrollView.verticalScrollIndicatorInsets
                    == example.indicatorInsets
            )
            #expect(
                scrollView.horizontalScrollIndicatorInsets
                    == .zero
            )
        }
    }
}
