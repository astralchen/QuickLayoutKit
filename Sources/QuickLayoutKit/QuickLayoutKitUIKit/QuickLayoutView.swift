import UIKit
import QuickLayout

private final class QuickLayoutKeyboardSafeAreaDependencies {
    let notificationCenter: NotificationCenter
    let dockingResolver: QuickLayoutKeyboardSafeAreaCoordinator.DockingResolver?

    init(
        notificationCenter: NotificationCenter = .default,
        dockingResolver: QuickLayoutKeyboardSafeAreaCoordinator.DockingResolver? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.dockingResolver = dockingResolver
    }
}

/// 承载 QuickLayout 内容的可复用视图。
///
/// 需要将 QuickLayout 层级嵌入现有 UIKit 视图控制器、表格视图单元格、集合视图单元格
/// 或复用视图，并且不需要单独创建视图控制器子类时，使用 `QuickLayoutView`。
open class QuickLayoutView: UIView, HasBody, QuickLayoutUpdating, QuickLayoutEnvironmentUpdating {

    private var contentProvider: (() -> Layout)?
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    private var keyboardSafeAreaCoordinator:
        QuickLayoutKeyboardSafeAreaCoordinator?
    // 将 actor-isolated 测试闭包封装在具体引用类型内，避免它进入 open UIView
    // 的跨文件子类元数据；生产实例始终使用默认依赖。
    private var keyboardSafeAreaDependencies =
        QuickLayoutKeyboardSafeAreaDependencies()

    /// 宿主自动发布键盘安全区域的方式。
    ///
    /// 默认值为 ``QuickLayoutKeyboardSafeAreaBehavior/disabled``，不会改变已有宿主的
    /// 布局。启用后，布局可以使用 `safeAreaPadding` 消费 `.keyboard` 区域，或使用
    /// `ignoresSafeArea(.keyboard, edges:)` 选择性忽略它。
    open var quickLayoutKeyboardSafeAreaBehavior:
        QuickLayoutKeyboardSafeAreaBehavior = .disabled {
        didSet {
            guard quickLayoutKeyboardSafeAreaBehavior != oldValue else {
                return
            }
            updateKeyboardSafeAreaObservation()
        }
    }

    /// 当前向 QuickLayout 层级发布的物理键盘安全区域边距。
    public private(set) var quickLayoutKeyboardSafeAreaInsets:
        UIEdgeInsets = .zero

    /// 键盘上方可提前开始滚动收起手势的区域高度。
    ///
    /// 该值直接转发到宿主的 `UIKeyboardLayoutGuide.keyboardDismissPadding`，只调整
    /// `UIScrollView` 收起键盘手势的响应范围，不会改变 QuickLayout 发布的键盘安全区域
    /// 或添加视觉间距。默认值和负值处理与 UIKit 保持一致。
    @available(iOS 17.0, *)
    open var quickLayoutKeyboardDismissPadding: CGFloat {
        get { keyboardLayoutGuide.keyboardDismissPadding }
        set { keyboardLayoutGuide.keyboardDismissPadding = newValue }
    }

    /// 宿主水平尺寸弹性的显式覆盖值。
    ///
    /// 默认值 `nil` 表示从 `body` 推导尺寸弹性，从而保留宿主布局表达的尺寸语义。
    /// 仅当宿主本身需要针对其容器覆盖这些语义时，才应设置具体值。
    open var quickLayoutHorizontalFlexibility: Flexibility? {
        didSet {
            guard quickLayoutHorizontalFlexibility != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsQuickLayout()
            superview?.setNeedsLayout()
        }
    }

    /// 宿主垂直尺寸弹性的显式覆盖值。
    ///
    /// 默认值 `nil` 表示从 `body` 推导尺寸弹性，从而保留宿主布局表达的尺寸语义。
    /// 仅当宿主本身需要针对其容器覆盖这些语义时，才应设置具体值。
    open var quickLayoutVerticalFlexibility: Flexibility? {
        didSet {
            guard quickLayoutVerticalFlexibility != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsQuickLayout()
            superview?.setNeedsLayout()
        }
    }

    /// 宿主在附加、布局和测量时采用的语义方向策略。
    ///
    /// 默认值 `.preserve` 会保留局部播放或空间语义。对于可从层级中移除且重新附加时
    /// 必须恢复容器最新方向的应用内容宿主，应使用 `.followEnclosingContainer`。
    open var quickLayoutSemanticDirectionBehavior:
        QuickLayoutSemanticDirectionBehavior = .preserve {
        didSet {
            guard quickLayoutSemanticDirectionBehavior != oldValue else {
                return
            }
            synchronizeQuickLayoutSemanticDirectionIfNeeded(
                for: self,
                behavior: quickLayoutSemanticDirectionBehavior
            )
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 用于解析宿主布局方向的语义角色。
    ///
    /// 应用内切换语言时通常会直接更新该属性。属性变化会立即发布新的有效方向并使宿主内容
    /// 失效，而不等待后续特征或布局回调。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 创建不包含内容的宿主视图。
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    /// 从 Interface Builder 归档创建宿主视图。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    /// 创建以内联方式提供 QuickLayout 内容的宿主视图。
    ///
    /// - Parameter content: 返回宿主布局的构建器闭包。
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(frame: .zero)
        self.contentProvider = content
    }

    /// 视图承载的 QuickLayout 内容。
    ///
    /// 子类可以重写该属性以提供自定义布局。
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        keyboardSafeAreaCoordinator?.refresh()
        guard window != nil else { return }
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        quickLayoutEnvironmentState.update(self)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        keyboardSafeAreaCoordinator?.refresh()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    open override func layoutSubviews() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        super.layoutSubviews()
        keyboardSafeAreaCoordinator?.refresh()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(
                bounds.size,
                keyboardInsets: quickLayoutKeyboardSafeAreaInsets
            ) {
                _QuickLayoutViewImplementation.layoutSubviews(self)
            }
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        // 切换区域设置或布局方向后，自适应尺寸可能先于下一次布局执行，因此测量必须读取最新环境。
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        quickLayoutEnvironmentState.update(self)
        return withQuickLayoutManagedViewState {
            keyboardSafeAreaCoordinator?.refresh()
            return withQuickLayoutContainerSize(
                size,
                keyboardInsets: quickLayoutKeyboardSafeAreaInsets
            ) {
                _QuickLayoutViewImplementation.sizeThatFits(
                    self,
                    size: size
                ) ?? super.sizeThatFits(size)
            }
        }
    }

    open override func quick_flexibility(for axis: Axis) -> Flexibility {
        let explicitFlexibility: Flexibility? = switch axis {
        case .horizontal:
            quickLayoutHorizontalFlexibility
        case .vertical:
            quickLayoutVerticalFlexibility
        }

        return explicitFlexibility
            ?? _QuickLayoutViewImplementation.quick_flexibility(self, for: axis)
            ?? super.quick_flexibility(for: axis)
    }

    /// 将宿主布局标记为需要更新。
    ///
    /// 本地化内容发生变化但布局方向未改变时，应调用此方法，因为 UIKit 不会为应用自定义
    /// 区域设置发送通知。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 根据需要立即布局宿主 QuickLayout 内容。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// 返回最适合指定约束的尺寸。
    ///
    /// - Parameter size: 宿主内容可使用的最大尺寸。
    /// - Returns: 适合宿主布局的尺寸。
    open func sizeThatFits(in size: CGSize) -> CGSize {
        sizeThatFits(size)
    }

    /// 响应可能影响布局的 UIKit 环境变化。
    ///
    /// 默认实现会使宿主 QuickLayout 内容失效。子类可以重写该方法以同步其他状态。
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

    func applyQuickLayoutKeyboardSafeAreaInsets(
        _ insets: UIEdgeInsets,
        context: QuickLayoutKeyboardContext?
    ) {
        guard quickLayoutKeyboardSafeAreaInsets != insets else { return }
        quickLayoutKeyboardSafeAreaInsets = insets

        guard let context, context.animationDuration > 0, window != nil else {
            setNeedsQuickLayout()
            return
        }
        performLayoutUpdate(
            duration: context.animationDuration,
            options: context.animationOptions.union([
                .beginFromCurrentState,
                .allowUserInteraction,
            ])
        )
    }

    private func updateKeyboardSafeAreaObservation() {
        switch quickLayoutKeyboardSafeAreaBehavior {
        case .disabled:
            keyboardSafeAreaCoordinator?.stop()
            keyboardSafeAreaCoordinator = nil
            applyQuickLayoutKeyboardSafeAreaInsets(.zero, context: nil)
        case .docked:
            if keyboardSafeAreaCoordinator == nil {
                keyboardSafeAreaCoordinator =
                    QuickLayoutKeyboardSafeAreaCoordinator(
                        hostView: self,
                        notificationCenter:
                            keyboardSafeAreaDependencies.notificationCenter,
                        dockingResolver:
                            keyboardSafeAreaDependencies.dockingResolver
                    )
            } else {
                keyboardSafeAreaCoordinator?.refresh()
            }
        }
    }

    /// 替换键盘 safe-area 的事件源与 docked 判定器，仅供确定性测试使用。
    ///
    /// 必须在启用 ``quickLayoutKeyboardSafeAreaBehavior`` 前调用，测试仍通过公开行为属性
    /// 启停完整的宿主协调链路，而不是绕过宿主直接构造协调器。
    @_spi(Testing)
    public final func configureQuickLayoutKeyboardSafeAreaForTesting(
        notificationCenter: NotificationCenter,
        dockingResolver: @MainActor @escaping (
            QuickLayoutKeyboardContext,
            UIView
        ) -> Bool
    ) {
        precondition(
            quickLayoutKeyboardSafeAreaBehavior == .disabled,
            "Configure keyboard safe-area dependencies before enabling it."
        )
        keyboardSafeAreaDependencies =
            QuickLayoutKeyboardSafeAreaDependencies(
                notificationCenter: notificationCenter,
                dockingResolver: dockingResolver
            )
    }

}
