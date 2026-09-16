import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func safeAreaPaddingDemoCoversQuickLayoutCombinations() throws {
        Localization.setLocale(identifier: "en-US")
        defer { Localization.setLocale(identifier: "en-US") }

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
        let safeAreaGuideView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutShapeView.self)
                .first {
                    $0.accessibilityIdentifier == "safeAreaPadding.guide"
                }
        )
        let safeAreaGuideLayer = try #require(
            safeAreaGuideView.layer as? CAShapeLayer
        )
        let guidePathBounds = try #require(
            safeAreaGuideLayer.path?.boundingBoxOfPath
        )
        let expectedGuideBounds = safeAreaGuideView.bounds.inset(
            by: safeAreaGuideView.safeAreaInsets
        )
        #expect(guidePathBounds.approximatelyEquals(expectedGuideBounds))
        #expect(safeAreaGuideLayer.lineDashPattern?.map(\.intValue) == [6, 4])

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
        Localization.setLocale(identifier: "en-US")
        defer { Localization.setLocale(identifier: "en-US") }

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

    @Test func viewThatFitsDemoCoversSwiftUISelectionContract() throws {
        Localization.setLocale(identifier: "en-US")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = ViewThatFitsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        #expect(viewController.scenarioCount == 6)
        #expect(viewController.selectedCandidateIdentifier == "B")

        for scenario in ViewThatFitsDemoViewController.Scenario.allCases {
            viewController.selectScenario(at: scenario.rawValue)
            layout(viewController, in: navigationController)

            let expectedCandidate = try #require(
                scenario.expectedCandidate(for: scenario.proposedSize)
            )

            #expect(
                viewController.selectedCandidateIdentifier
                    == expectedCandidate.identifier
            )
            #expect(
                viewController.selectedCandidateSize
                    == expectedCandidate.size
            )
            #expect(
                viewController.expectedCandidateIdentifier
                    == expectedCandidate.identifier
            )
            #expect(
                viewController.expectedLabel.text
                    == Localization.text(
                        "viewThatFits.expected",
                        expectedCandidate.identifier
                    )
            )
            #expect(
                viewController.metricsLabel.text
                    == Localization.text(
                        "viewThatFits.selected",
                        expectedCandidate.identifier
                    )
            )
            #expect(
                viewController.previewView.bounds.size
                    == scenario.proposedSize
            )
        }

        viewController.selectScenario(
            at: ViewThatFitsDemoViewController.Scenario
                .defaultBothAxes.rawValue
        )
        viewController.setProposedSize(CGSize(width: 300, height: 140))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "A")
        #expect(viewController.expectedCandidateIdentifier == "A")
        #expect(
            viewController.expectedLabel.text
                == Localization.text("viewThatFits.expected", "A")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 260, height: 120)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 300, height: 140)
        )

        viewController.setProposedSize(CGSize(width: 200, height: 100))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "B")
        #expect(viewController.expectedCandidateIdentifier == "B")
        #expect(
            viewController.expectedLabel.text
                == Localization.text("viewThatFits.expected", "B")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 180, height: 90)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 200, height: 100)
        )

        viewController.setProposedSize(CGSize(width: 90, height: 50))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "C")
        #expect(viewController.expectedCandidateIdentifier == "C")
        #expect(
            viewController.expectedLabel.text
                == Localization.text("viewThatFits.expected", "C")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 100, height: 60)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 90, height: 50)
        )

        viewController.selectScenario(
            at: ViewThatFitsDemoViewController.Scenario
                .horizontalOnly.rawValue
        )
        viewController.setProposedSize(CGSize(width: 151, height: 200))
        layout(viewController, in: navigationController)
        #expect(viewController.expectedCandidateIdentifier == "B")
        #expect(viewController.selectedCandidateIdentifier == "B")
        #expect(
            viewController.expectedLabel.text
                == Localization.text("viewThatFits.expected", "B")
        )
        #expect(
            viewController.metricsLabel.text
                == Localization.text("viewThatFits.selected", "B")
        )
    }

    @Test func viewThatFitsDemoRemainsScrollableInLandscape() throws {
        let viewController = ViewThatFitsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let scrollView = viewController.pageScrollView
        #expect(scrollView.bounds.width > scrollView.bounds.height)
        #expect(scrollView.contentSize.height > scrollView.bounds.height)
        #expect(
            viewController.previewView.bounds.size
                == viewController.proposedSize
        )

        let maximumOffset = max(
            0,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumOffset),
            animated: false
        )
        scrollView.layoutIfNeeded()

        #expect(maximumOffset > 0)
        #expect(scrollView.contentOffset.y > 0)
    }

    @Test func positionAndZIndexDemoUsesPhysicalPointsAndLayerOrdering() throws {
        Localization.setLocale(identifier: "en-US")
        defer { Localization.setLocale(identifier: "en-US") }

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

    @Test func counterDemoFallsBackToVerticalActionsWhenNarrow() {
        Localization.setLocale(identifier: "en-US")
        defer { Localization.setLocale(identifier: "en-US") }
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
        let configuredContentView = ContentConfigurationView(
            configuration: .init(model: ContentConfigurationModel.mockData[0])
        )
        let configuredSize = configuredContentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        configuredContentView.frame = CGRect(origin: .zero, size: configuredSize)
        configuredContentView.layoutIfNeeded()

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

        #expect(configuredContentView.iconView.bounds.size == CGSize(width: 40, height: 40))
        #expect(fitRow.directionIconView.bounds.width <= 24)
        #expect(fitRow.directionIconView.bounds.height <= 24)
        #expect(abs(fittedRatio - iconRatio) < 0.01)
        #expect(fillRow.imageView.bounds.width >= 40)
        #expect(fillRow.imageView.bounds.height >= 40)
        #expect(abs(filledRatio - fillImageRatio) < 0.01)
    }
}

/// 在主 Actor 读取视图几何并转换测试坐标。
@MainActor
private func center(of view: UIView, in coordinateSpace: UIView) -> CGPoint {
    view.convert(
        CGPoint(x: view.bounds.midX, y: view.bounds.midY),
        to: coordinateSpace
    )
}
