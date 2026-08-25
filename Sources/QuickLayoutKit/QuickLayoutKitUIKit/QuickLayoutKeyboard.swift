import Combine
import ObjectiveC
import UIKit

/// 上下文所表示的 UIKit 键盘通知事件。
public enum QuickLayoutKeyboardEvent: Equatable, Sendable {
    /// 键盘即将显示。
    case willShow

    /// 键盘即将隐藏。
    case willHide

    /// 键盘框架即将变化。
    case willChangeFrame

    /// 键盘框架已经变化。
    case didChangeFrame

    /// 无法识别的键盘事件。
    case unknown
}

/// 控制键盘避让值与滚动视图安全区域的组合方式。
public enum QuickLayoutKeyboardSafeAreaStrategy: Equatable, Sendable {
    /// 仅使用解析后的键盘相交高度。
    case ignore

    /// 将滚动视图底部安全区域添加到解析后的键盘高度。
    case add

    /// 从解析后的键盘高度中减去滚动视图现有的底部安全区域。
    case subtractExisting
}

/// 针对具体视图解析后的键盘几何信息。
public struct QuickLayoutResolvedKeyboardContext: Equatable, Sendable {

    /// 转换到目标视图坐标空间中的键盘框架。
    public let keyboardFrameInView: CGRect

    /// 用于计算相交区域的可见边界。
    public let visibleBounds: CGRect

    /// 目标可见边界与键盘框架的相交区域。
    public let intersection: CGRect

    /// 键盘在目标视图中的有效可见高度。
    public let height: CGFloat

    /// 指示键盘是否呈现为浮动或分离状态的布尔值。
    public let isFloatingOrSplitKeyboard: Bool

    /// 指示当前变化是否类似外接硬件键盘切换的布尔值。
    public let isHardwareKeyboardLikely: Bool

    /// 创建解析后的键盘几何信息。
    ///
    /// 该初始化方法适用于确定性测试，也适用于在 ``QuickLayoutKeyboardContext`` 之外
    /// 解析键盘几何信息的集成场景。
    ///
    /// - Parameters:
    ///   - keyboardFrameInView: 目标视图坐标空间中的键盘框架。
    ///   - visibleBounds: 用于计算相交区域的可见边界。
    ///   - intersection: 可见边界与键盘框架的相交区域。
    ///   - height: 键盘的有效可见高度。
    ///   - isFloatingOrSplitKeyboard: 键盘是否为浮动或分离状态。
    ///   - isHardwareKeyboardLikely: 当前变化是否可能由硬件键盘导致。
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

    /// 自定义输入控件开始编辑时发布的通知。
    static let quickLayoutKeyboardActiveInputDidBeginEditing = Notification.Name(
        "QuickLayoutKeyboardActiveInputDidBeginEditing"
    )

    /// 自定义输入控件结束编辑时发布的通知。
    static let quickLayoutKeyboardActiveInputDidEndEditing = Notification.Name(
        "QuickLayoutKeyboardActiveInputDidEndEditing"
    )
}

/// 解析后的 UIKit 键盘通知。
public struct QuickLayoutKeyboardContext: Equatable, Sendable {

    /// 当前上下文对应的键盘事件类型。
    public typealias Event = QuickLayoutKeyboardEvent

    /// 当前上下文对应的解析后几何信息类型。
    public typealias Resolved = QuickLayoutResolvedKeyboardContext

    /// 键盘变化开始时的框架。
    public let beginFrame: CGRect

    /// 键盘变化结束时的框架。
    public let endFrame: CGRect

    /// 生成该上下文的 UIKit 键盘事件。
    public let event: QuickLayoutKeyboardEvent

    /// 键盘动画持续时间。
    public let animationDuration: TimeInterval

    /// 与键盘变化匹配的 UIKit 动画选项。
    public let animationOptions: UIView.AnimationOptions

    /// 指示键盘是否可见的布尔值。
    public let isVisible: Bool

    /// 键盘的有效高度。
    ///
    /// 上下文尚未针对具体视图解析时，为保持兼容，该值使用 UIKit 原始的
    /// `endFrame.height`。
    public var height: CGFloat {
        guard isVisible else { return 0 }
        return endFrame.height
    }

    /// 使用明确提供的值创建键盘上下文。
    ///
    /// - Parameters:
    ///   - beginFrame: 键盘变化开始时的框架。
    ///   - endFrame: 键盘变化结束时的框架。
    ///   - animationDuration: 键盘动画持续时间。
    ///   - animationOptions: 与键盘变化匹配的动画选项。
    ///   - isVisible: 指示键盘是否可见。
    ///   - event: 生成上下文的键盘事件。
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

    /// 根据 UIKit 键盘通知创建键盘上下文。
    ///
    /// - Parameter notification: `UIResponder` 发布的键盘通知。
    /// - Returns: 有效的键盘上下文；通知缺少键盘结束 frame 时返回 `nil`。
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

    /// 针对目标视图解析键盘几何信息。
    ///
    /// UIKit 使用屏幕坐标报告键盘框架。该方法将框架转换到目标视图坐标空间并计算可见
    /// 相交区域，以正确处理浮动键盘、分离键盘、iPad 窗口以及在窗口中存在偏移的视图。
    ///
    /// - Parameter view: 用于解析键盘几何信息的目标视图。
    /// - Returns: 针对目标视图解析后的键盘几何信息。
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

    /// 针对滚动视图解析键盘几何信息。
    ///
    /// - Parameter scrollView: 用于解析键盘几何信息的滚动视图。
    /// - Returns: 针对滚动视图解析后的键盘几何信息。
    @MainActor
    public func resolved(in scrollView: UIScrollView) -> QuickLayoutResolvedKeyboardContext {
        resolved(in: scrollView as UIView)
    }

    /// 表示键盘隐藏状态的空上下文。
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

/// 观察 UIKit 键盘通知并发布解析后的键盘上下文。
@MainActor
public final class QuickLayoutKeyboardObserver: ObservableObject {

    /// 最近一次接收到的键盘上下文。
    @Published public private(set) var context: QuickLayoutKeyboardContext = .hidden

    /// 最近一次接收到的键盘高度。
    public var keyboardHeight: CGFloat {
        context.height
    }

    /// 指示键盘是否可见的布尔值。
    public var isKeyboardVisible: Bool {
        context.isVisible
    }

    private var cancellables: Set<AnyCancellable> = []

    /// 创建并开始观察键盘通知的对象。
    ///
    /// - Parameter notificationCenter: 发布 UIKit 键盘通知的通知中心。
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

/// 将键盘边距应用到滚动视图，并保持当前输入视图可见。
@MainActor
public final class QuickLayoutKeyboardAvoider {

    /// 当前键盘避让器对应的安全区域策略类型。
    public typealias SafeAreaStrategy = QuickLayoutKeyboardSafeAreaStrategy

    private weak var scrollView: UIScrollView?
    private let observer: QuickLayoutKeyboardObserver
    private var cancellables: Set<AnyCancellable> = []
    private weak var activeView: UIView?
    private var keyboardInsetDelta: CGFloat = 0
    private var baseContentInset: UIEdgeInsets
    private var baseVerticalScrollIndicatorInsets: UIEdgeInsets
    private var baseHorizontalScrollIndicatorInsets: UIEdgeInsets

    /// 仅在键盘与滚动视图相交时应用的额外底部间距。
    public var extraBottomPadding: CGFloat = 0

    /// 控制解析后的键盘高度与滚动视图安全区域的组合方式。
    public var safeAreaStrategy: SafeAreaStrategy = .ignore

    /// 创建观察指定通知中心的键盘避让器。
    ///
    /// 创建的键盘观察器和当前输入视图观察均使用 `notificationCenter`。
    ///
    /// - Parameters:
    ///   - scrollView: 边距需要跟随键盘变化的滚动视图。
    ///   - notificationCenter: 用于接收键盘和编辑通知的通知中心。
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

    /// 使用指定键盘观察器创建键盘避让器。
    ///
    /// - Parameters:
    ///   - scrollView: 边距需要跟随键盘变化的滚动视图。
    ///   - observer: 使用的键盘观察器。
    ///   - notificationCenter: 用于接收编辑通知的通知中心。
    public init(
        scrollView: UIScrollView,
        observer: QuickLayoutKeyboardObserver,
        notificationCenter: NotificationCenter = .default
    ) {
        self.scrollView = scrollView
        self.observer = observer
        self.baseContentInset = scrollView.contentInset
            .subtracting(scrollView.quickLayoutAppliedContentMarginInsets)
        self.baseVerticalScrollIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            .subtracting(scrollView.quickLayoutAppliedIndicatorMarginInsets)
        self.baseHorizontalScrollIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
            .subtracting(scrollView.quickLayoutAppliedIndicatorMarginInsets)

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

    /// 将滚动视图当前边距保存为添加键盘高度时使用的基准值。
    public func captureCurrentInsetsAsBase() {
        guard let scrollView else { return }
        baseContentInset = scrollView.contentInset
            .subtracting(scrollView.quickLayoutAppliedContentMarginInsets)
        baseVerticalScrollIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            .subtracting(scrollView.quickLayoutAppliedIndicatorMarginInsets)
        baseHorizontalScrollIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
            .subtracting(scrollView.quickLayoutAppliedIndicatorMarginInsets)
    }

    /// 立即应用指定的键盘上下文。
    ///
    /// - Parameter context: 要应用的键盘上下文。
    public func apply(_ context: QuickLayoutKeyboardContext) {
        guard let scrollView else { return }

        let resolved = context.resolved(in: scrollView)
        let insetDelta = insetDelta(for: resolved, in: scrollView)
        keyboardInsetDelta = insetDelta
        scrollView.quickLayoutKeyboardInsetDelta = insetDelta

        var contentInset = baseContentInset
            .adding(scrollView.quickLayoutAppliedContentMarginInsets)
        var verticalIndicatorInsets = baseVerticalScrollIndicatorInsets
            .adding(scrollView.quickLayoutAppliedIndicatorMarginInsets)
        var horizontalIndicatorInsets = baseHorizontalScrollIndicatorInsets
            .adding(scrollView.quickLayoutAppliedIndicatorMarginInsets)

        contentInset.bottom += insetDelta
        verticalIndicatorInsets.bottom += insetDelta
        horizontalIndicatorInsets.bottom += insetDelta

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

    /// 设置需要保持在键盘上方可见的视图。
    ///
    /// - Parameter view: 当前输入视图或焦点视图；传入 `nil` 表示清除当前目标。
    public func setActiveView(_ view: UIView?) {
        activeView = view
    }

    /// 将当前输入视图滚动到可见区域。
    ///
    /// - Parameter animated: 传入 `true` 以动画方式执行滚动。
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

private enum QuickLayoutKeyboardAssociatedKeys {
    nonisolated(unsafe) static var insetDelta: UInt8 = 0
}

extension UIScrollView {

    var quickLayoutKeyboardInsetDelta: CGFloat {
        get {
            (objc_getAssociatedObject(
                self,
                &QuickLayoutKeyboardAssociatedKeys.insetDelta
            ) as? NSNumber)?.doubleValue ?? 0
        }
        set {
            objc_setAssociatedObject(
                self,
                &QuickLayoutKeyboardAssociatedKeys.insetDelta,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
