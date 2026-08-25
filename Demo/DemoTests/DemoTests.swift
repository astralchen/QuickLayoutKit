//
//  DemoTests.swift
//  DemoTests
//
//  Created by Sondra on 2025/12/26.
//

import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct DemoTests {

    @Test func safeAreaPaddingDemoCoversQuickLayoutCombinations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = SafeAreaPaddingDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        func expectPageInsets(
            _ expected: UIEdgeInsets,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            let frame = viewController.pageScrollView.convert(
                viewController.pageScrollView.bounds,
                to: viewController.view
            )
            let bounds = viewController.view.bounds
            #expect(
                abs(frame.minX - expected.left) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(frame.minY - expected.top) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(bounds.maxX - frame.maxX - expected.right) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(bounds.maxY - frame.maxY - expected.bottom) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(
                    viewController.pageScrollView.contentOffset.y
                        + viewController.pageScrollView
                            .adjustedContentInset.top
                ) < 1,
                sourceLocation: sourceLocation
            )
        }

        #expect(viewController.scenarioCount == 10)
        expectPageInsets(.zero)

        let safeArea = viewController.view.safeAreaInsets
        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.zeroAll.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(safeArea)

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.nilAll.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(safeArea)

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.allSixteen.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: safeArea.top + 16,
                left: safeArea.left + 16,
                bottom: safeArea.bottom + 16,
                right: safeArea.right + 16
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .perEdgeInsets.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: safeArea.top + 8,
                left: safeArea.left + 12,
                bottom: safeArea.bottom + 20,
                right: safeArea.right + 24
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .separateEdges.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 16,
                bottom: safeArea.bottom + 24,
                right: safeArea.right + 16
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .repeatedLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 20,
                bottom: 0,
                right: 0
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .leadingThenNil.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 8,
                bottom: 0,
                right: 0
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .negativeLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left,
                bottom: 0,
                right: 0
            )
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .repeatedLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: 0,
                right: safeArea.right + 20
            )
        )
    }

    @Test func safeAreaPaddingDemoFollowsLandscapeSafeAreaChanges() throws {
        let viewController = SafeAreaPaddingDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.allSixteen.rawValue
        )
        layout(viewController, in: navigationController)

        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 62,
            bottom: 20,
            right: 62
        )
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        navigationController.view.frame = window.bounds
        layout(viewController, in: navigationController)

        let safeArea = viewController.view.safeAreaInsets
        let frame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        #expect(viewController.view.bounds.width > viewController.view.bounds.height)
        #expect(safeArea.left >= 62)
        #expect(safeArea.right >= 62)
        #expect(abs(frame.minX - safeArea.left - 16) < 1)
        #expect(abs(viewController.view.bounds.maxX - frame.maxX - safeArea.right - 16) < 1)
        #expect(abs(frame.minY - safeArea.top - 16) < 1)
        #expect(abs(viewController.view.bounds.maxY - frame.maxY - safeArea.bottom - 16) < 1)
        #expect(viewController.pageScrollView.contentSize.height > 0)
    }

    @Test func contentMarginsDemoCoversSwiftUIPlacementCombinations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = ContentMarginsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        #expect(viewController.scenarioCount == 9)
        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .explicitContentWithAutomaticBottom.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .sameScrollContentPlacement.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 16, bottom: 24, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == .zero
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .explicitContentReplacesAutomatic.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        )
    }

    @Test func contentMarginsDemoRemainsReachableInLandscape() throws {
        let viewController = ContentMarginsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let pageScrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first { $0 !== viewController.previewScrollView }
        )
        #expect(viewController.previewScrollView.bounds.width > 600)
        #expect(
            viewController.previewScrollView.contentSize.height
                > viewController.previewScrollView.bounds.height
        )
        #expect(
            pageScrollView.contentSize.height > pageScrollView.bounds.height
        )
    }

    @Test func positionAndZIndexDemoUsesPhysicalPointsAndLayerOrdering() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = PositionAndZIndexDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.positionCanvas.layoutIfNeeded()
        viewController.zIndexCanvas.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        #expect(scrollView.contentInset.bottom == 24)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 24)
        #expect(scrollView.automaticallyAdjustsScrollIndicatorInsets)

        #expect(viewController.positionCanvas.bounds.width > 0)
        #expect(
            center(
                of: viewController.positionCanvas.firstBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 60, y: 54))
        )
        #expect(
            center(
                of: viewController.positionCanvas.centerBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 144, y: 100))
        )
        #expect(
            center(
                of: viewController.positionCanvas.lastBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 228, y: 146))
        )
        #expect(
            [
                viewController.positionCanvas.firstBadge,
                viewController.positionCanvas.centerBadge,
                viewController.positionCanvas.lastBadge,
            ].allSatisfy {
                $0.bounds.width >= $0.intrinsicContentSize.width + 27
                    && $0.bounds.height >= $0.intrinsicContentSize.height + 15
            }
        )

        #expect(viewController.zIndexCanvas.backCard.layer.zPosition == 0)
        #expect(viewController.zIndexCanvas.middleCard.layer.zPosition == 1)
        #expect(viewController.zIndexCanvas.frontCard.layer.zPosition == 3)
        #expect(
            [
                viewController.zIndexCanvas.backCard,
                viewController.zIndexCanvas.middleCard,
                viewController.zIndexCanvas.frontCard,
            ].allSatisfy {
                $0.bounds.width >= $0.intrinsicContentSize.width + 35
                    && $0.bounds.height >= $0.intrinsicContentSize.height + 23
            }
        )

        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 62,
            bottom: 20,
            right: 62
        )
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        navigationController.view.frame = window.bounds
        layout(viewController, in: navigationController)

        #expect(viewController.view.bounds.width > viewController.view.bounds.height)
        #expect(scrollView.safeAreaInsets.left >= 62)
        #expect(scrollView.safeAreaInsets.right >= 62)
        #expect(scrollView.contentInset.bottom == 24)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 24)
        #expect(scrollView.automaticallyAdjustsScrollIndicatorInsets)

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.positionCanvas.layoutIfNeeded()

        #expect(
            center(
                of: viewController.positionCanvas.centerBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 144, y: 100))
        )
    }

    private func layout(
        _ viewController: DemoQuickLayoutHostingController,
        in navigationController: UINavigationController
    ) {
        navigationController.view.setNeedsLayout()
        navigationController.view.layoutIfNeeded()
        viewController.setNeedsQuickLayout()
        viewController.quickLayoutIfNeeded()
        viewController.view.layoutIfNeeded()
    }

    @Test func quickLayoutViewMeasuresHostedContent() {
        let label = UILabel()
        label.text = "QuickLayoutKit"
        label.font = .systemFont(ofSize: 17)

        let hostingView = QuickLayoutView {
            label
                .padding(.all, 12)
        }

        let measuredSize = hostingView.sizeThatFits(in: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))

        #expect(measuredSize.width > 0)
        #expect(measuredSize.height > 17)
    }

    @Test func hostingControllerUsesReusableQuickLayoutView() {
        let label = UILabel()
        label.text = "Hosted"

        let viewController = QuickLayoutHostingController {
            label
                .padding(.all, 8)
        }

        viewController.loadViewIfNeeded()

        #expect(viewController.view is QuickLayoutView)
        #expect(viewController.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height > 0)
    }

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
                == DemoLocalization.text("dashboard.weekly.progress")
        )
        #expect(
            viewController.recentActivityLabel.text
                == DemoLocalization.text("dashboard.activity.title")
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

        viewController.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge
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
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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
                $0.text == DemoLocalization.text("horizontal.explore.headline")
            }
        )
        let footerLabel = try #require(
            labels.first {
                $0.text == DemoLocalization.text("horizontal.explore.hint")
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
            firstCard.allSubviews(of: UIView.self).first { view in
                view.layer.sublayers?.contains { $0 is CAGradientLayer } == true
            }
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
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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
                == DemoLocalization.text(
                    "horizontal.explore.destination.lakeside.title"
                )
        )
        #expect(
            englishLabels.contains {
                $0.text == DemoLocalization.text("horizontal.explore.headline")
            }
        )
        #expect(
            englishLabels.contains {
                $0.text == DemoLocalization.text(
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
                $0.text == DemoLocalization.text(
                    "horizontal.explore.page",
                    2,
                    viewController.views.count
                )
            }
        )

        DemoLocalization.setLocale(identifier: "ar")
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
                == DemoLocalization.text(
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

    @Test func counterDemoFallsBackToVerticalActionsWhenNarrow() {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }
        let viewController = CounterViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        #expect(
            abs(
                viewController.decrementButton.frame.midY
                    - viewController.incrementButton.frame.midY
            ) < 1
        )
        #expect(viewController.counterLabel.text == "3")
        #expect(
            viewController.incrementButton.accessibilityLabel == "Add glass"
        )
        #expect(
            viewController.decrementButton.accessibilityLabel == "Remove"
        )
        #expect(viewController.resetButton.isEnabled)

        viewController.incrementButton.performAction()
        #expect(viewController.counterLabel.text == "4")
        viewController.decrementButton.performAction()
        #expect(viewController.counterLabel.text == "3")

        viewController.view.frame = CGRect(x: 0, y: 0, width: 140, height: 500)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        #expect(
            viewController.decrementButton.frame.maxY
                < viewController.incrementButton.frame.minY
        )
    }

    @Test func mediaExamplesPreserveTheirAspectRatios() throws {
        let messageContentView = MessageContentView(frame: .zero)
        messageContentView.configure(MessageModel.mockData[0])
        let messageSize = messageContentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        messageContentView.frame = CGRect(origin: .zero, size: messageSize)
        messageContentView.layoutIfNeeded()

        let fitRow = ExampleRow2()
        fitRow.body.applyFrame(
            CGRect(x: 0, y: 0, width: 320, height: 72),
            alignment: .topLeading
        )
        let iconSize = try #require(fitRow.directionIconView.image?.size)
        let iconRatio = iconSize.width / iconSize.height
        let fittedRatio = fitRow.directionIconView.bounds.width
            / fitRow.directionIconView.bounds.height

        let fillRow = ExampleRow3()
        fillRow.body.applyFrame(
            CGRect(x: 0, y: 0, width: 320, height: 72),
            alignment: .topLeading
        )
        let fillImageSize = try #require(fillRow.imageView.image?.size)
        let fillImageRatio = fillImageSize.width / fillImageSize.height
        let filledRatio = fillRow.imageView.bounds.width
            / fillRow.imageView.bounds.height

        #expect(messageContentView.avatarView.bounds.size == CGSize(width: 40, height: 40))
        #expect(fitRow.directionIconView.bounds.width <= 24)
        #expect(fitRow.directionIconView.bounds.height <= 24)
        #expect(abs(fittedRatio - iconRatio) < 0.01)
        #expect(fillRow.imageView.bounds.width >= 40)
        #expect(fillRow.imageView.bounds.height >= 40)
        #expect(abs(filledRatio - fillImageRatio) < 0.01)
    }

    @Test func messageContentViewUpdatesAndSelfSizes() {
        let firstModel = MessageModel(
            title: "First",
            message: "Short message",
            imageName: "sun.max.fill",
            themeColor: .systemOrange
        )
        let contentView = MessageContentView(frame: .zero)
        contentView.configure(firstModel)

        #expect(contentView.titleLabel.text == firstModel.title)
        #expect(contentView.messageLabel.text == firstModel.message)

        let secondModel = MessageModel(
            title: "Updated",
            message: String(
                repeating: "A longer message that should wrap. ",
                count: 8
            ),
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        contentView.configure(secondModel)

        let wideSize = contentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        let narrowSize = contentView.sizeThatFits(
            CGSize(
                width: 180,
                height: CGFloat.greatestFiniteMagnitude
            )
        )

        #expect(contentView.titleLabel.text == secondModel.title)
        #expect(contentView.messageLabel.text == secondModel.message)
        #expect(narrowSize.height > wideSize.height)

        let cell = MessageCell(frame: .zero)
        cell.configure(firstModel)
        let initialCellContentView = cell.messageContentView
        #expect(initialCellContentView.titleLabel.text == firstModel.title)
        cell.isHighlighted = true
        #expect(initialCellContentView.alpha < 1)

        cell.prepareForReuse()
        #expect(initialCellContentView.titleLabel.text == nil)
        #expect(initialCellContentView.messageLabel.text == nil)
        #expect(initialCellContentView.alpha == 1)

        cell.configure(secondModel)
        let reusedCellContentView = cell.messageContentView
        #expect(reusedCellContentView === initialCellContentView)
        #expect(reusedCellContentView.titleLabel.text == secondModel.title)
        #expect(reusedCellContentView.messageLabel.text == secondModel.message)

        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: 0, section: 0)
        )
        attributes.size = CGSize(width: 180, height: 80)
        let fittedAttributes = cell.preferredLayoutAttributesFitting(
            attributes
        )

        #expect(fittedAttributes.size == narrowSize)
    }

    @Test func tableMessageControllerUsesSelfSizingViews() throws {
        let fittingTolerance: CGFloat = 1.01
        let viewController = MessageTableViewController()
        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.tableView)
        tableView.estimatedRowHeight = 1
        tableView.estimatedSectionHeaderHeight = 1
        tableView.estimatedSectionFooterHeight = 1
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        tableView.reloadData()
        tableView.layoutIfNeeded()

        #expect(tableView.numberOfRows(inSection: 0) == 12)
        #expect(
            tableView.rectForRow(
                at: IndexPath(row: 0, section: 0)
            ).height > 60
        )
        #expect(tableView.rectForHeader(inSection: 0).height > 44)

        let cell = try #require(
            tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                as? MessageTableCell
        )
        let cellContentView = cell.messageContentView
        #expect(cellContentView.titleLabel.text?.isEmpty == false)
        let cellFittingSize = cell.systemLayoutSizeFitting(
            CGSize(width: cell.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(cell.bounds.height - cellFittingSize.height)
                <= fittingTolerance
        )

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        #expect(header.sectionContentView.titleLabel.text?.isEmpty == false)
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= fittingTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        let footer = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(footer.sectionContentView.titleLabel.text?.isEmpty == false)
        #expect(footer.bounds.height > 20)
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= fittingTolerance
        )
    }

    @Test func tableMessageSupplementariesStartRTLOnFirstAppearance() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = MessageTableListView()

        let model = MessageModel(
            title: "رسالة",
            message: "محتوى الرسالة",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            MessageListItem(
                id: MessageListItemID(group: 0, message: model.imageName),
                model: model
            )
        ]
        let headerText = "رسائل ذاتية التحجيم عند الظهور الأول"
        let detailText = "يجب أن يبدأ هذا الرأس من الحافة اليمنى مباشرة."
        let footerText = "يظهر هذا التذييل باتجاه صحيح وارتفاع مناسب من المرة الأولى."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: headerText,
                headerDetail: detailText,
                footerTitle: footerText,
                completion: { continuation.resume() }
            )
        }

        #expect(listView.bounds == .zero)
        #expect(listView.tableView.bounds == .zero)
        #expect(listView.window == nil)
        #expect(listView.tableView.headerView(forSection: 0) == nil)
        #expect(listView.tableView.footerView(forSection: 0) == nil)
        #expect(
            listView.tableView.semanticContentAttribute == .unspecified
        )

        let viewController = UIViewController()
        viewController.view = listView
        viewController.view.semanticContentAttribute = .forceRightToLeft
        listView.applyLayoutDirection(.rightToLeft)
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }
        listView.tableView.layoutIfNeeded()

        let header = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footer = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        let footerContent = footer.sectionContentView
        headerContent.layoutIfNeeded()
        footerContent.layoutIfNeeded()

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == headerText)
        #expect(headerDetail.text == detailText)
        #expect(footerTitle.text == footerText)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(window.semanticContentAttribute == .unspecified)
        #expect(listView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            listView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            listView.tableView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(header.semanticContentAttribute == .forceRightToLeft)
        #expect(footer.semanticContentAttribute == .forceRightToLeft)
        #expect(
            headerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            footerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForHeader(inSection: 0).height
                    - header.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForFooter(inSection: 0).height
                    - footer.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.contentOffset.y
                    + listView.tableView.adjustedContentInset.top
            ) <= tolerance
        )
    }

    @Test func tableMessageSupplementariesRelayoutImmediatelyAfterLocalizationAndDirectionChange() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = MessageTableListView()
        let viewController = UIViewController()
        viewController.view = listView
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }

        let model = MessageModel(
            title: "Message",
            message: "Body",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            MessageListItem(
                id: MessageListItemID(group: 0, message: model.imageName),
                model: model
            )
        ]

        listView.applyLayoutDirection(.leftToRight)
        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: "Header",
                headerDetail: "Detail",
                footerTitle: "Footer",
                completion: { continuation.resume() }
            )
        }
        listView.tableView.layoutIfNeeded()

        let initialHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let initialFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let initialHeaderHeight = listView.tableView.rectForHeader(
            inSection: 0
        ).height
        let initialFooterHeight = listView.tableView.rectForFooter(
            inSection: 0
        ).height
        let initialContentOffset = listView.tableView.contentOffset

        let arabicHeader = "رسائل ذاتية التحجيم طويلة لاختبار الارتفاع"
        let arabicDetail = "يجب أن يتغير اتجاه هذا الرأس وارتفاعه فورًا من دون تمرير القائمة."
        let arabicFooter = "يجب أن يحدّث الرأس والتذييل الارتفاع مباشرة عند تبديل اللغة من الصينية إلى العربية من دون تمرير القائمة."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: arabicHeader,
                headerDetail: arabicDetail,
                footerTitle: arabicFooter,
                completion: { continuation.resume() }
            )
            // Match production ordering: localized content starts an
            // asynchronous ListKit apply before direction is updated.
            listView.applyLayoutDirection(.rightToLeft)
        }

        let updatedHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let updatedFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = updatedHeader.sectionContentView
        let footerContent = updatedFooter.sectionContentView

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == arabicHeader)
        #expect(headerDetail.text == arabicDetail)
        #expect(footerTitle.text == arabicFooter)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )

        #expect(updatedHeader === initialHeader)
        #expect(updatedFooter === initialFooter)
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(headerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(footerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            updatedHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            updatedFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            updatedHeader.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            updatedFooter.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            listView.tableView.rectForHeader(inSection: 0).height
                > initialHeaderHeight
        )
        #expect(
            listView.tableView.rectForFooter(inSection: 0).height
                > initialFooterHeight
        )

        let headerFittingSize = updatedHeader.systemLayoutSizeFitting(
            CGSize(width: updatedHeader.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = updatedFooter.systemLayoutSizeFitting(
            CGSize(width: updatedFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(updatedHeader.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(updatedFooter.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(listView.tableView.contentOffset.y - initialContentOffset.y)
                <= tolerance
        )
    }

    @Test func collectionMessageControllerReusesItsCellRegistration() throws {
        let viewController = MesssageViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        #expect(collectionView.numberOfItems(inSection: 0) == 4)
        #expect(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) is MessageCell
        )
    }

    @Test func dynamicScrollDemoFillsScreenAndProtectsItsOverlayAction() {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let buttonFrame = viewController.addButton.convert(
            viewController.addButton.bounds,
            to: viewController.view
        )
        let scrollFrame = viewController.scrollView.convert(
            viewController.scrollView.bounds,
            to: viewController.view
        )

        #expect(abs(scrollFrame.minX - viewController.view.bounds.minX) < 1)
        #expect(abs(scrollFrame.minY - viewController.view.bounds.minY) < 1)
        #expect(abs(scrollFrame.maxX - viewController.view.bounds.maxX) < 1)
        #expect(abs(scrollFrame.maxY - viewController.view.bounds.maxY) < 1)
        #expect(
            abs(buttonFrame.minY - viewController.view.safeAreaInsets.top) < 1
        )
        #expect(
            abs(
                buttonFrame.maxX
                    - viewController.view.bounds.maxX
                    + viewController.view.safeAreaInsets.right
                    + 16
            ) < 1
        )
        #expect(
            viewController.scrollView.adjustedContentInset.top
                >= buttonFrame.maxY - scrollFrame.minY + 7
        )
        #expect(viewController.scrollView.contentInset.left == 16)
        #expect(viewController.scrollView.contentInset.bottom == 8)
        #expect(viewController.scrollView.contentInset.right == 16)
        let indicatorInsets = viewController.scrollView
            .verticalScrollIndicatorInsets
        #expect(
            abs(
                indicatorInsets.top
                    - viewController.scrollView.contentInset.top
            ) < 1
        )
        #expect(
            abs(
                indicatorInsets.bottom
                    - viewController.scrollView.contentInset.bottom
            ) < 1
        )
    }

    @Test func dynamicScrollCardsExposeLocalizedDeletionAffordance() throws {
        let localizer = DemoLocalizer { key, arguments in
            guard !arguments.isEmpty else { return key }
            return key + ": "
                + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 2,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let titleLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hintLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let accentIcon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: card)
        let hintFrame = hintLabel.convert(hintLabel.bounds, to: card)
        let accentFrame = accentIcon.convert(accentIcon.bounds, to: card)
        let deleteFrame = deleteButton.convert(deleteButton.bounds, to: card)
        let titleCenter = titleLabel.convert(
            CGPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY),
            to: card
        )

        #expect(titleLabel.text == "dynamic.item.title: 1")
        #expect(hintLabel.text == "dynamic.item.deleteHint")
        #expect(accentIcon.image != nil)
        #expect(deleteButton.configuration?.image != nil)
        #expect(deleteButton.configuration?.cornerStyle == .capsule)
        #expect(card.bounds.height >= 80)
        #expect(deleteButton.bounds.width >= 44)
        #expect(deleteButton.bounds.height >= 44)
        #expect(card.bounds.contains(titleFrame))
        #expect(card.bounds.contains(hintFrame))
        #expect(card.bounds.contains(accentFrame))
        #expect(card.bounds.contains(deleteFrame))
        #expect(accentFrame.maxX <= min(titleFrame.minX, hintFrame.minX))
        #expect(max(titleFrame.maxX, hintFrame.maxX) <= deleteFrame.minX)

        #expect(!(card is UIControl))
        #expect(card.gestureRecognizers?.isEmpty ?? true)
        #expect(card.hitTest(titleCenter, with: nil) !== deleteButton)
        #expect(!card.isAccessibilityElement)
        #expect(titleLabel.isAccessibilityElement)
        #expect(titleLabel.accessibilityTraits.contains(.staticText))
        #expect(titleLabel.accessibilityLabel == "dynamic.item.title: 1")
        #expect(!hintLabel.isAccessibilityElement)
        #expect(!accentIcon.isAccessibilityElement)
        #expect(deleteButton.isAccessibilityElement)
        #expect(deleteButton.accessibilityTraits.contains(.button))
        #expect(
            deleteButton.accessibilityLabel
                == "dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "dynamic.item.deleteAccessibilityHint"
        )
    }

    @Test func dynamicScrollCachedCardMirrorsAndRelocalizesFromLTRToRTL() throws {
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, arguments in
            let suffix = arguments.isEmpty
                ? ""
                : ": " + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
            return prefix + key + suffix
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 1,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let icon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let title = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hint = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        card.layoutIfNeeded()

        let ltrCardWidth = card.bounds.width
        let ltrIconFrame = icon.convert(icon.bounds, to: card)
        let ltrDeleteFrame = deleteButton.convert(deleteButton.bounds, to: card)

        #expect(ltrIconFrame.midX < ltrDeleteFrame.midX)
        #expect(title.text == "ltr.dynamic.item.title: 1")

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        card.layoutIfNeeded()

        let updatedCard = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let updatedIcon = try #require(
            updatedCard.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let updatedDeleteButton = try #require(
            updatedCard.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let rtlIconFrame = updatedIcon.convert(updatedIcon.bounds, to: updatedCard)
        let rtlDeleteFrame = updatedDeleteButton.convert(
            updatedDeleteButton.bounds,
            to: updatedCard
        )
        let mirroredIconMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrIconFrame.midX
        let mirroredDeleteMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrDeleteFrame.midX

        #expect(updatedCard === card)
        #expect(updatedIcon === icon)
        #expect(updatedDeleteButton === deleteButton)
        #expect(updatedCard.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlIconFrame.midX > rtlDeleteFrame.midX)
        #expect(abs(rtlIconFrame.midX - mirroredIconMidX) < 1)
        #expect(abs(rtlDeleteFrame.midX - mirroredDeleteMidX) < 1)
        #expect(abs(updatedCard.bounds.width - ltrCardWidth) < 0.001)
        #expect(
            abs(rtlIconFrame.width - ltrIconFrame.width) < 0.001
                && abs(rtlIconFrame.height - ltrIconFrame.height) < 0.001
        )
        #expect(
            abs(rtlDeleteFrame.width - ltrDeleteFrame.width) < 0.001
                && abs(rtlDeleteFrame.height - ltrDeleteFrame.height) < 0.001
        )
        #expect(title.text == "rtl.dynamic.item.title: 1")
        #expect(hint.text == "rtl.dynamic.item.deleteHint")
        #expect(
            deleteButton.accessibilityLabel
                == "rtl.dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "rtl.dynamic.item.deleteAccessibilityHint"
        )
    }

    @Test func dynamicScrollAdditionsFinishAtTheNewBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let initialLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.9"
            }
        )
        let initialLastFrame = initialLastItem.convert(
            initialLastItem.bounds,
            to: viewController.scrollView
        )
        let initialContentHeight = viewController.scrollView.contentSize.height
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        viewController.addButton.sendActions(for: .touchUpInside)
        viewController.addButton.sendActions(for: .touchUpInside)

        let scrollView = viewController.scrollView
        let newLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.11"
            }
        )
        let newLastFrame = newLastItem.convert(
            newLastItem.bounds,
            to: scrollView
        )
        let expectedHeightIncrease = newLastFrame.maxY - initialLastFrame.maxY
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(expectedHeightIncrease > 0)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    - expectedHeightIncrease
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)
    }

    @Test func dynamicScrollDeleteButtonRemovesAndClampsAtTheBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let scrollView = viewController.scrollView
        scrollView.scrollTo(.bottom, animated: false)

        let itemViews = viewController.view.allSubviews(of: UIView.self)
        let previousItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let removedItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.4"
            }
        )
        let followingItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let deleteButton = try #require(
            removedItem.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.4.deleteButton"
            }
        )
        let previousFrame = previousItem.convert(previousItem.bounds, to: scrollView)
        let removedFrame = removedItem.convert(removedItem.bounds, to: scrollView)
        let followingFrame = followingItem.convert(followingItem.bounds, to: scrollView)
        let removedStride = followingFrame.minY - removedFrame.minY
        let initialContentHeight = scrollView.contentSize.height

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        deleteButton.sendActions(for: .touchUpInside)

        let survivingPreviousItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let survivingFollowingItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let updatedPreviousFrame = survivingPreviousItem.convert(
            survivingPreviousItem.bounds,
            to: scrollView
        )
        let updatedFollowingFrame = survivingFollowingItem.convert(
            survivingFollowingItem.bounds,
            to: scrollView
        )
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(removedItem.superview == nil)
        #expect(survivingPreviousItem === previousItem)
        #expect(survivingFollowingItem === followingItem)
        #expect(removedFrame.height >= 80)
        #expect(removedStride > removedFrame.height)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    + removedStride
            ) < 1
        )
        #expect(abs(updatedPreviousFrame.minY - previousFrame.minY) < 1)
        #expect(
            abs(
                updatedFollowingFrame.minY
                    - followingFrame.minY
                    + removedStride
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)

        let contentHeightAfterDeletion = scrollView.contentSize.height
        deleteButton.sendActions(for: .touchUpInside)
        #expect(
            abs(scrollView.contentSize.height - contentHeightAfterDeletion) < 1
        )
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

    @Test func keyboardContextParsesUIKitNotification() throws {
        let beginFrame = CGRect(x: 0, y: 844, width: 390, height: 0)
        let frame = CGRect(x: 0, y: 320, width: 390, height: 240)
        let notification = Notification(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameBeginUserInfoKey: beginFrame,
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.25,
                UIResponder.keyboardAnimationCurveUserInfoKey: UInt(UIView.AnimationCurve.easeInOut.rawValue),
            ]
        )

        let context = try #require(QuickLayoutKeyboardContext(notification: notification))

        #expect(context.event == .willShow)
        #expect(context.beginFrame == beginFrame)
        #expect(context.endFrame == frame)
        #expect(context.height == 240)
        #expect(context.animationDuration == 0.25)
        #expect(context.isVisible)
    }

    @Test func keyboardContextMapsChangeAndHideEvents() throws {
        let didChange = Notification(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 600, width: 390, height: 244),
            ]
        )
        let willHide = Notification(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 844, width: 390, height: 0),
            ]
        )

        let didChangeContext = try #require(QuickLayoutKeyboardContext(notification: didChange))
        let willHideContext = try #require(QuickLayoutKeyboardContext(notification: willHide))

        #expect(didChangeContext.event == .didChangeFrame)
        #expect(didChangeContext.isVisible)
        #expect(willHideContext.event == .willHide)
        #expect(!willHideContext.isVisible)
        #expect(willHideContext.height == 0)
    }

    @Test func keyboardContextResolvesVisibleIntersectionInTargetView() throws {
        let window = try makeVisibleTestWindow(
            rootViewController: UIViewController(),
            size: CGSize(width: 390, height: 844)
        )
        let fullScreenView = UIView(frame: window.bounds)
        let insetView = UIView(frame: CGRect(x: 0, y: 250, width: 390, height: 120))
        window.addSubview(fullScreenView)
        window.addSubview(insetView)

        let normalContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 600, width: 390, height: 244),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )
        let floatingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 40, y: 300, width: 220, height: 180),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )

        let normalResolved = normalContext.resolved(in: fullScreenView)
        let floatingResolved = floatingContext.resolved(in: insetView)

        #expect(normalResolved.height == 244)
        #expect(normalResolved.intersection == CGRect(x: 0, y: 600, width: 390, height: 244))
        #expect(!normalResolved.isFloatingOrSplitKeyboard)
        #expect(floatingResolved.keyboardFrameInView == CGRect(x: 40, y: 50, width: 220, height: 180))
        #expect(floatingResolved.intersection == CGRect(x: 40, y: 50, width: 220, height: 70))
        #expect(floatingResolved.height == 70)
        #expect(floatingResolved.height != floatingContext.endFrame.height)
        #expect(floatingResolved.isFloatingOrSplitKeyboard)
    }

    @Test func keyboardContextResolvesHardwareAndNonOverlappingKeyboardsToZero() throws {
        let window = try makeVisibleTestWindow(
            rootViewController: UIViewController(),
            size: CGSize(width: 390, height: 844)
        )
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.addSubview(scrollView)

        let nonOverlappingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 500, width: 390, height: 200),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )
        let hardwareContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 844, width: 390, height: 0),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        let nonOverlappingResolved = nonOverlappingContext.resolved(in: scrollView)
        let hardwareResolved = hardwareContext.resolved(in: scrollView)

        #expect(nonOverlappingResolved.height == 0)
        #expect(nonOverlappingResolved.intersection.isNull)
        #expect(hardwareResolved.height == 0)
        #expect(hardwareResolved.isHardwareKeyboardLikely)
    }

    @Test func keyboardAvoiderPreservesBaseScrollInsets() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentInset = UIEdgeInsets(top: 1, left: 2, bottom: 10, right: 4)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        scrollView.horizontalScrollIndicatorInsets = UIEdgeInsets(top: 9, left: 10, bottom: 11, right: 12)

        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter())
        )

        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 300, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        avoider.apply(visibleContext)

        #expect(scrollView.contentInset.bottom == 130)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 127)
        #expect(scrollView.horizontalScrollIndicatorInsets.bottom == 131)

        avoider.apply(.hidden)

        #expect(scrollView.contentInset.bottom == 10)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 7)
        #expect(scrollView.horizontalScrollIndicatorInsets.bottom == 11)
    }

    @Test func keyboardAvoiderUsesInjectedNotificationCenterForDefaultObserver() {
        let notificationCenter = NotificationCenter()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            notificationCenter: notificationCenter
        )
        let keyboardFrame = CGRect(x: 0, y: 360, width: 320, height: 120)

        notificationCenter.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )

        #expect(scrollView.contentInset.bottom == 120)
        _ = avoider
    }

    @Test func keyboardAvoiderAppliesSafeAreaStrategiesAndExtraPadding() {
        let scrollView = TestSafeAreaScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.testSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter()),
            notificationCenter: NotificationCenter()
        )
        avoider.extraBottomPadding = 8

        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 360, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )
        let nonOverlappingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 640, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )

        avoider.safeAreaStrategy = .ignore
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 138)

        avoider.safeAreaStrategy = .add
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 172)

        avoider.safeAreaStrategy = .subtractExisting
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 104)

        avoider.apply(nonOverlappingContext)
        #expect(scrollView.contentInset.bottom == 10)
    }

    @Test func keyboardAvoiderTracksCustomActiveInputNotification() {
        let notificationCenter = NotificationCenter()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        scrollView.contentSize = CGSize(width: 320, height: 640)
        let activeInput = UIView(frame: CGRect(x: 0, y: 520, width: 320, height: 44))
        scrollView.addSubview(activeInput)

        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter()),
            notificationCenter: notificationCenter
        )
        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 80, width: 320, height: 40),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        notificationCenter.post(
            name: .quickLayoutKeyboardActiveInputDidBeginEditing,
            object: nil,
            userInfo: ["activeView": activeInput]
        )
        avoider.apply(visibleContext)

        #expect(scrollView.contentOffset.y > 0)

        scrollView.setContentOffset(.zero, animated: false)
        notificationCenter.post(name: .quickLayoutKeyboardActiveInputDidEndEditing, object: activeInput)
        avoider.apply(visibleContext)

        #expect(scrollView.contentOffset.y == 0)
    }

    @Test func listCellMeasuresQuickLayoutContent() {
        let titleLabel = UILabel()
        titleLabel.text = "Title"
        let messageLabel = UILabel()
        messageLabel.text = "A long message that should wrap inside the proposed collection cell width."
        messageLabel.numberOfLines = 0

        let cell = QuickLayoutCollectionViewCell {
            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                messageLabel
            }
            .padding(.all, 12)
        }

        cell.quickLayoutHorizontalFlexibility = .fixedSize
        cell.quickLayoutVerticalFlexibility = .fullyFlexible

        let size = cell.sizeThatFits(CGSize(width: 180, height: 44))

        #expect(size.width == 180)
        #expect(size.height > 44)
    }

    @Test func directionalEnvironmentHelpersRespectLayoutDirection() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        view.semanticContentAttribute = .forceRightToLeft

        let margins = view.quickLayoutDirectionalLayoutMargins

        #expect(margins.top == 1)
        #expect(margins.leading == 2)
        #expect(margins.bottom == 3)
        #expect(margins.trailing == 4)
    }

    @Test func quickLayoutEnvironmentReflectsCurrentUIViewState() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.semanticContentAttribute = .forceRightToLeft
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 16, trailing: 20)

        let environment = view.quickLayoutEnvironment

        #expect(environment.layoutDirection == .rightToLeft)
        #expect(environment.preferredContentSizeCategory == view.traitCollection.preferredContentSizeCategory)
        #expect(environment.horizontalSizeClass == view.traitCollection.horizontalSizeClass)
        #expect(environment.verticalSizeClass == view.traitCollection.verticalSizeClass)
        #expect(environment.userInterfaceStyle == view.traitCollection.userInterfaceStyle)
        #expect(environment.displayScale == view.traitCollection.displayScale)
        #expect(environment.layoutMargins.leading == 12)
        #expect(environment.containerSize == CGSize(width: 320, height: 480))
        #expect(view.quickLayoutDirection == .rightToLeft)
    }

    @Test func quickLayoutEnvironmentReportsPublicChanges() {
        let previous = QuickLayoutEnvironment(
            layoutDirection: .leftToRight,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 375, height: 480)
        )
        let current = QuickLayoutEnvironment(
            layoutDirection: .rightToLeft,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 34, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 320, height: 480)
        )

        let changes = current.changes(from: previous)

        #expect(changes == [.layoutDirection, .safeArea, .containerSize])
        #expect(QuickLayoutEnvironmentChangeReason.all.isSuperset(of: changes))
    }

    @Test func quickLayoutViewNotifiesEnvironmentChangesFromMargins() {
        let hostingView = EnvironmentRecordingQuickLayoutView()
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        hostingView.layoutMargins = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        hostingView.layoutIfNeeded()

        hostingView.layoutMargins = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        hostingView.layoutMarginsDidChange()

        #expect(hostingView.environmentChanges.contains { $0.reason.contains(.layoutMargins) })
        #expect(hostingView.environmentChanges.last?.environment.layoutMargins.leading == 6)
    }

    @Test func diagnosticsRecordsLayoutPasses() {
        QuickLayoutDiagnostics.reset()
        QuickLayoutDiagnostics.isEnabled = true
        QuickLayoutDiagnostics.recordLayoutPass(for: "TestView", measuredSize: CGSize(width: 10, height: 20))

        let snapshot = QuickLayoutDiagnostics.snapshot()

        #expect(snapshot.totalLayoutPasses == 1)
        #expect(snapshot.entries.first?.viewName == "TestView")

        QuickLayoutDiagnostics.isEnabled = false
        QuickLayoutDiagnostics.reset()
    }

    @Test func lazyRepresentableDoesNotLoadUntilIncludedInBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var loadCount = 0
        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "A"))
        }

        var showsChild = false
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded == nil)
        #expect(loadCount == 0)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(loadCount == 1)
    }

    @Test func representableAttachesAndDetachesWithQuickLayoutBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []

        let lazyRepresentable = LazyView {
            let representable = QuickLayoutViewControllerRepresentable(child)
            representable.eventHandler = { events.append($0.name) }
            return representable
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent === parent)
        #expect(parent.children.contains { $0 === child })
        #expect(events.contains("willAttach"))
        #expect(events.contains("didAttach"))

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(!parent.children.contains { $0 === child })
        #expect(lazyRepresentable.isLoaded)
        #expect(events.contains("willDetach"))
        #expect(events.contains("didDetach"))
    }

    @Test func lazyRepresentableReusesLoadedHostAndCanReplaceChild() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var loadCount = 0

        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(firstChild)
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(loadCount == 1)
        #expect(firstChild.parent === parent)

        lazyRepresentable.ifLoaded?.setViewController(secondChild)

        #expect(firstChild.parent == nil)
        #expect(secondChild.parent === parent)
    }

    @Test func representableDetailedEventsIncludeContainmentContext() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var detailedEvents: [QuickLayoutViewControllerRepresentable.DetailedEvent] = []

        let representable = QuickLayoutViewControllerRepresentable(firstChild)
        representable.detailedEventHandler = { detailedEvents.append($0) }
        parent.view.addSubview(representable)
        representable.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        representable.layoutIfNeeded()
        representable.setViewController(secondChild)

        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .willDetach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === secondChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didReplaceViewController && $0.oldViewController === firstChild && $0.newViewController === secondChild
        })
    }

    @Test func representableInvalidatesChildPreferredContentSize() {
        let child = RepresentableTestChildViewController(name: "A")
        let representable = QuickLayoutViewControllerRepresentable(child)

        let firstSize = representable.sizeThatFits(CGSize(width: 400, height: 400))
        child.preferredContentSize = CGSize(width: 240, height: 180)
        representable.invalidateChildLayout()
        let secondSize = representable.sizeThatFits(CGSize(width: 400, height: 400))

        #expect(firstSize.height == 96)
        #expect(secondSize.height == 180)
    }

    @Test func resettingLazyRepresentableCreatesANewHostOnNextLayout() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var hostCreationCount = 0
        func makeLazyRepresentable() -> LazyView<QuickLayoutViewControllerRepresentable> {
            LazyView {
                hostCreationCount += 1
                return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "\(hostCreationCount)"))
            }
        }

        var lazyRepresentable = makeLazyRepresentable()
        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 1)
        #expect(lazyRepresentable.isLoaded)
        let firstHost = lazyRepresentable.ifLoaded!

        firstHost.dismantleViewController()
        showsChild = false
        lazyRepresentable = makeLazyRepresentable()
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 2)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(lazyRepresentable.ifLoaded! !== firstHost)
    }

    @Test func parentlessRepresentableDoesNotAttachWithoutControllerOwnedHierarchy() {
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []
        let representable = QuickLayoutViewControllerRepresentable(child)
        representable.eventHandler = { events.append($0.name) }

        let containerView = QuickLayoutView {
            representable.frame(height: 120)
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(events.contains("missingParent"))
        #expect(!events.contains("didAttach"))
    }

    @Test func demoLocalizationResolvesCoreLanguages() {
        DemoLocalization.setLocale(identifier: "en-US")
        #expect(DemoLocalization.text("main.title") == "Examples")
        #expect(DemoLocalization.text("demo.localizationOverview.title") == "Language Center")

        DemoLocalization.setLocale(identifier: "zh-Hans")
        #expect(DemoLocalization.text("main.title") == "示例")
        #expect(DemoLocalization.text("language.follow.system") == "跟随系统")

        DemoLocalization.setLocale(identifier: "ar")
        #expect(DemoLocalization.text("main.title") == "الأمثلة")
        #expect(DemoLocalization.text("profile.section.about") == "نبذة")
        #expect(
            DemoLocalization.text("profile.skill.localization")
                == "التوطين"
        )
        #expect(
            DemoLocalization.text("profile.action.portfolio")
                == "معرض الأعمال"
        )
        #expect(
            DemoLocalization.text("uikit.showModal")
                == "عرض نافذة مشروطة"
        )
        #expect(
            DemoLocalization.text("boundary.recreateAlert")
                == "إعادة إنشاء التنبيه"
        )
        #expect(DemoLocalization.text("navigation.leading") == "عنصر البداية")
        #expect(DemoLocalization.text("navigation.trailing") == "عنصر النهاية")
        #expect(
            DemoLocalization.text(
                "navigation.edge.summary",
                DemoLocalization.text("navigation.edge.right"),
                "chevron.right"
            ).removingBidiIsolationMarks
                == "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
        )
        #expect(
            DemoLocalization.text("gesture.translation", Int64(0))
                == "الإزاحة الأفقية: 0"
        )
        #expect(
            DemoLocalization.text(
                "gesture.backSwipe",
                DemoLocalization.text("common.boolean.false")
            ).removingBidiIsolationMarks == "إيماءة الرجوع: لا"
        )
        #expect(DemoLocalization.currentLayoutDirection == .rightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func arabicDiagnosticScreensRenderLocalizedText() throws {
        DemoLocalization.setLocale(identifier: "ar")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

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

    @Test func languageMenuUsesSemanticTrailingEdgeAcrossDirectionChanges() {
        let viewController = UIViewController()
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        DemoLocalization.setLocale(identifier: "zh-Hans")
        DemoLocalization.installLanguageMenu(on: viewController)

        let languageItem = viewController.navigationItem.rightBarButtonItem
        #expect(languageItem != nil)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)

        DemoLocalization.setLocale(identifier: "ar")
        DemoLocalization.reloadLanguageMenu(on: viewController)

        #expect(viewController.navigationItem.leftBarButtonItem === languageItem)
        #expect(viewController.navigationItem.rightBarButtonItem == nil)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        DemoLocalization.reloadLanguageMenu(on: viewController)

        #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
    }

    @Test func plainNavigationPreviewReceivesLanguageMenuSelections() async throws {
        DemoLocalization.setLocale(identifier: "en-US")

        let profileViewController = ProfileViewController()
        let navigationController = UINavigationController(
            rootViewController: profileViewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )

        defer {
            DemoLocalization.unregister(window: window)
            window.isHidden = true
            DemoLocalization.setLocale(identifier: "en-US")
        }

        #expect(profileViewController.title == "Profile")

        DemoLocalization.setLocale(identifier: "ar")
        let appliedArabic = await waitForCondition {
            profileViewController.title
                == DemoLocalization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceRightToLeft
                && profileViewController.view.semanticContentAttribute
                    == .forceRightToLeft
        }
        #expect(appliedArabic)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        let appliedChinese = await waitForCondition {
            profileViewController.title
                == DemoLocalization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceLeftToRight
                && profileViewController.view.semanticContentAttribute
                    == .forceLeftToRight
        }
        #expect(appliedChinese)
    }

    @Test func localizationStringCatalogContainsSupportedLocales() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        for key in [
            "main.title",
            "demo.safeAreaPadding.title",
            "safeAreaPadding.intro",
            "safeAreaPadding.previous",
            "safeAreaPadding.next",
            "demo.localizationOverview.title",
            "demo.uikitLocalization.title",
            "demo.swiftUIBridge.title",
            "demo.tableMessages.title",
            "demo.tableMessages.header",
            "demo.tableMessages.header.detail",
            "demo.tableMessages.footer",
            "dynamic.item.title",
            "dynamic.item.deleteHint",
            "dynamic.item.deleteButton",
            "dynamic.item.deleteAccessibilityHint",
            "common.boolean.false",
            "common.boolean.true",
            "gesture.translation",
            "keyboard.diagnostics.event",
            "keyboard.diagnostics.height",
            "keyboard.diagnostics.intersection",
            "keyboard.diagnostics.rawFrame",
            "navigation.edge.left",
            "navigation.edge.right",
            "navigation.edge.summary",
        ] {
            let localizations = try #require(catalog.strings[key]?.localizations)
            #expect(localizations["en"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["zh-Hans"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
        }
    }

    @Test func arabicLocalizationsDoNotContainHanCharacters() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        let keysContainingHan: [String] = catalog.strings.compactMap {
            key, entry -> String? in
            guard let value = entry.localizations?["ar"]?.stringUnit.value else {
                return nil
            }
            let containsHan = value.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                    return true
                default:
                    return false
                }
            }
            return containsHan ? key : nil
        }

        #expect(keysContainingHan.isEmpty)
    }

    @Test func infoPlistStringCatalogContainsDisplayName() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("InfoPlist.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)
        let localizations = try #require(catalog.strings["CFBundleDisplayName"]?.localizations)

        #expect(localizations["en"]?.stringUnit.value == "QuickLayoutKit Demo")
        #expect(localizations["zh-Hans"]?.stringUnit.value == "QuickLayoutKit 演示")
        #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
    }

    @Test func mainMenuUsesListKitCellsWithQuickLayoutContentViews() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        #expect(main.view is QuickLayoutView)
        #expect(main.collectionView.superview === main.view)
        #expect(main.view.allSubviews(of: QuickLayoutScrollView.self).isEmpty)
        #expect(main.collectionView.numberOfSections == 3)
        #expect(main.collectionView.numberOfItems(inSection: 0) == 13)
        #expect(main.collectionView.numberOfItems(inSection: 1) == 1)
        #expect(main.collectionView.numberOfItems(inSection: 2) == 6)

        let cell = try mainMenuCell(
            at: IndexPath(item: 0, section: 0),
            in: main
        )
        let configuration = try #require(
            cell.contentConfiguration as? MainMenuContentConfiguration
        )
        let contentView = try #require(
            cell
                .allSubviews(of: MainMenuContentView.self)
                .first
        )

        #expect(configuration.title == "横向滚动")
        #expect(contentView.titleLabel.text == configuration.title)
        #expect(contentView.superview != nil)
        #expect(
            contentView.intrinsicContentSize
                == CGSize(
                    width: UIView.noIntrinsicMetric,
                    height: UIView.noIntrinsicMetric
                )
        )

        let narrowSize = contentView.sizeThatFits(
            CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        )
        let wideSize = contentView.sizeThatFits(
            CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        #expect(abs(narrowSize.width - 180) < 1)
        #expect(abs(wideSize.width - 320) < 1)
        #expect(narrowSize.height >= 52)
        #expect(wideSize.height >= 52)
        #expect(cell.accessories.isEmpty)
    }

    @Test func mainMenuReloadsRouteTitlesAfterLanguageChange() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            testWindow.isHidden = true
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let chineseTitles = try [0, 1, 4].map { item in
            try mainMenuConfiguration(
                at: IndexPath(item: item, section: 2),
                in: main
            ).title
        }

        #expect(chineseTitles == ["语言中心", "UIKit 本地化", "SwiftUI 桥接"])

        DemoLocalization.setLocale(identifier: "ar")
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
            arabicConfiguration.title
                == DemoLocalizer.live.text("demo.localizationOverview.title")
        )
        #expect(
            arabicCell.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }

    @Test func allLoadedUIKitDemoButtonsUseConfigurations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            DemoLocalization.setLocale(identifier: "en-US")
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

        let router = DemoRouter()
        var inspectedButtonCount = 0

        // SwiftUI owns the implementation behind SwiftUI.Button; this guard
        // covers the UIKit buttons authored by the Demo target.
        for route in DemoRoute.allCases where route != .swiftUIBridge {
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

    @Test func mainMenuSectionHeadersFollowQuickLayoutDirection() throws {
        DemoLocalization.setLocale(identifier: "ar")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.reloadLayoutDirection(.rightToLeft)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let headerView = try #require(
            main.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? MainMenuSectionHeaderView
        )
        let quickLayoutHeader = headerView.titleLabel

        #expect(quickLayoutHeader.textAlignment == .natural)
        #expect(
            main.collectionView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            quickLayoutHeader.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        let rightToLeftFrame = quickLayoutHeader.convert(
            quickLayoutHeader.bounds,
            to: headerView
        )
        #expect(rightToLeftFrame.maxX > headerView.bounds.width - 32)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let leftToRightHeaderView = try #require(
            main.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? MainMenuSectionHeaderView
        )
        let leftToRightHeader = leftToRightHeaderView.titleLabel

        #expect(leftToRightHeader.text == "QuickLayout 示例")
        #expect(leftToRightHeader.textAlignment == .natural)
        #expect(
            leftToRightHeader.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        let leftToRightFrame = leftToRightHeader.convert(
            leftToRightHeader.bounds,
            to: leftToRightHeaderView
        )
        #expect(leftToRightFrame.minX < 32)
        #expect(leftToRightFrame.minX < rightToLeftFrame.minX)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func mainMenuRebuildsAndMirrorsItsQuickLayoutContentRoundTrip() throws {
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
                .allSubviews(of: MainMenuContentView.self)
                .first
        )
        let ltrTitleFrame = contentView.titleLabel.convert(
            contentView.titleLabel.bounds,
            to: contentView
        )
        let ltrChevronFrame = contentView.disclosureImageView.convert(
            contentView.disclosureImageView.bounds,
            to: contentView
        )

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
                .allSubviews(of: MainMenuContentView.self)
                .first
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlChevronFrame = rtlContentView.disclosureImageView.convert(
            rtlContentView.disclosureImageView.bounds,
            to: rtlContentView
        )

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
        #expect(rtlContentView.quickLayoutEnvironment.layoutDirection == .rightToLeft)
        #expect(rtlTitleFrame.minX > ltrTitleFrame.minX)
        #expect(rtlChevronFrame.minX < ltrChevronFrame.minX)

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
                .allSubviews(of: MainMenuContentView.self)
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
            restoredContentView.quickLayoutEnvironment.layoutDirection
                == .leftToRight
        )
        #expect(
            restoredContentView.titleLabel.convert(
                restoredContentView.titleLabel.bounds,
                to: restoredContentView
            ).approximatelyEquals(ltrTitleFrame)
        )
    }

    @Test func mainMenuSelectionRoutesThroughListKit() throws {
        let router = RecordingDemoRouter()
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
            DemoLocalization.layoutDirectionUpdate(.rightToLeft),
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
            DemoLocalization.layoutDirectionUpdate(.leftToRight),
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
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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
        DemoLocalization.setLocale(identifier: "ar")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
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

        DemoLocalization.setLocale(identifier: "en-US")
        viewController.applyLocalization(
            .initial(
                snapshot: DemoLocalization.localizationController.currentSnapshot
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
            DemoLocalization.text("profile.section.about"),
            DemoLocalization.text("profile.section.activity"),
            DemoLocalization.text("profile.section.skills")
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
        let firstSkillTitle = DemoLocalization.text("profile.skill.uikit")
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

    @Test func overviewPageReflectsArabicDirection() {
        DemoLocalization.setLocale(identifier: "ar")
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

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func uikitShowcaseAppliesCollectionDirection() throws {
        DemoLocalization.setLocale(identifier: "ar")
        let viewController = UIKitLocalizationShowcaseViewController()
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.rightToLeft)

        let collectionView = try #require(viewController.view.allSubviews(of: UICollectionView.self).first)

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func localizationOverviewMirrorsItsReusedLeadingContent() throws {
        var usesRightToLeftLayout = false
        let localizer = DemoLocalizer { key, _ in key }
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
        let viewController = SemanticContentDemoViewController()
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

    @Test func representableParentRelaysDirectionToItsExistingChild() throws {
        let viewController = ViewControllerRepresentableDemoViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let stateLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text?.contains("LazyView isLoaded") == true
            }
        )
        let showButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first
        )
        let ltrStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        let rtlStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        #expect(stateLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            isHorizontalMirror(
                rtlStateFrame,
                of: ltrStateFrame,
                in: scrollView.contentSize.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        #expect(
            stateLabel.convert(stateLabel.bounds, to: scrollView)
                .approximatelyEquals(ltrStateFrame)
        )

        showButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        let child = try #require(viewController.children.first)
        let childView = child.view!
        let childIdentity = ObjectIdentifier(child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(ObjectIdentifier(viewController.children[0]) == childIdentity)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let childLabels = childView.subviews.compactMap { $0 as? UILabel }
        let childButtons = childView.subviews.compactMap { $0 as? UIButton }
        #expect(childLabels.count == 2)
        #expect(childButtons.count == 1)
        #expect(childButtons.allSatisfy { $0.configuration != nil })
        #expect(
            childLabels.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )
        #expect(
            childButtons.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)
    }

    @Test func keyboardControllerUpdatesItsNestedViewWithoutMovingVerticalContent() throws {
        let viewController = KeyboardHandlingViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let keyboardView = try #require(
            viewController.view
                .allSubviews(of: AnimatedKeyboardResponsiveView.self)
                .first
        )
        keyboardView.layoutIfNeeded()
        let textField = keyboardView.textField
        let submitButton = keyboardView.submitButton
        let ltrTextFieldFrame = textField.convert(textField.bounds, to: keyboardView)
        let ltrSubmitFrame = submitButton.convert(
            submitButton.bounds,
            to: keyboardView
        )

        #expect(ltrTextFieldFrame.maxY < ltrSubmitFrame.minY)
        #expect(textField.textAlignment == .left)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        keyboardView.layoutIfNeeded()

        #expect(keyboardView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(keyboardView.semanticContentAttribute == .forceRightToLeft)
        #expect(textField.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(submitButton.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(textField.textAlignment == .right)
        #expect(
            textField.convert(textField.bounds, to: keyboardView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
        #expect(
            submitButton.convert(submitButton.bounds, to: keyboardView)
                .approximatelyEquals(ltrSubmitFrame)
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        keyboardView.layoutIfNeeded()

        #expect(keyboardView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(textField.textAlignment == .left)
        #expect(
            textField.convert(textField.bounds, to: keyboardView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
        #expect(
            submitButton.convert(submitButton.bounds, to: keyboardView)
                .approximatelyEquals(ltrSubmitFrame)
        )
    }

    @Test func collectionMessagesInheritDirectionForVisibleAndNewContent() async throws {
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, _ in prefix + key }
        let viewController = MesssageViewController(
            viewModel: MessageListViewModel(
                configuration: .collection,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 220)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        #expect(
            !collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )

        let cell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let contentView = cell.messageContentView
        contentView.layoutIfNeeded()
        let avatarView = contentView.avatarView
        let titleLabel = contentView.titleLabel
        let ltrAvatarFrame = avatarView.convert(avatarView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)
        // Local QuickLayout frames can look correct while UICollectionView's
        // reusable-view coordinate mapping is still mirrored. Keep a physical
        // window-space baseline to catch that stale UIKit state.
        let ltrAvatarWindowFrame = avatarView.convert(
            avatarView.bounds,
            to: window
        )
        let ltrTitleWindowFrame = titleLabel.convert(
            titleLabel.bounds,
            to: window
        )

        #expect(titleLabel.text == "ltr.messages.title.1")
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(cell.semanticContentAttribute == .forceLeftToRight)
        #expect(cell.contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(avatarView.semanticContentAttribute == .unspecified)
        #expect(titleLabel.semanticContentAttribute == .unspecified)
        #expect(contentView.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrAvatarFrame.midX < ltrTitleFrame.midX)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let rtlCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let rtlContentView = rtlCell.messageContentView
        rtlContentView.layoutIfNeeded()
        let rtlAvatarFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: rtlContentView
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlAvatarWindowFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: window
        )
        let rtlTitleWindowFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: window
        )

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(rtlCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(rtlContentView.avatarView.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.titleLabel.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlAvatarFrame.midX > rtlTitleFrame.midX)
        #expect(rtlAvatarWindowFrame.midX > rtlTitleWindowFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlAvatarFrame,
                of: ltrAvatarFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTitleFrame,
                of: ltrTitleFrame,
                in: rtlContentView.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let returnedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let returnedContent = returnedCell.messageContentView
        returnedContent.layoutIfNeeded()

        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(returnedCell.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.contentView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(returnedContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(returnedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(returnedContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedCell.transform == .identity)
        #expect(returnedCell.contentView.transform == .identity)
        #expect(returnedContent.transform == .identity)
        #expect(returnedContent.titleLabel.transform == .identity)
        #expect(CATransform3DIsIdentity(returnedCell.layer.transform))
        #expect(CATransform3DIsIdentity(returnedCell.layer.sublayerTransform))
        #expect(CATransform3DIsIdentity(returnedContent.layer.transform))
        #expect(
            CATransform3DIsIdentity(returnedContent.layer.sublayerTransform)
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrAvatarFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrTitleFrame)
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: window
            )
                .approximatelyEquals(ltrAvatarWindowFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: window
            )
                .approximatelyEquals(ltrTitleWindowFrame)
        )

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? MessageCell
            else {
                return false
            }
            return cell.messageContentView.titleLabel.text
                == "rtl.messages.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let localizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let localizedContent = localizedCell.messageContentView
        localizedContent.layoutIfNeeded()
        #expect(localizedContent.titleLabel.text == "rtl.messages.title.1")
        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(localizedCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(localizedContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(localizedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(localizedContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )

        collectionView.scrollToItem(
            at: IndexPath(item: 3, section: 0),
            at: .bottom,
            animated: false
        )
        collectionView.layoutIfNeeded()

        let newlyVisibleCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 3, section: 0)
            ) as? MessageCell
        )
        let newlyVisibleContent = newlyVisibleCell.messageContentView
        newlyVisibleCell.layoutIfNeeded()
        newlyVisibleContent.layoutIfNeeded()
        let newAvatarFrame = newlyVisibleContent.avatarView.convert(
            newlyVisibleContent.avatarView.bounds,
            to: newlyVisibleContent
        )
        let newTitleFrame = newlyVisibleContent.titleLabel.convert(
            newlyVisibleContent.titleLabel.bounds,
            to: newlyVisibleContent
        )

        #expect(
            collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )
        #expect(newlyVisibleContent.titleLabel.text == "rtl.messages.title.4")
        #expect(newlyVisibleCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            newlyVisibleContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(newlyVisibleContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newAvatarFrame.midX > newTitleFrame.midX)

        prefix = "returned."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.leftToRight)
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: false
        )
        let returnedLocalizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? MessageCell
            else {
                return false
            }
            return cell.messageContentView.titleLabel.text
                == "returned.messages.title.1"
        }
        #expect(returnedLocalizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let returnedLocalizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let returnedLocalizedContent = returnedLocalizedCell.messageContentView
        returnedLocalizedContent.layoutIfNeeded()
        let returnedLocalizedAvatarWindowFrame =
            returnedLocalizedContent.avatarView.convert(
                returnedLocalizedContent.avatarView.bounds,
                to: window
            )
        let returnedLocalizedTitleWindowFrame =
            returnedLocalizedContent.titleLabel.convert(
                returnedLocalizedContent.titleLabel.bounds,
                to: window
            )

        #expect(
            returnedLocalizedContent.titleLabel.text
                == "returned.messages.title.1"
        )
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedLocalizedContent.semanticContentAttribute
                == .forceLeftToRight
        )
        // 文本宽度可以因语言变化而不同；物理 leading 坐标必须回到初始 LTR，
        // 这能捕获局部 frame 正确但 window 坐标仍残留 RTL 镜像的回归。
        #expect(
            abs(
                returnedLocalizedAvatarWindowFrame.minX
                    - ltrAvatarWindowFrame.minX
            ) < 0.5
        )
        #expect(
            abs(
                returnedLocalizedTitleWindowFrame.minX
                    - ltrTitleWindowFrame.minX
            ) < 0.5
        )
        #expect(
            returnedLocalizedAvatarWindowFrame.midX
                < returnedLocalizedTitleWindowFrame.midX
        )
    }

    @Test func tableMessagesInheritDirectionForVisibleAndNewContent() async throws {
        let sectionHorizontalPadding: CGFloat = 16
        let sectionEdgeTolerance: CGFloat = 1
        let sectionSizingTolerance: CGFloat = 1.01
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, _ in prefix + key }
        let viewController = MessageTableViewController(
            viewModel: MessageListViewModel(
                configuration: .table,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 260)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let tableView = try #require(viewController.tableView)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        #expect(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            ) == nil
        )

        let cell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let contentView = cell.messageContentView
        contentView.layoutIfNeeded()
        let avatarView = contentView.avatarView
        let titleLabel = contentView.titleLabel
        let ltrAvatarFrame = avatarView.convert(avatarView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        headerContent.layoutIfNeeded()
        let headerTitleLabel = headerContent.titleLabel
        let headerDetailLabel = headerContent.detailLabel
        #expect(headerTitleLabel.text == "ltr.demo.tableMessages.header")
        #expect(
            headerDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let ltrHeaderTitleFrame = headerTitleLabel.convert(
            headerTitleLabel.bounds,
            to: headerContent
        )
        let ltrHeaderDetailFrame = headerDetailLabel.convert(
            headerDetailLabel.bounds,
            to: headerContent
        )

        #expect(titleLabel.text == "ltr.messages.title.1")
        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            cell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrAvatarFrame.midX < ltrTitleFrame.midX)
        #expect(headerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            header.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrHeaderTitleFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                ltrHeaderDetailFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        let footer = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footerContent = footer.sectionContentView
        footerContent.layoutIfNeeded()
        let footerTitleLabel = footerContent.titleLabel
        let footerDetailLabel = footerContent.detailLabel
        #expect(footerTitleLabel.text == "ltr.demo.tableMessages.footer")
        #expect(footerDetailLabel.text == nil)
        let ltrFooterTitleFrame = footerTitleLabel.convert(
            footerTitleLabel.bounds,
            to: footerContent
        )

        #expect(footerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrFooterTitleFrame.minX
                    - (footerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 0, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()

        let rtlCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let rtlContentView = rtlCell.messageContentView
        rtlContentView.layoutIfNeeded()
        let rtlAvatarFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: rtlContentView
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let rtlHeaderContent = rtlHeader.sectionContentView
        rtlHeaderContent.layoutIfNeeded()
        let rtlHeaderTitleLabel = rtlHeaderContent.titleLabel
        let rtlHeaderDetailLabel = rtlHeaderContent.detailLabel
        #expect(rtlHeaderTitleLabel.text == "ltr.demo.tableMessages.header")
        #expect(
            rtlHeaderDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let rtlHeaderTitleFrame = rtlHeaderTitleLabel.convert(
            rtlHeaderTitleLabel.bounds,
            to: rtlHeaderContent
        )
        let rtlHeaderDetailFrame = rtlHeaderDetailLabel.convert(
            rtlHeaderDetailLabel.bounds,
            to: rtlHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlAvatarFrame.midX > rtlTitleFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlAvatarFrame,
                of: ltrAvatarFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTitleFrame,
                of: ltrTitleFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(rtlHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlHeaderContent.frame)
        )
        #expect(
            rtlHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeader.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlHeaderTitleFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                rtlHeaderDetailFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderTitleFrame,
                of: ltrHeaderTitleFrame,
                in: rtlHeaderContent.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderDetailFrame,
                of: ltrHeaderDetailFrame,
                in: rtlHeaderContent.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let returnedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let returnedContent = returnedCell.messageContentView
        returnedContent.layoutIfNeeded()
        let returnedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let returnedHeaderContent = returnedHeader.sectionContentView
        returnedHeaderContent.layoutIfNeeded()
        let returnedHeaderTitleLabel = returnedHeaderContent.titleLabel
        let returnedHeaderDetailLabel = returnedHeaderContent.detailLabel
        #expect(
            returnedHeaderTitleLabel.text
                == "ltr.demo.tableMessages.header"
        )
        #expect(
            returnedHeaderDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let returnedHeaderTitleFrame = returnedHeaderTitleLabel.convert(
            returnedHeaderTitleLabel.bounds,
            to: returnedHeaderContent
        )
        let returnedHeaderDetailFrame = returnedHeaderDetailLabel.convert(
            returnedHeaderDetailLabel.bounds,
            to: returnedHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedHeaderContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedHeaderTitleFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedHeaderDetailFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrAvatarFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrTitleFrame)
        )

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let header = tableView.headerView(forSection: 0)
                    as? MessageTableHeaderFooterView,
                let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                    as? MessageTableCell
            else {
                return false
            }
            return header.sectionContentView.titleLabel.text
                    == "rtl.demo.tableMessages.header"
                && cell.messageContentView.titleLabel.text
                    == "rtl.messages.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let localizedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let localizedContent = localizedCell.messageContentView
        localizedContent.layoutIfNeeded()
        let localizedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let localizedHeaderContent = localizedHeader.sectionContentView
        localizedHeaderContent.layoutIfNeeded()
        let localizedHeaderTitleLabel = localizedHeaderContent.titleLabel
        let localizedHeaderDetailLabel = localizedHeaderContent.detailLabel
        #expect(
            localizedHeaderTitleLabel.text
                == "rtl.demo.tableMessages.header"
        )
        #expect(
            localizedHeaderDetailLabel.text
                == "rtl.demo.tableMessages.header.detail"
        )
        let localizedHeaderTitleFrame = localizedHeaderTitleLabel.convert(
            localizedHeaderTitleLabel.bounds,
            to: localizedHeaderContent
        )
        let localizedHeaderDetailFrame = localizedHeaderDetailLabel.convert(
            localizedHeaderDetailLabel.bounds,
            to: localizedHeaderContent
        )

        #expect(localizedContent.titleLabel.text == "rtl.messages.title.1")
        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(localizedHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                localizedHeaderTitleFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                localizedHeaderDetailFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.headerView(forSection: 0) == nil)

        let newlyVisibleCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            ) as? MessageTableCell
        )
        let newlyVisibleContent = newlyVisibleCell.messageContentView
        newlyVisibleCell.layoutIfNeeded()
        newlyVisibleContent.layoutIfNeeded()
        let newAvatarFrame = newlyVisibleContent.avatarView.convert(
            newlyVisibleContent.avatarView.bounds,
            to: newlyVisibleContent
        )
        let newTitleFrame = newlyVisibleContent.titleLabel.convert(
            newlyVisibleContent.titleLabel.bounds,
            to: newlyVisibleContent
        )
        let rtlFooter = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let rtlFooterContent = rtlFooter.sectionContentView
        rtlFooterContent.layoutIfNeeded()
        let rtlFooterTitleLabel = rtlFooterContent.titleLabel
        let rtlFooterDetailLabel = rtlFooterContent.detailLabel
        #expect(rtlFooterTitleLabel.text == "rtl.demo.tableMessages.footer")
        #expect(rtlFooterDetailLabel.text == nil)
        let rtlFooterTitleFrame = rtlFooterTitleLabel.convert(
            rtlFooterTitleLabel.bounds,
            to: rtlFooterContent
        )

        #expect(newlyVisibleContent.titleLabel.text == "rtl.messages.title.4")
        #expect(newlyVisibleContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newAvatarFrame.midX > newTitleFrame.midX)
        #expect(rtlFooterContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlFooterContent.frame)
        )
        #expect(
            rtlFooter.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlFooterTitleFrame.maxX
                    - (rtlFooterContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        let rtlFooterFittingSize = rtlFooter.systemLayoutSizeFitting(
            CGSize(width: rtlFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(rtlFooter.bounds.height - rtlFooterFittingSize.height)
                <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForFooter(inSection: 0).height
                    - rtlFooter.bounds.height
            ) <= sectionSizingTolerance
        )

        tableView.setContentOffset(
            CGPoint(
                x: tableView.contentOffset.x,
                y: -tableView.adjustedContentInset.top
            ),
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.footerView(forSection: 0) == nil)

        let returnedRTLHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let returnedRTLHeaderContent = returnedRTLHeader.sectionContentView
        returnedRTLHeaderContent.layoutIfNeeded()
        let returnedRTLHeaderTitleLabel = returnedRTLHeaderContent.titleLabel
        let returnedRTLHeaderDetailLabel = returnedRTLHeaderContent.detailLabel
        #expect(
            returnedRTLHeaderTitleLabel.text
                == "rtl.demo.tableMessages.header"
        )
        #expect(
            returnedRTLHeaderDetailLabel.text
                == "rtl.demo.tableMessages.header.detail"
        )
        let returnedRTLHeaderTitleFrame = returnedRTLHeaderTitleLabel.convert(
            returnedRTLHeaderTitleLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderDetailFrame = returnedRTLHeaderDetailLabel.convert(
            returnedRTLHeaderDetailLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderFittingSize = returnedRTLHeader
            .systemLayoutSizeFitting(
                CGSize(width: returnedRTLHeader.bounds.width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            returnedRTLHeaderContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            returnedRTLHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedRTLHeaderTitleFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeaderDetailFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeader.bounds.height
                    - returnedRTLHeaderFittingSize.height
            ) <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForHeader(inSection: 0).height
                    - returnedRTLHeader.bounds.height
            ) <= sectionSizingTolerance
        )
    }

    @Test func semanticGestureUsesDirectionalLayout() {
        DemoLocalization.setLocale(identifier: "ar")

        let physicalRight = DirectionalLayout.semanticHorizontalDirection(
            translationX: 20,
            layoutDirection: DemoLocalization.currentLayoutDirection
        )
        let isBackSwipe = DirectionalLayout.isBackSwipe(
            translationX: -20,
            layoutDirection: DemoLocalization.currentLayoutDirection
        )

        #expect(physicalRight == .leading)
        #expect(isBackSwipe)

        DemoLocalization.setLocale(identifier: "en-US")
    }
}

private struct TestStringCatalog: Decodable {
    let strings: [String: TestStringCatalogEntry]
}

private struct TestStringCatalogEntry: Decodable {
    let localizations: [String: TestStringLocalization]?
}

private struct TestStringLocalization: Decodable {
    let stringUnit: TestStringUnit
}

private struct TestStringUnit: Decodable {
    let value: String
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
) throws -> MainMenuContentConfiguration {
    let cell = try mainMenuCell(at: indexPath, in: viewController)
    return try #require(
        cell.contentConfiguration as? MainMenuContentConfiguration
    )
}

@MainActor
private func makeVisibleTestWindow(
    rootViewController: UIViewController,
    size: CGSize,
    semanticContentAttribute: UISemanticContentAttribute = .unspecified
) throws -> UIWindow {
    let windowScene = try #require(
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    )
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(origin: .zero, size: size)
    window.semanticContentAttribute = semanticContentAttribute
    window.rootViewController = rootViewController
    window.isHidden = false
    rootViewController.view.frame = window.bounds
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
private func waitForCondition(
    attempts: Int = 200,
    _ condition: () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func isHorizontalMirror(
    _ frame: CGRect,
    of originalFrame: CGRect,
    in containerWidth: CGFloat,
    tolerance: CGFloat = 1
) -> Bool {
    abs(frame.midX - (containerWidth - originalFrame.midX)) < tolerance
        && abs(frame.midY - originalFrame.midY) < tolerance
        && abs(frame.width - originalFrame.width) < tolerance
        && abs(frame.height - originalFrame.height) < tolerance
}

private func center(of view: UIView, in coordinateSpace: UIView) -> CGPoint {
    view.convert(
        CGPoint(x: view.bounds.midX, y: view.bounds.midY),
        to: coordinateSpace
    )
}

private extension CGPoint {
    func approximatelyEquals(
        _ other: CGPoint,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(x - other.x) < tolerance
            && abs(y - other.y) < tolerance
    }
}

private extension CGRect {
    func approximatelyEquals(
        _ other: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(minX - other.minX) < tolerance
            && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}

private extension String {
    /// Foundation may add Unicode bidi-isolation marks around formatted
    /// substitutions on newer SDKs. They are correct for rendering but should
    /// not make localized copy assertions SDK-dependent.
    var removingBidiIsolationMarks: String {
        replacingOccurrences(of: "\u{2066}", with: "")
            .replacingOccurrences(of: "\u{2067}", with: "")
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }
}

private extension UIView {
    func allSubviews<T: UIView>(of type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matches: [T] = []
            if let typed = subview as? T {
                matches.append(typed)
            }
            matches.append(contentsOf: subview.allSubviews(of: type))
            return matches
        }
    }
}

private final class EnvironmentRecordingQuickLayoutView: QuickLayoutView {

    var environmentChanges: [(environment: QuickLayoutEnvironment, reason: QuickLayoutEnvironmentChangeReason)] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
        environmentChanges.append((environment, reason))
    }
}

private final class TestSafeAreaScrollView: UIScrollView {

    var testSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        testSafeAreaInsets
    }
}

private final class RepresentableTestChildViewController: UIViewController {

    let name: String

    init(name: String) {
        self.name = name
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 180, height: 96)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        self.view = view
    }
}

@MainActor
private final class RecordingDemoRouter: DemoRouting {

    private(set) var routes: [DemoRoute] = []

    func navigate(
        to route: DemoRoute,
        from sourceViewController: UIViewController
    ) {
        routes.append(route)
    }
}
