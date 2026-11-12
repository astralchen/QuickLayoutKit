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

/// QuickLayout 宿主发布键盘安全区域的方式。
public enum QuickLayoutKeyboardSafeAreaBehavior: Equatable, Sendable {

    /// 不观察键盘，也不向布局层级发布键盘安全区域。
    case disabled

    /// 只跟随停靠在宿主底边的键盘。
    ///
    /// 浮动键盘、分离键盘以及未与宿主相交的键盘均按隐藏状态处理。
    /// `usesBottomSafeArea` 为 `true` 时，隐藏状态的键盘安全区域底边使用宿主的
    /// `safeAreaInsets.bottom`；为 `false` 时使用宿主底边。
    case followsDockedKeyboard(usesBottomSafeArea: Bool = true)
}

/// 针对具体视图解析后的键盘几何信息。
public struct QuickLayoutResolvedKeyboardContext: Equatable, Sendable {

    /// 转换到目标视图坐标空间中的键盘框架。
    ///
    /// 原始键盘框架为空或无法转换到目标视图时为 `.null`。
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
public struct QuickLayoutKeyboardContext: Equatable, @unchecked Sendable {

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

    /// 从 UIKit 通知创建时，表示键盘结束框架在来源屏幕上有可见面积。
    /// 特定视图受到的遮挡请读取 `resolved(in:).height`。
    public let isVisible: Bool

    // iOS 16.1 起键盘通知会在 object 中携带来源屏幕。保留引用可以避免把外接屏幕
    // 或其他屏幕上的键盘 frame 错误地转换到当前宿主；所有读取都发生在 MainActor。
    /// 键盘通知携带的来源屏幕，用于拒绝跨屏幕的错误坐标转换。
    private var sourceScreen: UIScreen?

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
        sourceScreen = nil
    }

    /// 根据 UIKit 键盘通知创建键盘上下文。
    ///
    /// - Parameter notification: `UIResponder` 发布的键盘通知。
    /// - Returns: 有效的键盘上下文；通知缺少键盘结束 frame 时返回 `nil`。
    @MainActor
    public init?(notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return nil
        }

        let beginFrame = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect ?? .zero
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        let options = curveValue.map { UIView.AnimationOptions(rawValue: $0 << 16) } ?? .curveEaseInOut
        let event = QuickLayoutKeyboardEvent(notificationName: notification.name)
        let screen = notification.object as? UIScreen
        // iOS 16.1 之前的键盘通知没有来源屏幕，使用主屏幕的坐标空间。
        let screenBounds = (screen ?? UIScreen.main).coordinateSpace.bounds
        let visible = event != .willHide && !screenBounds.intersection(endFrame).isEmpty

        self.init(
            beginFrame: beginFrame,
            endFrame: endFrame,
            animationDuration: duration,
            animationOptions: options,
            isVisible: visible,
            event: event
        )
        sourceScreen = screen
    }

    /// 针对目标视图解析键盘几何信息。
    ///
    /// UIKit 使用屏幕坐标报告键盘框架。该方法将框架转换到目标视图坐标空间并计算可见
    /// 相交区域，以正确处理浮动键盘、分离键盘、iPad 窗口以及在窗口中存在偏移的视图。
    /// 空键盘框架不参与坐标转换，解析后的框架和相交区域为 `.null`，有效高度为零；
    /// 可见状态下的零高度框架仍保留硬件键盘判定。
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
        let hardwareKeyboard = (isVisible || event == .willShow) && endFrame.height <= 0

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

    /// 将非空屏幕键盘矩形转换到视图空间。
    ///
    /// 空框架直接返回 `.null`。已知来源屏幕时，目标未挂载或来源不匹配也返回 `.null`。
    ///
    /// - Parameter view: 接收键盘几何信息的目标视图。
    /// - Returns: 转换后的键盘框架；不存在有效转换区域时返回 `.null`。
    @MainActor
    private func convertedEndFrame(in view: UIView) -> CGRect {
        // 键盘隐藏或使用硬件键盘时，通知可能携带零高度矩形。
        // 空矩形不构成有效遮挡区域，无需转换到目标视图坐标空间。
        guard !endFrame.isEmpty else { return .null }

        if let sourceScreen {
            guard
                let window = view.window,
                window.screen === sourceScreen
            else {
                return .null
            }
            return sourceScreen.coordinateSpace.convert(
                endFrame,
                to: view
            )
        }

        guard let window = view.window else {
            // 未挂载时 UIKit 把 nil 解释为根视图的内容坐标。键盘矩形相对视口，
            // 因此先补上根视图滚动产生的 bounds.origin。
            var root = view
            while let parent = root.superview { root = parent }
            return view.convert(endFrame.offsetBy(dx: root.bounds.minX, dy: root.bounds.minY), from: nil)
        }

        let frameInWindow = window.convert(endFrame, from: nil)
        return view.convert(frameInWindow, from: window)
    }
}

private extension QuickLayoutKeyboardEvent {
    /// 将 UIKit 键盘通知名称映射为事件，未识别名称使用 `.unknown`。
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

// MARK: - 键盘通知观察

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

    /// 持有通知订阅，随所属对象释放而取消。
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

// MARK: - 宿主键盘安全区域

/// 观察键盘并向普通宿主发布停靠键盘安全区域，停止时恢复布局指南配置。
@MainActor
final class QuickLayoutKeyboardSafeAreaCoordinator {

    /// 可注入的主线程停靠判定闭包，供确定性测试替换系统判定。
    typealias DockingResolver = @MainActor (
        QuickLayoutKeyboardContext,
        UIView
    ) -> Bool

    /// 需要发布键盘安全区域的弱引用宿主。
    private weak var hostView: QuickLayoutView?
    /// 提供最近键盘通知上下文的观察对象。
    private let observer: QuickLayoutKeyboardObserver
    /// 可选停靠判定覆盖；未设置时检查系统布局指南。
    private let dockingResolver: DockingResolver?
    /// 键盘上下文订阅，显式停止时释放。
    private var cancellable: AnyCancellable?
    /// @Published 在写入属性前发送新值；同步布局必须读取本次收到的上下文。
    private var latestContext: QuickLayoutKeyboardContext?
    private var transition: QuickLayoutKeyboardTransition?
    /// 启用前布局指南的非停靠键盘跟随配置，停止时恢复。
    private let previousFollowsUndockedKeyboard: Bool
    /// 启用前布局指南的底部安全区域配置；不支持该属性的系统为 `nil`。
    private let previousUsesBottomSafeArea: Bool?
    /// 保存已提交的策略，避免无窗口场景下 UIKit 的延迟读回导致重复写入指南。
    private var configuredUsesBottomSafeArea: Bool?
    /// 协调器是否已经停止，阻止延迟通知再次写入宿主。
    private var isStopped = false

    /// 保存布局指南原配置，启用停靠模式并订阅键盘上下文。
    init(
        hostView: QuickLayoutView,
        notificationCenter: NotificationCenter = .default,
        dockingResolver: DockingResolver? = nil
    ) {
        self.hostView = hostView
        self.dockingResolver = dockingResolver
        let keyboardLayoutGuide = hostView.keyboardLayoutGuide
        previousFollowsUndockedKeyboard =
            keyboardLayoutGuide.followsUndockedKeyboard
        keyboardLayoutGuide.followsUndockedKeyboard = false
        if #available(iOS 17.0, *) {
            previousUsesBottomSafeArea =
                keyboardLayoutGuide.usesBottomSafeArea
            // 隐藏时不使用底部安全区的宿主，指南本身也不能保留上一轮的 Home 指示器高度。
            if case let .followsDockedKeyboard(usesBottomSafeArea) = hostView.quickLayoutKeyboardSafeAreaBehavior {
                keyboardLayoutGuide.usesBottomSafeArea = usesBottomSafeArea
                configuredUsesBottomSafeArea = usesBottomSafeArea
            }
        } else {
            previousUsesBottomSafeArea = nil
        }
        observer = QuickLayoutKeyboardObserver(
            notificationCenter: notificationCenter
        )
        cancellable = observer.$context
            .dropFirst()
            .sink { [weak self] context in
                guard let self else { return }
                latestContext = context
                // 快速反向时 UIKit 可能先发送上一段的 didChangeFrame，再发送下一段 will。
                // 两次通知之间仍按进行中的过渡处理几何修正。
                if context.event != .didChangeFrame {
                    transition = QuickLayoutKeyboardTransition(context)
                }
                refresh()
                if self.hostView?.window != nil { self.hostView?.layoutIfNeeded() }
                // 键盘通知可能早于 UIKeyboardLayoutGuide 的最终 frame 更新。
                // 保证 guide 变化后的下一次布局会重新解析最后一个 context。
                self.hostView?.setNeedsLayout()
            }
    }

    /// 显式结束观察并恢复宿主原有的 keyboard layout guide 配置。
    ///
    /// UIKit 属性只能在 MainActor 上恢复，因此不能依赖 Swift 6 中非隔离的 `deinit`。
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        cancellable = nil
        guard let hostView else { return }
        hostView.keyboardLayoutGuide.followsUndockedKeyboard =
            previousFollowsUndockedKeyboard
        if #available(iOS 17.0, *),
            let previousUsesBottomSafeArea {
            hostView.keyboardLayoutGuide.usesBottomSafeArea =
                previousUsesBottomSafeArea
        }
    }

    /// 同一过渡内，布局指南即使比通知晚更新，也使用剩余动画时间。
    func refresh() {
        guard !isStopped, let hostView else { return }
        if #available(iOS 17.0, *),
           case let .followsDockedKeyboard(usesBottomSafeArea) = hostView.quickLayoutKeyboardSafeAreaBehavior,
           configuredUsesBottomSafeArea != usesBottomSafeArea {
            // 运行期间切换策略时同步指南，不能只在协调器初始化时设置。
            hostView.keyboardLayoutGuide.usesBottomSafeArea = usesBottomSafeArea
            configuredUsesBottomSafeArea = usesBottomSafeArea
        }
        let insets: UIEdgeInsets
        if let latestContext {
            let docked = dockingResolver?(latestContext, hostView)
                ?? (Self.dockedGuideHeight(in: hostView) != nil)
            insets = Self.insets(
                for: latestContext, behavior: hostView.quickLayoutKeyboardSafeAreaBehavior,
                in: hostView, isDocked: docked
            )
        } else {
            // 初次挂载或重新启用时，键盘可能已经停靠，UIKit 不必重发通知。
            var initial = Self.insets(
                for: .hidden, behavior: hostView.quickLayoutKeyboardSafeAreaBehavior, in: hostView
            )
            if let height = Self.dockedGuideHeight(in: hostView) { initial.bottom = height }
            insets = initial
        }
        hostView.applyQuickLayoutKeyboardSafeAreaInsets(insets, transition: transition)
    }

    /// 结合几何相交与可选停靠判定解析底部避让；隐藏时按策略保留底部安全区域。
    static func insets(
        for context: QuickLayoutKeyboardContext,
        behavior: QuickLayoutKeyboardSafeAreaBehavior,
        in view: UIView,
        isDocked dockedOverride: Bool? = nil
    ) -> UIEdgeInsets {
        guard case let .followsDockedKeyboard(usesBottomSafeArea) = behavior else {
            return .zero
        }

        let hiddenBottomInset = usesBottomSafeArea
            ? sanitizedKeyboardSafeAreaValue(view.safeAreaInsets.bottom)
            : 0
        let resolved = context.resolved(in: view)
        let isGeometricallyDocked = resolved.height > 0
            && !resolved.isFloatingOrSplitKeyboard
            && !resolved.isHardwareKeyboardLikely
            && abs(resolved.intersection.maxY - resolved.visibleBounds.maxY)
                <= 0.5
        let isDocked = isGeometricallyDocked
            && (dockedOverride ?? true)

        guard isDocked else {
            return UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: hiddenBottomInset,
                right: 0
            )
        }
        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: sanitizedKeyboardSafeAreaValue(resolved.height),
            right: 0
        )
    }

    /// 非停靠键盘不会使本宿主配置的 guide 向上扩展。
    private static func dockedGuideHeight(in view: UIView) -> CGFloat? {
        guard view.window != nil else { return nil }
        let frame = view.keyboardLayoutGuide.layoutFrame
        guard !frame.isEmpty, abs(frame.maxY - view.bounds.maxY) <= 0.5,
              frame.minY < view.bounds.maxY - view.safeAreaInsets.bottom - 0.5 else { return nil }
        return view.bounds.intersection(frame).height
    }
}

/// 记录通知的截止时间，避免下一轮布局重新开始一段完整动画。
struct QuickLayoutKeyboardTransition {
    let end: CFTimeInterval
    let curve: UIView.AnimationCurve

    init?(_ context: QuickLayoutKeyboardContext) {
        guard context.animationDuration > 0, context.event != .didChangeFrame else { return nil }
        end = CACurrentMediaTime() + context.animationDuration
        let rawCurve = Int((context.animationOptions.rawValue >> 16) & 7)
        curve = UIView.AnimationCurve(rawValue: rawCurve) ?? .easeInOut
    }
}

/// 将非有限值及负值归零，得到可发布的键盘边距。
private func sanitizedKeyboardSafeAreaValue(_ value: CGFloat) -> CGFloat {
    value.isFinite ? max(0, value) : 0
}

// MARK: - 滚动内容避让

/// 将键盘边距应用到滚动视图，并保持当前输入视图可见。
@MainActor
public final class QuickLayoutKeyboardAvoider {

    /// 当前键盘避让器对应的安全区域策略类型。
    public typealias SafeAreaStrategy = QuickLayoutKeyboardSafeAreaStrategy

    /// 需要调整边距的滚动视图弱引用。
    private weak var scrollView: UIScrollView?
    /// 提供最近键盘通知上下文的观察对象。
    private var observer: QuickLayoutKeyboardObserver?
    /// 持有通知订阅，随所属对象释放而取消。
    private var cancellables: Set<AnyCancellable> = []
    /// 当前需要保持可见的输入视图弱引用。
    private weak var activeView: UIView?
    private let insets: KeyboardScrollInsets
    private var latestContext = QuickLayoutKeyboardContext.hidden
    private var lastViewportSize: CGSize?
    private var lastObstruction: CGRect = .null
    private var isApplyingContext = false
    private var needsGeometryRefresh = false
    private var pendingContext: QuickLayoutKeyboardContext?

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
        // 一次只允许一个避让器拥有该视图的增量，普通 UIScrollView 也一样。
        if let previous = scrollView.keyboardScrollInsets {
            if let owner = previous.owner { owner.stop() }
            else { previous.restore(on: scrollView) }
        }
        self.scrollView = scrollView
        self.observer = observer
        insets = KeyboardScrollInsets(scrollView)
        insets.owner = self
        scrollView.keyboardScrollInsets = insets

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
                guard let self, let scrollView = self.scrollView,
                      let view = Self.activeView(from: notification),
                      view.isDescendant(of: scrollView) else { return }
                activeView = view
                scrollActiveViewIntoVisibleArea(animated: true)
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
                if endedView === activeView {
                    activeView = nil
                }
            }
            .store(in: &cancellables)
    }

    isolated deinit { stop() }

    /// 停止跟踪并移除本实例添加的键盘边距。可以重复调用。
    public func stop() {
        let view = scrollView
        scrollView = nil
        cancellables.removeAll()
        observer = nil
        activeView = nil
        if let view, view.keyboardScrollInsets === insets { insets.restore(on: view) }
    }

    /// 重新采集业务边距，保留已写入但未被调用方替换的键盘增量。
    public func captureCurrentInsetsAsBase() {
        guard let scrollView else { return }
        insets.capture(from: scrollView)
        if insets.delta > 0 { insets.write(insets.delta, to: scrollView) }
    }

    /// 立即应用指定的键盘上下文。
    ///
    /// - Parameter context: 要应用的键盘上下文。
    public func apply(_ context: QuickLayoutKeyboardContext) {
        apply(context, animated: true)
    }

    /// 容器尺寸或安全区改变后，按当前几何重新计算最近键盘事件的避让量。
    ///
    /// `QuickLayoutScrollView` 在布局结束时自动调用。普通 `UIScrollView` 的宿主应在
    /// `viewDidLayoutSubviews` / `layoutSubviews` 中调用；不需要伪造键盘通知。
    /// 单纯滚动不会触发重新避让，避免把用户的阅读位置拉回输入框。
    public func refreshGeometry() {
        guard let scrollView else { return }
        if isApplyingContext {
            needsGeometryRefresh = true
            return
        }
        let resolved = latestContext.resolved(in: scrollView)
        let obstruction = resolved.intersection.offsetBy(dx: -scrollView.bounds.minX, dy: -scrollView.bounds.minY)
        guard lastViewportSize != scrollView.bounds.size || lastObstruction != obstruction
                || abs(insetDelta(for: resolved, in: scrollView) - insets.delta) > 0.5 else { return }
        apply(latestContext, animated: false)
    }

    private func apply(_ context: QuickLayoutKeyboardContext, animated: Bool) {
        guard let scrollView else { return }
        if isApplyingContext {
            pendingContext = context
            return
        }
        isApplyingContext = true
        defer {
            isApplyingContext = false
            if let next = pendingContext {
                pendingContext = nil
                apply(next, animated: true)
            } else if needsGeometryRefresh {
                // 父宿主可能在这次边距更新内缩短视口，按新的交集再核算一次。
                needsGeometryRefresh = false
                refreshGeometry()
            }
        }
        latestContext = context
        let resolved = context.resolved(in: scrollView)
        let obstruction = resolved.intersection.offsetBy(dx: -scrollView.bounds.minX, dy: -scrollView.bounds.minY)
        let delta = insetDelta(for: resolved, in: scrollView)
        let changed = lastObstruction != obstruction || lastViewportSize != scrollView.bounds.size || delta != insets.delta
        lastObstruction = obstruction
        lastViewportSize = scrollView.bounds.size
        UIView.animate(
            withDuration: animated ? context.animationDuration : 0,
            delay: 0,
            options: context.animationOptions.union([.beginFromCurrentState, .allowUserInteraction]),
            animations: {
                self.insets.write(delta, to: scrollView)
                scrollView.superview?.layoutIfNeeded()
                // 在本次更新内定位。动画完成后，用户可能已经滚动或切换了焦点。
                if changed && resolved.height > 0 { self.scrollActiveViewIntoVisibleArea(animated: false) }
            }
        )
    }

    /// 设置需要保持可见的输入视图；传入 nil 清除当前目标。
    public func setActiveView(_ view: UIView?) {
        if let view, let scrollView, !view.isDescendant(of: scrollView) { return }
        activeView = view
    }

    /// 将输入视图移至视口内实际未被键盘覆盖的区域。
    public func scrollActiveViewIntoVisibleArea(animated: Bool) {
        guard let scrollView, let activeView else { return }
        guard activeView.isDescendant(of: scrollView) else {
            self.activeView = nil
            return
        }
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else { return }
        let target = activeView.convert(activeView.bounds, to: scrollView).insetBy(dx: 0, dy: -12)
        let bounds = scrollView.bounds
        let adjusted = scrollView.adjustedContentInset
        let top = bounds.minY + max(0, adjusted.top)
        let bottom = max(top, bounds.maxY - max(0, adjusted.bottom - insets.delta))
        let obstacle = latestContext.resolved(in: scrollView).intersection
        var bands = [top...bottom]
        if !obstacle.isEmpty, target.minX < obstacle.maxX, target.maxX > obstacle.minX {
            bands = []
            let above = min(bottom, obstacle.minY - extraBottomPadding)
            let below = max(top, obstacle.maxY + extraBottomPadding)
            if above > top { bands.append(top...above) }
            if below < bottom { bands.append(below...bottom) }
        }
        let current = scrollView.contentOffset
        let minY = -adjusted.top
        let maxY = max(minY, scrollView.contentSize.height - bounds.height + adjusted.bottom)
        var bestOffset = current.y
        var bestVisible: CGFloat = -1
        for band in bands {
            // 先最大化可见高度，再选移动最少且确实可达的一侧。
            let a = target.maxY - band.upperBound
            let b = target.minY - band.lowerBound
            let shift = min(max(0, min(a, b)), max(a, b))
            let offset = min(max(current.y + shift, minY), maxY)
            let moved = target.offsetBy(dx: 0, dy: current.y - offset)
            let visible = max(0, min(moved.maxY, band.upperBound) - max(moved.minY, band.lowerBound))
            if visible > bestVisible || (visible == bestVisible && abs(offset - current.y) < abs(bestOffset - current.y)) {
                bestOffset = offset
                bestVisible = visible
            }
        }
        if bestOffset != current.y {
            scrollView.setContentOffset(CGPoint(x: current.x, y: bestOffset), animated: animated)
        }
    }

    /// 有键盘相交时按安全区域策略计算高度并添加额外间距，无相交时返回零。
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

    /// 优先读取通知 `userInfo` 中的 `activeView`，否则尝试将通知对象作为视图。
    private static func activeView(from notification: Notification) -> UIView? {
        if let view = notification.userInfo?["activeView"] as? UIView {
            return view
        }
        return notification.object as? UIView
    }
}

/// 同时记录业务基线和本实例施加的增量；替换或延迟释放时依身份归还边距。
@MainActor
private final class KeyboardScrollInsets {
    weak var owner: QuickLayoutKeyboardAvoider?
    private(set) var delta: CGFloat = 0
    private var content = UIEdgeInsets.zero
    private var vertical = UIEdgeInsets.zero
    private var horizontal = UIEdgeInsets.zero

    init(_ view: UIScrollView) { capture(from: view) }

    func capture(from view: UIScrollView) {
        func base(_ actual: UIEdgeInsets, margin: UIEdgeInsets, previous: UIEdgeInsets) -> UIEdgeInsets {
            var value = actual.subtracting(margin)
            if abs(value.bottom - (previous.bottom + delta)) < 0.0001 { value.bottom = previous.bottom }
            return value
        }
        content = base(view.contentInset, margin: view.quickLayoutAppliedContentMarginInsets, previous: content)
        vertical = base(view.verticalScrollIndicatorInsets, margin: view.quickLayoutAppliedVerticalIndicatorMarginInsets, previous: vertical)
        horizontal = base(view.horizontalScrollIndicatorInsets, margin: view.quickLayoutAppliedHorizontalIndicatorMarginInsets, previous: horizontal)
    }

    func write(_ delta: CGFloat, to view: UIScrollView) {
        self.delta = delta
        // 键盘与 safeAreaInset 的遮挡取并集，再由同一边距状态写入剩余贡献。
        (view as? QuickLayoutScrollView)?.quickLayoutContentMarginState.updateSafeArea(
            on: view, keepsContentAtStart: false
        )
        let extra = UIEdgeInsets(top: 0, left: 0, bottom: delta, right: 0)
        view.contentInset = content.adding(view.quickLayoutAppliedContentMarginInsets).adding(extra)
        view.verticalScrollIndicatorInsets = vertical.adding(view.quickLayoutAppliedVerticalIndicatorMarginInsets).adding(extra)
        view.horizontalScrollIndicatorInsets = horizontal.adding(view.quickLayoutAppliedHorizontalIndicatorMarginInsets).adding(extra)
    }

    func restore(on view: UIScrollView) {
        capture(from: view)
        write(0, to: view)
        view.keyboardScrollInsets = nil
    }
}

private enum QuickLayoutKeyboardAssociatedKeys {
    nonisolated(unsafe) static var insets: UInt8 = 0
}

extension UIScrollView {
    fileprivate var keyboardScrollInsets: KeyboardScrollInsets? {
        get { objc_getAssociatedObject(self, &QuickLayoutKeyboardAssociatedKeys.insets) as? KeyboardScrollInsets }
        set { objc_setAssociatedObject(self, &QuickLayoutKeyboardAssociatedKeys.insets, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var quickLayoutKeyboardInsetDelta: CGFloat { keyboardScrollInsets?.delta ?? 0 }
    var quickLayoutKeyboardAvoider: QuickLayoutKeyboardAvoider? { keyboardScrollInsets?.owner }
}
