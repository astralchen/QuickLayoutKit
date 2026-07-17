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
struct DemoTests {

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

    @Test func keyboardContextResolvesVisibleIntersectionInTargetView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
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

    @Test func keyboardContextResolvesHardwareAndNonOverlappingKeyboardsToZero() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
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
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        )
        let current = QuickLayoutEnvironment(
            layoutDirection: .rightToLeft,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 34, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        )

        let changes = current.changes(from: previous)

        #expect(changes == [.layoutDirection, .safeArea])
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
        #expect(DemoLocalization.currentLayoutDirection == .rightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func rootRebuildIsSkippedWhenPresentedControllerExists() {
        let leftToRightChange = LocalizationChange(previousLocale: .englishUS, currentLocale: .simplifiedChinese)
        let rightToLeftChange = LocalizationChange(previousLocale: .englishUS, currentLocale: .arabic)

        #expect(!DemoLocalization.shouldRebuildRootWindows(
            for: leftToRightChange,
            hasPresentedViewController: false
        ))
        #expect(DemoLocalization.shouldRebuildRootWindows(
            for: rightToLeftChange,
            hasPresentedViewController: false
        ))
        #expect(!DemoLocalization.shouldRebuildRootWindows(
            for: rightToLeftChange,
            hasPresentedViewController: true
        ))
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

        for key in ["main.title", "demo.localizationOverview.title", "demo.uikitLocalization.title", "demo.swiftUIBridge.title"] {
            let localizations = try #require(catalog.strings[key]?.localizations)
            #expect(localizations["en"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["zh-Hans"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
        }
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

    @Test func mainMenuReloadsRouteTitlesAfterLanguageChange() {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let buttonTitles = main.view.allSubviews(of: UIButton.self).compactMap { $0.configuration?.title ?? $0.title(for: .normal) }

        #expect(buttonTitles.contains("语言中心"))
        #expect(buttonTitles.contains("UIKit 本地化"))
        #expect(buttonTitles.contains("SwiftUI 桥接"))

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func mainMenuSectionHeadersFollowQuickLayoutDirection() throws {
        DemoLocalization.setLocale(identifier: "ar")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.reloadLayoutDirection(.rightToLeft)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let quickLayoutHeader = try #require(
            main.view.allSubviews(of: UILabel.self).first { $0.accessibilityIdentifier == "main.section.quicklayout" }
        )

        #expect(quickLayoutHeader.textAlignment == .natural)
        #expect(quickLayoutHeader.semanticContentAttribute == .unspecified)
        let rightToLeftFrame = quickLayoutHeader.convert(quickLayoutHeader.bounds, to: main.scrollView)
        #expect(rightToLeftFrame.maxX > main.scrollView.bounds.width - 48)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        #expect(quickLayoutHeader.text == "QuickLayout 示例")
        #expect(quickLayoutHeader.textAlignment == .natural)
        #expect(quickLayoutHeader.semanticContentAttribute == .unspecified)
        let leftToRightFrame = quickLayoutHeader.convert(quickLayoutHeader.bounds, to: main.scrollView)
        #expect(leftToRightFrame.minX < 48)
        #expect(leftToRightFrame.minX < rightToLeftFrame.minX)

        DemoLocalization.setLocale(identifier: "en-US")
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
