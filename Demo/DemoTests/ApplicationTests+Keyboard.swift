import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension ApplicationTests {

    @Test func keyboardDiagnosticsDisplaysReceivedEventAndVisibilityIndependently() throws {
        let view = AnimatedKeyboardResponsiveView()
        #expect(view.diagnosticsLabel.text?.contains(Localization.text("keyboard.diagnostics.waiting")) == true)
        #expect(view.diagnosticsLabel.text?.contains("willHide") == false)

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let screen = try #require(scene).screen
        let bounds = screen.coordinateSpace.bounds
        let hidden = CGRect(x: bounds.minX, y: bounds.maxY, width: bounds.width, height: 264)
        let shown = hidden.offsetBy(dx: 0, dy: -hidden.height)

        func check(_ notification: Notification.Name, _ frame: CGRect, event: String, visible: Bool) {
            NotificationCenter.default.post(name: notification, object: screen, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ])
            let lines = view.diagnosticsLabel.text?.components(separatedBy: "\n") ?? []
            #expect(lines.contains(Localization.text("keyboard.diagnostics.event", event)))
            #expect(lines.contains(Localization.text(
                "keyboard.diagnostics.visible", Localization.text(visible ? "common.boolean.true" : "common.boolean.false")
            )))
        }

        check(UIResponder.keyboardDidChangeFrameNotification, shown, event: "didChangeFrame", visible: true)
        check(UIResponder.keyboardWillHideNotification, hidden, event: "willHide", visible: false)
        check(UIResponder.keyboardDidChangeFrameNotification, hidden, event: "didChangeFrame", visible: false)
    }

    /// 键盘通知同步触发布局时，不能重新读到 @Published 尚未写入的旧上下文。
    /// 同时检查 Core Animation 的中间位置，避免只验证最终布局而漏掉瞬移。
    @Test func keyboardSafeAreaAnimatesShowAndHideWithoutRevertingContext() async throws {
        // 同时触发 Demo 自己的诊断／滚动订阅，覆盖它清除宿主动画的回归。
        let center = NotificationCenter.default
        let view = KeyboardLayoutSafeAreaView()
        view.quickLayoutKeyboardSafeAreaBehavior = .disabled
        view.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, _ in true }
        view.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard()
        let controller = UIViewController()
        controller.view = view
        let window = try makeVisibleTestWindow(rootViewController: controller)
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer {
            window.isHidden = true
            UIView.setAnimationsEnabled(animationsWereEnabled)
        }
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        for showing in [true, false] {
            let startY = view.contentScrollView.layer.position.y
            let height: CGFloat = showing ? 220 : 0
            let frame = view.convert(
                CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height),
                to: nil
            )
            center.post(
                name: showing ? UIResponder.keyboardWillShowNotification : UIResponder.keyboardWillHideNotification,
                object: nil,
                userInfo: [
                    UIResponder.keyboardFrameEndUserInfoKey: frame,
                    UIResponder.keyboardAnimationDurationUserInfoKey: 0.5,
                    UIResponder.keyboardAnimationCurveUserInfoKey: UIView.AnimationCurve.linear.rawValue,
                ]
            )
            // 不额外手动布局：通知处理本身应当更新目标位置并开始动画。
            #expect(abs(view.quickLayoutKeyboardSafeAreaInsets.bottom - height) < 1)
            let endY = view.contentScrollView.layer.position.y
            #expect(abs(endY - startY) > 100)
            // Core Animation 提交首帧的时间受同进程其他测试影响；在动画时限内观察真实中间帧，
            // 仍要求位置严格位于起终点之间，瞬移不能通过此检查。
            #expect(await waitForCondition(attempts: 40) {
                guard let intermediate = view.contentScrollView.layer.presentation()?.position.y else { return false }
                return intermediate > min(startY, endY) + 1 && intermediate < max(startY, endY) - 1
            })
            try await Task.sleep(for: .milliseconds(500))
            #expect(abs(view.contentScrollView.layer.position.y - endY) < 1)
        }
    }

    @Test func keyboardAvoiderRecalculatesInsetsWhenContainerResizesWithoutNotification() {
        for scroll in [QuickLayoutScrollView(), UIScrollView()] as [UIScrollView] {
            scroll.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            scroll.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
            let avoider = QuickLayoutKeyboardAvoider(scrollView: scroll, notificationCenter: NotificationCenter())
            avoider.apply(QuickLayoutKeyboardContext(
                endFrame: CGRect(x: 0, y: 360, width: 320, height: 120),
                animationDuration: 0, animationOptions: [], isVisible: true
            ))
            #expect(scroll.contentInset.bottom == 130)
            for (height, expectedInset) in [(300.0, 10.0), (430.0, 80.0), (480.0, 130.0)] {
                scroll.frame.size.height = height
                scroll.setNeedsLayout()
                scroll.layoutIfNeeded()
                if !(scroll is QuickLayoutScrollView) { avoider.refreshGeometry() }
                #expect(abs(scroll.contentInset.bottom - expectedInset) < 1)
            }
            withExtendedLifetime(avoider) {}
        }
    }

    @Test func keyboardOnlyAvoidsDockedKeyboardAndReevaluatesGeometry() {
        let center = NotificationCenter()
        let view = KeyboardLayoutSafeAreaView(frame: CGRect(x: 0, y: 0, width: 640, height: 700))
        view.quickLayoutKeyboardSafeAreaBehavior = .disabled
        view.configureQuickLayoutKeyboardSafeAreaForTesting(notificationCenter: center) { _, _ in true }
        view.quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard()
        view.textField.text = "Preserved while resizing"

        func update(frame: CGRect) -> CGFloat {
            center.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ])
            view.setNeedsLayout()
            view.layoutIfNeeded()
            view.contentScrollView.layoutIfNeeded()
            view.contentScrollView.scrollTo(.bottom, animated: false)
            return view.submitButton.convert(view.submitButton.bounds, to: view).maxY
        }

        #expect(abs(update(frame: CGRect(x: 80, y: 300, width: 300, height: 220)) - 680) < 1)
        #expect(abs(update(frame: CGRect(x: 0, y: 480, width: 640, height: 220)) - 460) < 1)
        // 不发新通知，改变容器的底边：原键盘与新视口不再相交。
        view.frame.size = CGSize(width: 320, height: 400)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.contentScrollView.layoutIfNeeded()
        view.contentScrollView.scrollTo(.bottom, animated: false)
        #expect(abs(view.submitButton.convert(view.submitButton.bounds, to: view).maxY - 380) < 1)
        #expect(view.textField.text == "Preserved while resizing")
    }

    /// 分栏遮挡只应从实际所在的一侧扣除，旋转及窄窗口下控件继续填满可用宽度。
    @Test func keyboardLayoutUsesAsymmetricSafeArea() {
        let view = KeyboardLayoutSafeAreaView()
        let cases: [(CGSize, UIEdgeInsets)] = [
            (CGSize(width: 744, height: 1133), UIEdgeInsets(top: 100, left: 268, bottom: 20, right: 0)),
            (CGSize(width: 1133, height: 744), UIEdgeInsets(top: 100, left: 320, bottom: 20, right: 0)),
            (CGSize(width: 744, height: 1133), UIEdgeInsets(top: 100, left: 0, bottom: 20, right: 268)),
            (CGSize(width: 390, height: 844), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
            (CGSize(width: 852, height: 393), UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)),
        ]
        for (size, insets) in cases {
            view.frame = CGRect(origin: .zero, size: size)
            view.testSafeAreaInsets = insets
            view.safeAreaInsetsDidChange()
            for direction in [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
                view.applyLayoutDirection(direction)
                view.setNeedsLayout()
                view.layoutIfNeeded()
                view.contentScrollView.layoutIfNeeded()
                for control in [view.textField, view.submitButton, view.diagnosticsBackgroundView] {
                    let frame = control.convert(control.bounds, to: view)
                    #expect(abs(frame.minX - (insets.left + 20)) < 1)
                    #expect(abs(frame.maxX - (size.width - insets.right - 20)) < 1)
                }
                #expect(view.diagnosticsBackgroundView.frame.maxY < view.textField.frame.minY)
                #expect(view.textField.frame.maxY < view.submitButton.frame.minY)
                #expect(view.submitButton.convert(view.submitButton.bounds, to: view).maxY <= size.height - insets.bottom)
            }
        }
    }

    /// 验证隐藏及硬件键盘的空框架无需经过 UIKit 坐标转换。
    ///
    /// 先后使用横竖屏尺寸的零高度框架，覆盖旋转后仍保存上一屏幕几何信息的情况。
    /// 非空框架作为对照，确认转换计数能够观测正常的坐标转换路径。
    @Test func keyboardContextSkipsConversionForEmptyFrames() {
        let view = KeyboardConversionTrackingView(
            frame: CGRect(x: 0, y: 0, width: 951, height: 669)
        )
        let frames = [
            CGRect(x: 0, y: 951, width: 669, height: 0),
            CGRect(x: 0, y: 669, width: 951, height: 0),
            CGRect.zero,
        ]
        for frame in frames {
            for isVisible in [false, true] {
                let context = QuickLayoutKeyboardContext(
                    endFrame: frame,
                    animationDuration: 0,
                    animationOptions: [],
                    isVisible: isVisible
                )
                let resolved = context.resolved(in: view)
                #expect(resolved.keyboardFrameInView.isNull)
                #expect(resolved.intersection.isNull)
                #expect(resolved.height == 0)
                #expect(!resolved.isFloatingOrSplitKeyboard)
                #expect(resolved.isHardwareKeyboardLikely == isVisible)
            }
        }
        #expect(view.conversionCount == 0)

        let visible = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 400, width: 951, height: 269),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true
        ).resolved(in: view)
        #expect(view.conversionCount > 0)
        #expect(visible.height == 269)
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

    @Test(arguments: [true, false])
    func keyboardObserverStaysHiddenAfterFinalFrameChange(includesSourceScreen: Bool) throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let sceneScreen = try #require(scene).screen
        // 无来源屏幕的通知模拟旧系统的主屏幕坐标；Duo 的场景屏幕可能不同。
        let screen = includesSourceScreen ? sceneScreen : UIScreen.main
        let bounds = screen.coordinateSpace.bounds
        let center = NotificationCenter()
        let observer = QuickLayoutKeyboardObserver(notificationCenter: center)
        let hidden = CGRect(x: bounds.minX, y: bounds.maxY, width: bounds.width, height: 264)
        let shown = hidden.offsetBy(dx: 0, dy: -hidden.height)

        func post(_ name: Notification.Name, _ frame: CGRect) {
            center.post(name: name, object: includesSourceScreen ? screen : nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
            ])
        }

        post(UIResponder.keyboardWillShowNotification, shown)
        #expect(observer.isKeyboardVisible)
        post(UIResponder.keyboardDidChangeFrameNotification, hidden.offsetBy(dx: 0, dy: -1))
        #expect(observer.isKeyboardVisible)

        post(UIResponder.keyboardWillHideNotification, shown)
        #expect(observer.context.event == .willHide)
        #expect(!observer.isKeyboardVisible)
        post(UIResponder.keyboardWillChangeFrameNotification, hidden)
        #expect(!observer.isKeyboardVisible)
        post(UIResponder.keyboardDidChangeFrameNotification, hidden)
        #expect(observer.context.event == .didChangeFrame)
        #expect(observer.context.endFrame.height == 264)
        #expect(!observer.context.isVisible)
        #expect(!observer.isKeyboardVisible)
        #expect(observer.keyboardHeight == 0)

        post(UIResponder.keyboardDidChangeFrameNotification, shown)
        #expect(observer.isKeyboardVisible)
        #expect(observer.keyboardHeight == 264)
    }

    @Test func keyboardWillShowWithZeroHeightIsHiddenAndPreservesHardwareKeyboardHint() throws {
        let context = try #require(QuickLayoutKeyboardContext(notification: Notification(
            name: UIResponder.keyboardWillShowNotification,
            userInfo: [UIResponder.keyboardFrameEndUserInfoKey: CGRect.zero]
        )))
        #expect(!context.isVisible)
        #expect(context.resolved(in: UIView()).isHardwareKeyboardLikely)
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

        scrollView.testSafeAreaInsets.bottom = 20
        avoider.refreshGeometry()
        #expect(scrollView.contentInset.bottom == 118)

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
        avoider.refreshGeometry()
        #expect(scrollView.contentOffset.y == 0, "用户滚动不应重新定位仍处于编辑状态的输入框")
        notificationCenter.post(name: .quickLayoutKeyboardActiveInputDidEndEditing, object: activeInput)
        avoider.apply(visibleContext)

        #expect(scrollView.contentOffset.y == 0)
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
}

private final class KeyboardLayoutSafeAreaView: AnimatedKeyboardResponsiveView {
    var testSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets { testSafeAreaInsets }
}

private final class TestSafeAreaScrollView: UIScrollView {

    var testSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        testSafeAreaInsets
    }
}

/// 记录从其他视图坐标空间转换矩形的调用次数。
private final class KeyboardConversionTrackingView: UIView {
    /// 自创建以来观测到的矩形转换次数。
    var conversionCount = 0

    /// 记录转换后沿用 UIKit 的坐标转换结果。
    override func convert(_ rect: CGRect, from view: UIView?) -> CGRect {
        conversionCount += 1
        return super.convert(rect, from: view)
    }
}
