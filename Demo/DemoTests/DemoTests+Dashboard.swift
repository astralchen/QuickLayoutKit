import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func dashboardPresentsRealContentAndScrollsOnCompactScreens() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 320, height: 568)
        )
        defer {
            window.isHidden = true
        }

        navigationController.view.setNeedsLayout()
        navigationController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let contentCards = [
            viewController.profileCardView,
            viewController.weeklyGoalCardView,
            viewController.activityCardView,
        ]

        #expect(viewController.dashboardMetricViews.count == 3)
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.superview != nil
                    && $0.bounds.width > 0
                    && $0.bounds.height >= 126
            }
        )
        let metricFrames = viewController.dashboardMetricViews
            .map { $0.convert($0.bounds, to: viewController.scrollView) }
            .sorted { $0.minX < $1.minX }
        let visibleMetricFrames = viewController.dashboardMetricBackgroundViews
            .map { $0.convert($0.bounds, to: viewController.scrollView) }
            .sorted { $0.minX < $1.minX }
        let profileFrame = viewController.profileCardView.convert(
            viewController.profileCardView.bounds,
            to: viewController.scrollView
        )
        let weeklyGoalFrame = viewController.weeklyGoalCardView.convert(
            viewController.weeklyGoalCardView.bounds,
            to: viewController.scrollView
        )
        #expect(abs(metricFrames[0].width - metricFrames[1].width) < 1)
        #expect(abs(metricFrames[1].width - metricFrames[2].width) < 1)
        #expect(abs(metricFrames[1].minX - metricFrames[0].maxX - 10) < 1)
        #expect(abs(metricFrames[2].minX - metricFrames[1].maxX - 10) < 1)
        #expect(abs(metricFrames[0].minX - profileFrame.minX) < 1)
        #expect(abs(metricFrames[2].maxX - profileFrame.maxX) < 1)
        #expect(abs(weeklyGoalFrame.minX - profileFrame.minX) < 1)
        #expect(abs(weeklyGoalFrame.maxX - profileFrame.maxX) < 1)
        #expect(
            zip(metricFrames, visibleMetricFrames).allSatisfy { pair in
                abs(pair.0.width - pair.1.width) < 1
                    && abs(pair.0.minX - pair.1.minX) < 1
                    && abs(pair.0.maxX - pair.1.maxX) < 1
            }
        )
        #expect(
            contentCards.allSatisfy {
                $0.superview != nil
                    && $0.bounds.width > 0
                    && $0.bounds.height > 0
            }
        )
        #expect(
            viewController.scrollView.contentSize.height
                > viewController.scrollView.bounds.height
        )
        #expect(viewController.weeklyProgressView.progress == 0.72)
        #expect(
            viewController.weeklyProgressLabel.text
                == Localization.percent(0.72)
        )
        #expect(
            viewController.recentActivityLabel.text
                == Localization.text("dashboard.activity.title")
        )
    }

    @Test func dashboardMirrorsOwnedContentAndRecoversLTR() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
        }

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let rtlMetricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }
        #expect(
            viewController.scrollView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )
        #expect(
            viewController.weeklyGoalCardView
                .effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(
            viewController.weeklyProgressView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(viewController.weeklyProgressView.transform.a == -1)
        #expect(viewController.weeklyProgressView.transform.d == 1)
        #expect(rtlMetricFrames[0].minX > rtlMetricFrames[2].minX)

        window.semanticContentAttribute = .forceLeftToRight
        viewController.reloadLayoutDirection(.leftToRight)
        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let ltrMetricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }
        #expect(
            viewController.scrollView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .leftToRight
            }
        )
        #expect(
            viewController.weeklyGoalCardView
                .effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(
            viewController.weeklyProgressView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(viewController.weeklyProgressView.transform == .identity)
        #expect(ltrMetricFrames[0].minX < ltrMetricFrames[2].minX)
    }

    @Test func dashboardStacksMetricsForAccessibilityTextSizes() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 320, height: 568)
        )
        defer {
            window.isHidden = true
        }

        if #available(iOS 17.0, *) {
            viewController.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        } else {
            navigationController.setOverrideTraitCollection(
                UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
                forChild: viewController
            )
        }
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let metricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }

        #expect(metricFrames[0].minY < metricFrames[1].minY)
        #expect(metricFrames[1].minY < metricFrames[2].minY)
        #expect(
            metricFrames.allSatisfy {
                abs($0.width - metricFrames[0].width) < 1
                    && abs($0.minX - metricFrames[0].minX) < 1
            }
        )
        #expect(
            viewController.scrollView.contentSize.height
                > viewController.scrollView.bounds.height
        )
    }
}
