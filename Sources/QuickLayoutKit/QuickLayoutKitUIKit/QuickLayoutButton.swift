import UIKit
import QuickLayout

/// ``QuickLayoutButton`` 公开的操作语义角色。
///
/// 角色不会自动应用视觉样式。它会作为 ``QuickLayoutButtonState`` 的一部分发布，
/// 供应用自行决定适当的外观。
public enum QuickLayoutButtonRole: Equatable, Sendable {
    /// 删除数据或执行其他破坏性操作的角色。
    case destructive

    /// 取消当前操作的角色。
    case cancel
}

/// ``QuickLayoutButton`` 发布的交互状态快照。
public struct QuickLayoutButtonState: Equatable, Sendable {
    /// 指示当前指针或触摸是否正在按钮内部按压。
    public let isPressed: Bool

    /// 指示按钮当前是否可以执行操作。
    public let isEnabled: Bool

    /// 指示按钮是否处于选中状态。
    public let isSelected: Bool

    /// 操作的语义角色；未提供角色时为 `nil`。
    public let role: QuickLayoutButtonRole?

    /// 创建按钮状态快照。
    ///
    /// - Parameters:
    ///   - isPressed: 指示按钮是否正被按压。
    ///   - isEnabled: 指示按钮是否可以执行操作。
    ///   - isSelected: 指示按钮是否处于选中状态。
    ///   - role: 操作的语义角色；`nil` 表示没有 destructive 或 cancel 角色。
    public init(
        isPressed: Bool,
        isEnabled: Bool,
        isSelected: Bool,
        role: QuickLayoutButtonRole?
    ) {
        self.isPressed = isPressed
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.role = role
    }
}

/// 使用 QuickLayout 构建完整视觉层级的 UIKit 控件。
///
/// `QuickLayoutButton` 本身是一个 ``HasBody`` 宿主。应用可以通过布局构建器初始化方法
/// 提供标签，也可以创建子类并重写 ``body``。控件负责交互、辅助功能语义、测量和布局；
/// 所有视觉细节均由应用负责。
///
/// 控件不会提供默认内边距、前景色、背景、圆角、按压动画或禁用状态外观。应通过 ``body``
/// 和 ``stateUpdateHandler`` 提供这些内容。
@MainActor
open class QuickLayoutButton:
    UIControl,
    HasBody,
    QuickLayoutUpdating,
    QuickLayoutEnvironmentUpdating {

    /// 主控件事件触发时执行的操作。
    public typealias Action = @MainActor () -> Void

    /// 应用自有界面用于渲染控件状态的回调。
    public typealias StateUpdateHandler =
        @MainActor (QuickLayoutButtonState) -> Void

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    private var lastPublishedState: QuickLayoutButtonState?

    /// 控件发出 `primaryActionTriggered` 事件时执行的操作。
    public var action: Action

    /// 向 ``stateUpdateHandler`` 公开的操作语义角色。
    ///
    /// `nil` 表示不提供 destructive 或 cancel 语义，且不会产生任何隐式样式。
    open var role: QuickLayoutButtonRole? {
        didSet {
            guard role != oldValue else { return }
            publishButtonState()
        }
    }

    /// 控制按钮在附加、测量或布局时如何恢复语义方向。
    ///
    /// 默认行为与 ``QuickLayoutView`` 一致，会保留局部播放或空间语义。对于可能被移除并
    /// 重新附加的普通应用内容，应使用 `.followEnclosingContainer`。
    open var quickLayoutSemanticDirectionBehavior:
        QuickLayoutSemanticDirectionBehavior = .preserve {
        didSet {
            guard quickLayoutSemanticDirectionBehavior != oldValue else {
                return
            }
            synchronizeDirectionIfNeeded()
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 设置时立即接收初始状态，此后接收每个不同的状态。设置为 `nil` 时停止应用回调，
    /// 但不改变按钮自身的交互状态和生命周期。
    ///
    /// 该回调是框架为按压、禁用、选中和角色相关外观提供的唯一内置桥接。不要在按钮自身的
    /// 处理闭包中强引用按钮。
    public var stateUpdateHandler: StateUpdateHandler? {
        didSet {
            publishButtonState(force: true)
        }
    }

    /// 当前不可变的交互状态快照。
    public var buttonState: QuickLayoutButtonState {
        QuickLayoutButtonState(
            isPressed: isHighlighted,
            isEnabled: isEnabled,
            isSelected: isSelected,
            role: role
        )
    }

    /// 完全由应用提供的按钮视觉层级。
    ///
    /// 子类可以重写该属性。默认实现使用 ``init(role:action:label:)`` 提供的层级；
    /// 使用 `init(frame:)` 创建按钮时不渲染任何内容。
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    open override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                isHighlighted = false
            }
            updateAccessibilityTraits()
            publishButtonState()
        }
    }

    open override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            publishButtonState()
        }
    }

    open override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            publishButtonState()
        }
    }

    /// 创建用于子类化或后续配置的空按钮宿主。
    public override init(frame: CGRect) {
        action = {}
        role = nil
        super.init(frame: frame)
        configureControl()
    }

    /// 从 Interface Builder 归档创建空按钮宿主。
    ///
    /// 使用该初始化方法的子类应自行提供 ``body`` 并设置 ``action``。
    public required init?(coder: NSCoder) {
        action = {}
        role = nil
        super.init(coder: coder)
        configureControl()
    }

    /// 创建由子类提供视觉层级的按钮。
    ///
    /// - Parameters:
    ///   - role: 可选的操作语义角色；`nil` 表示没有语义角色。该值不会自动应用样式。
    ///   - action: 按钮的主要操作。
    public init(
        role: QuickLayoutButtonRole? = nil,
        action: @escaping Action
    ) {
        self.action = action
        self.role = role
        super.init(frame: .zero)
        configureControl()
    }

    /// 创建具有应用自有 QuickLayout 层级的按钮。
    ///
    /// - Parameters:
    ///   - role: 可选的操作语义角色；`nil` 表示没有语义角色。该值不会自动应用样式。
    ///   - action: 按钮的主要操作。
    ///   - label: 完整的视觉层级；框架不会隐式添加样式或内边距。
    public convenience init(
        role: QuickLayoutButtonRole? = nil,
        action: @escaping Action,
        @LayoutBuilder label: @escaping () -> Layout
    ) {
        self.init(role: role, action: action)
        contentProvider = label
    }

    /// 在按钮启用时发送主要操作。
    ///
    /// 已注册的 `primaryActionTriggered` 目标会通过标准 `UIControl` 事件路径收到通知。
    open func performAction() {
        guard isEnabled else { return }
        sendActions(for: .primaryActionTriggered)
    }

    open override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        performAction()
        return true
    }

    /// 即使应用提供的标签视图通常会接收触摸，也将交互保持在控件边界上。
    open override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        guard super.hitTest(point, with: event) != nil else { return nil }
        return self
    }

    open override func beginTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard isEnabled else { return false }
        isHighlighted = true
        sendActions(for: .touchDown)
        return true
    }

    open override func continueTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        guard isEnabled else { return false }

        let wasInside = isHighlighted
        let isInside = bounds.contains(touch.location(in: self))
        isHighlighted = isInside

        if isInside {
            sendActions(for: wasInside ? .touchDragInside : .touchDragEnter)
        } else {
            sendActions(for: wasInside ? .touchDragExit : .touchDragOutside)
        }
        return true
    }

    open override func endTracking(
        _ touch: UITouch?,
        with event: UIEvent?
    ) {
        let isInside = touch.map {
            bounds.contains($0.location(in: self))
        } ?? false
        isHighlighted = false

        if isEnabled && isInside {
            sendActions(for: .touchUpInside)
            performAction()
        } else {
            sendActions(for: .touchUpOutside)
        }
    }

    open override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
        sendActions(for: .touchCancel)
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        synchronizeDirectionIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .layoutMargins
        )
    }

    open override func layoutSubviews() {
        synchronizeDirectionIfNeeded()
        super.layoutSubviews()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(
            for: String(describing: Self.self),
            measuredSize: bounds.size
        )
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(bounds.size) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        synchronizeDirectionIfNeeded()
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(size) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                ) ?? super.sizeThatFits(size)
            }
        }
    }

    open override var intrinsicContentSize: CGSize {
        let measured = sizeThatFits(
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        return CGSize(
            width: intrinsicDimension(
                measured.width,
                flexibility: quick_flexibility(for: .horizontal)
            ),
            height: intrinsicDimension(
                measured.height,
                flexibility: quick_flexibility(for: .vertical)
            )
        )
    }

    open override func quick_flexibility(for axis: Axis) -> Flexibility {
        _QuickLayoutViewImplementation.quick_flexibility(self, for: axis)
            ?? super.quick_flexibility(for: axis)
    }

    /// 将 `body` 的测量和放置标记为需要更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    /// 根据需要立即布局控件。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// 响应不同的启用、选中、按压或角色状态。
    ///
    /// 子类可以重写该方法以更新应用自有界面。默认实现会调用 ``stateUpdateHandler``。
    ///
    /// - Parameter state: 按钮当前的交互状态快照。
    open func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        stateUpdateHandler?(state)
    }

    /// 响应可能影响 ``body`` 的 UIKit 环境变化。
    ///
    /// - Parameters:
    ///   - environment: 变化后的当前环境快照。
    ///   - reason: 描述发生变化部分的原因集合。
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private func configureControl() {
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)

        addAction(
            UIAction { [weak self] _ in
                self?.action()
            },
            for: .primaryActionTriggered
        )
        updateAccessibilityTraits()
    }

    private func synchronizeDirectionIfNeeded() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
    }

    private func updateAccessibilityTraits() {
        if isEnabled {
            accessibilityTraits.remove(.notEnabled)
        } else {
            accessibilityTraits.insert(.notEnabled)
        }
    }

    private func publishButtonState(force: Bool = false) {
        let state = buttonState
        guard force || state != lastPublishedState else { return }
        lastPublishedState = state
        quickLayoutButtonStateDidChange(state)
    }

    private func intrinsicDimension(
        _ measured: CGFloat,
        flexibility: Flexibility
    ) -> CGFloat {
        flexibility == .fullyFlexible
            ? UIView.noIntrinsicMetric
            : measured
    }
}
