import Combine
import UIKit

/// The UIKit keyboard notification event represented by a context.
public enum QuickLayoutKeyboardEvent: Equatable, Sendable {
    case willShow
    case willHide
    case willChangeFrame
    case didChangeFrame
    case unknown
}

/// Controls how keyboard avoidance combines with the scroll view's safe area.
public enum QuickLayoutKeyboardSafeAreaStrategy: Equatable, Sendable {
    /// Use only the resolved keyboard intersection height.
    case ignore

    /// Add the scroll view's bottom safe area to the resolved keyboard height.
    case add

    /// Subtract the scroll view's existing bottom safe area from the resolved keyboard height.
    case subtractExisting
}

/// Keyboard geometry resolved for a concrete view.
public struct QuickLayoutResolvedKeyboardContext: Equatable, Sendable {

    /// The keyboard frame converted into the target view's coordinate space.
    public let keyboardFrameInView: CGRect

    /// The visible bounds used for intersection.
    public let visibleBounds: CGRect

    /// The intersection between the target visible bounds and keyboard frame.
    public let intersection: CGRect

    /// The effective visible keyboard height for the target view.
    public let height: CGFloat

    /// A Boolean value indicating whether the keyboard appears floating or split.
    public let isFloatingOrSplitKeyboard: Bool

    /// A Boolean value indicating whether this looks like an external hardware keyboard transition.
    public let isHardwareKeyboardLikely: Bool

    /// Creates resolved keyboard geometry.
    ///
    /// This initializer is useful for deterministic tests and for integrations
    /// that resolve keyboard geometry outside ``QuickLayoutKeyboardContext``.
    public init(
        keyboardFrameInView: CGRect,
        visibleBounds: CGRect,
        intersection: CGRect,
        height: CGFloat,
        isFloatingOrSplitKeyboard: Bool,
        isHardwareKeyboardLikely: Bool
    ) {
        self.keyboardFrameInView = keyboardFrameInView
        self.visibleBounds = visibleBounds
        self.intersection = intersection
        self.height = height
        self.isFloatingOrSplitKeyboard = isFloatingOrSplitKeyboard
        self.isHardwareKeyboardLikely = isHardwareKeyboardLikely
    }
}

public extension Notification.Name {

    /// Posted by custom input controls when editing begins.
    static let quickLayoutKeyboardActiveInputDidBeginEditing = Notification.Name(
        "QuickLayoutKeyboardActiveInputDidBeginEditing"
    )

    /// Posted by custom input controls when editing ends.
    static let quickLayoutKeyboardActiveInputDidEndEditing = Notification.Name(
        "QuickLayoutKeyboardActiveInputDidEndEditing"
    )
}

/// A parsed UIKit keyboard notification.
public struct QuickLayoutKeyboardContext: Equatable, Sendable {

    /// A discoverable spelling for keyboard events scoped to a context.
    public typealias Event = QuickLayoutKeyboardEvent

    /// A discoverable spelling for resolved geometry scoped to a context.
    public typealias Resolved = QuickLayoutResolvedKeyboardContext

    /// The keyboard frame at the beginning of the transition.
    public let beginFrame: CGRect

    /// The keyboard frame at the end of the transition.
    public let endFrame: CGRect

    /// The UIKit keyboard event that produced this context.
    public let event: QuickLayoutKeyboardEvent

    /// The keyboard animation duration.
    public let animationDuration: TimeInterval

    /// UIKit animation options matching the keyboard transition.
    public let animationOptions: UIView.AnimationOptions

    /// A Boolean value indicating whether the keyboard is visible.
    public let isVisible: Bool

    /// The effective keyboard height.
    ///
    /// Before the context has been resolved against a view, this falls back to
    /// UIKit's raw `endFrame.height` for compatibility.
    public var height: CGFloat {
        guard isVisible else { return 0 }
        return endFrame.height
    }

    /// Creates a context from explicit values.
    public init(
        beginFrame: CGRect = .zero,
        endFrame: CGRect,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions,
        isVisible: Bool,
        event: QuickLayoutKeyboardEvent = .unknown
    ) {
        self.beginFrame = beginFrame
        self.endFrame = endFrame
        self.event = event
        self.animationDuration = animationDuration
        self.animationOptions = animationOptions
        self.isVisible = isVisible
    }

    /// Creates a keyboard context from a UIKit keyboard notification.
    ///
    /// - Parameter notification: A keyboard notification from `UIResponder`.
    public init?(notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return nil
        }

        let beginFrame = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect ?? .zero
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        let options = curveValue.map { UIView.AnimationOptions(rawValue: $0 << 16) } ?? .curveEaseInOut
        let event = QuickLayoutKeyboardEvent(notificationName: notification.name)
        let visible = event != .willHide

        self.init(
            beginFrame: beginFrame,
            endFrame: endFrame,
            animationDuration: duration,
            animationOptions: options,
            isVisible: visible,
            event: event
        )
    }

    /// Resolves keyboard geometry for a target view.
    ///
    /// UIKit keyboard frames are reported in screen coordinates. This method
    /// converts the frame into the target view and measures the visible
    /// intersection, which is required for floating keyboards, split keyboards,
    /// iPad windows, and views that are offset inside a window.
    @MainActor
    public func resolved(in view: UIView) -> QuickLayoutResolvedKeyboardContext {
        let keyboardFrameInView = convertedEndFrame(in: view)
        let visibleBounds = view.bounds
        let intersects = isVisible && endFrame.height > 0 && !keyboardFrameInView.isEmpty
        let intersection = intersects ? visibleBounds.intersection(keyboardFrameInView) : .null
        let hasIntersection = !intersection.isNull && !intersection.isEmpty
        let height = hasIntersection ? intersection.height : 0
        let horizontalGap = keyboardFrameInView.minX > visibleBounds.minX + 0.5
            || keyboardFrameInView.maxX < visibleBounds.maxX - 0.5
        let floatsAboveBottom = keyboardFrameInView.maxY < visibleBounds.maxY - 0.5
        let floatingOrSplit = isVisible && hasIntersection && (horizontalGap || floatsAboveBottom)
        let hardwareKeyboard = isVisible && endFrame.height <= 0

        return QuickLayoutResolvedKeyboardContext(
            keyboardFrameInView: keyboardFrameInView,
            visibleBounds: visibleBounds,
            intersection: intersection,
            height: height,
            isFloatingOrSplitKeyboard: floatingOrSplit,
            isHardwareKeyboardLikely: hardwareKeyboard
        )
    }

    /// Resolves keyboard geometry for a scroll view.
    @MainActor
    public func resolved(in scrollView: UIScrollView) -> QuickLayoutResolvedKeyboardContext {
        resolved(in: scrollView as UIView)
    }

    /// An empty hidden-keyboard context.
    public static let hidden = QuickLayoutKeyboardContext(
        endFrame: .zero,
        animationDuration: 0.25,
        animationOptions: .curveEaseInOut,
        isVisible: false,
        event: .willHide
    )

    @MainActor
    private func convertedEndFrame(in view: UIView) -> CGRect {
        guard let window = view.window else {
            return view.convert(endFrame, from: nil)
        }

        let frameInWindow = window.convert(endFrame, from: nil)
        return view.convert(frameInWindow, from: window)
    }
}

private extension QuickLayoutKeyboardEvent {
    init(notificationName: Notification.Name) {
        switch notificationName {
        case UIResponder.keyboardWillShowNotification:
            self = .willShow
        case UIResponder.keyboardWillHideNotification:
            self = .willHide
        case UIResponder.keyboardWillChangeFrameNotification:
            self = .willChangeFrame
        case UIResponder.keyboardDidChangeFrameNotification:
            self = .didChangeFrame
        default:
            self = .unknown
        }
    }
}

/// Observes UIKit keyboard notifications and publishes parsed keyboard context.
@MainActor
public final class QuickLayoutKeyboardObserver: ObservableObject {

    /// The latest keyboard context.
    @Published public private(set) var context: QuickLayoutKeyboardContext = .hidden

    /// The latest keyboard height.
    public var keyboardHeight: CGFloat {
        context.height
    }

    /// A Boolean value indicating whether the keyboard is visible.
    public var isKeyboardVisible: Bool {
        context.isVisible
    }

    private var cancellables: Set<AnyCancellable> = []

    public init(notificationCenter: NotificationCenter = .default) {
        let notifications = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardDidChangeFrameNotification,
        ]

        for name in notifications {
            notificationCenter.publisher(for: name)
                .compactMap(QuickLayoutKeyboardContext.init(notification:))
                .sink { [weak self] context in
                    self?.context = context
                }
                .store(in: &cancellables)
        }
    }
}

/// Applies keyboard insets to a scroll view and keeps the active input visible.
@MainActor
public final class QuickLayoutKeyboardAvoider {

    /// A discoverable spelling for safe-area behavior scoped to the avoider.
    public typealias SafeAreaStrategy = QuickLayoutKeyboardSafeAreaStrategy

    private weak var scrollView: UIScrollView?
    private let observer: QuickLayoutKeyboardObserver
    private var cancellables: Set<AnyCancellable> = []
    private weak var activeView: UIView?
    private var keyboardInsetDelta: CGFloat = 0
    private var baseContentInset: UIEdgeInsets
    private var baseVerticalScrollIndicatorInsets: UIEdgeInsets
    private var baseHorizontalScrollIndicatorInsets: UIEdgeInsets

    /// Additional bottom spacing applied only while a keyboard intersects the scroll view.
    public var extraBottomPadding: CGFloat = 0

    /// Controls how resolved keyboard height combines with the scroll view safe area.
    public var safeAreaStrategy: SafeAreaStrategy = .ignore

    /// Creates a keyboard avoider that observes one notification center.
    ///
    /// The created keyboard observer and the active-input observation both use
    /// `notificationCenter`.
    ///
    /// - Parameters:
    ///   - scrollView: The scroll view whose insets should track the keyboard.
    ///   - notificationCenter: The center used for keyboard and editing
    ///     notifications.
    public convenience init(
        scrollView: UIScrollView,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: notificationCenter),
            notificationCenter: notificationCenter
        )
    }

    /// Creates a keyboard avoider with an explicit keyboard observer.
    ///
    /// - Parameters:
    ///   - scrollView: The scroll view whose insets should track the keyboard.
    ///   - observer: The keyboard observer to use.
    ///   - notificationCenter: The center used for editing notifications.
    public init(
        scrollView: UIScrollView,
        observer: QuickLayoutKeyboardObserver,
        notificationCenter: NotificationCenter = .default
    ) {
        self.scrollView = scrollView
        self.observer = observer
        self.baseContentInset = scrollView.contentInset
        self.baseVerticalScrollIndicatorInsets = scrollView.verticalScrollIndicatorInsets
        self.baseHorizontalScrollIndicatorInsets = scrollView.horizontalScrollIndicatorInsets

        observer.$context
            .sink { [weak self] context in
                self?.apply(context)
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            notificationCenter.publisher(for: UITextField.textDidBeginEditingNotification),
            notificationCenter.publisher(for: UITextView.textDidBeginEditingNotification),
            notificationCenter.publisher(for: .quickLayoutKeyboardActiveInputDidBeginEditing),
        ])
            .sink { [weak self] notification in
                self?.activeView = QuickLayoutKeyboardAvoider.activeView(from: notification)
                self?.scrollActiveViewIntoVisibleArea(animated: true)
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            notificationCenter.publisher(for: UITextField.textDidEndEditingNotification),
            notificationCenter.publisher(for: UITextView.textDidEndEditingNotification),
            notificationCenter.publisher(for: .quickLayoutKeyboardActiveInputDidEndEditing),
        ])
            .sink { [weak self] notification in
                guard let self else { return }
                let endedView = QuickLayoutKeyboardAvoider.activeView(from: notification)
                if endedView == nil || endedView === activeView {
                    activeView = nil
                }
            }
            .store(in: &cancellables)
    }

    /// Captures the scroll view's current insets as the base values that
    /// keyboard height should be added to.
    public func captureCurrentInsetsAsBase() {
        guard let scrollView else { return }
        baseContentInset = scrollView.contentInset
        baseVerticalScrollIndicatorInsets = scrollView.verticalScrollIndicatorInsets
        baseHorizontalScrollIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
    }

    /// Applies a keyboard context immediately.
    ///
    /// - Parameter context: The keyboard context to apply.
    public func apply(_ context: QuickLayoutKeyboardContext) {
        guard let scrollView else { return }

        let resolved = context.resolved(in: scrollView)
        let insetDelta = insetDelta(for: resolved, in: scrollView)
        keyboardInsetDelta = insetDelta

        var contentInset = baseContentInset
        var verticalIndicatorInsets = baseVerticalScrollIndicatorInsets
        var horizontalIndicatorInsets = baseHorizontalScrollIndicatorInsets

        contentInset.bottom = baseContentInset.bottom + insetDelta
        verticalIndicatorInsets.bottom = baseVerticalScrollIndicatorInsets.bottom + insetDelta
        horizontalIndicatorInsets.bottom = baseHorizontalScrollIndicatorInsets.bottom + insetDelta

        UIView.animate(
            withDuration: context.animationDuration,
            delay: 0,
            options: context.animationOptions,
            animations: {
                scrollView.contentInset = contentInset
                scrollView.verticalScrollIndicatorInsets = verticalIndicatorInsets
                scrollView.horizontalScrollIndicatorInsets = horizontalIndicatorInsets
                scrollView.superview?.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                self?.scrollActiveViewIntoVisibleArea(animated: resolved.height > 0)
            }
        )
    }

    /// Sets the view that should remain visible above the keyboard.
    ///
    /// - Parameter view: The active input or focus view.
    public func setActiveView(_ view: UIView?) {
        activeView = view
    }

    /// Scrolls the active view into the visible region.
    ///
    /// - Parameter animated: Pass `true` to animate the scroll.
    public func scrollActiveViewIntoVisibleArea(animated: Bool) {
        guard
            let scrollView,
            let activeView,
            activeView.window != nil || activeView.superview != nil
        else {
            return
        }

        let targetRect = activeView.convert(activeView.bounds, to: scrollView).insetBy(dx: 0, dy: -12)
        var visibleBounds = scrollView.bounds
        visibleBounds.size.height = max(0, visibleBounds.height - keyboardInsetDelta)

        var targetOffset = scrollView.contentOffset
        if targetRect.maxY > visibleBounds.maxY {
            targetOffset.y += targetRect.maxY - visibleBounds.maxY
        }
        if targetRect.minY < visibleBounds.minY {
            targetOffset.y -= visibleBounds.minY - targetRect.minY
        }

        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(
            minY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        targetOffset.y = min(max(targetOffset.y, minY), maxY)
        scrollView.setContentOffset(targetOffset, animated: animated)
    }

    private func insetDelta(
        for resolved: QuickLayoutResolvedKeyboardContext,
        in scrollView: UIScrollView
    ) -> CGFloat {
        guard resolved.height > 0 else { return 0 }

        let safeAreaBottom = scrollView.safeAreaInsets.bottom
        let keyboardHeight: CGFloat
        switch safeAreaStrategy {
        case .ignore:
            keyboardHeight = resolved.height
        case .add:
            keyboardHeight = resolved.height + safeAreaBottom
        case .subtractExisting:
            keyboardHeight = max(0, resolved.height - safeAreaBottom)
        }

        return keyboardHeight + extraBottomPadding
    }

    private static func activeView(from notification: Notification) -> UIView? {
        if let view = notification.userInfo?["activeView"] as? UIView {
            return view
        }
        return notification.object as? UIView
    }
}
