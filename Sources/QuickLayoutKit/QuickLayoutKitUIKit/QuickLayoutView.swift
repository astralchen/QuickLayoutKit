import UIKit
import QuickLayout

/// 封装键盘事件源与可注入判定器，避免闭包进入开放视图子类元数据。
private final class QuickLayoutKeyboardSafeAreaDependencies {
    /// 键盘观察使用的通知中心，默认采用系统共享中心。
    let notificationCenter: NotificationCenter
    /// 可选的停靠判定器；未注入时采用系统判定。
    let dockingResolver: QuickLayoutKeyboardSafeAreaCoordinator.DockingResolver?

    /// 保存键盘依赖；生产实例使用默认通知中心及系统停靠判定。
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

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    /// 启用键盘安全区域时持有的协调器，禁用时显式停止并释放。
    private var keyboardSafeAreaCoordinator:
        QuickLayoutKeyboardSafeAreaCoordinator?
    /// 在真正写入子视图 frame 的布局轮次消费过渡，即使边距最先由测量阶段读到。
    private var hasExplicitKeyboardSafeAreaBehavior = false
    private var keyboardLayoutPending = false
    private var pendingKeyboardTransition: QuickLayoutKeyboardTransition?
    private var keyboardAnimator: UIViewPropertyAnimator?

    /// 用引用类型封装测试判定闭包，避免其进入 open UIView 的跨文件子类元数据。
    private var keyboardSafeAreaDependencies =
        QuickLayoutKeyboardSafeAreaDependencies()

    /// 上游先写 bounds、再写 center。位置确定后按最终边界重新投影父级安全区。
    open override var center: CGPoint {
        didSet {
            if center != oldValue { setNeedsLayout() }
        }
    }

    /// 宿主自动发布键盘安全区域的方式。
    ///
    /// 默认跟随停靠键盘，普通内容自动避让；使用 `ignoresSafeArea(.keyboard, edges:)`
    /// 选择性忽略。已有自定义键盘协调器的页面可以显式禁用。
    open var quickLayoutKeyboardSafeAreaBehavior:
        QuickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard(usesBottomSafeArea: false) {
        didSet {
            // 显式赋值即表示由调用方选择本宿主的键盘策略，即使值与默认值相同。
            hasExplicitKeyboardSafeAreaBehavior = true
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

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        QuickLayoutSafeAreaBodyBridge.willMove(self, toWindow: newWindow)
    }

    /// 刷新键盘状态，并在进入窗口后同步容器方向与环境。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        updateKeyboardSafeAreaObservation()
        guard window != nil else { return }
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 先刷新键盘安全区域，再发布宿主安全区域变化。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        keyboardSafeAreaCoordinator?.refresh()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
        // safeAreaPadding 会改变宿主的自然尺寸；只重排内部内容会使父级继续使用旧高度。
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    /// 同步方向、键盘与环境后，在状态和容器作用域中应用 `body` 布局。
    open override func layoutSubviews() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
        super.layoutSubviews()
        updateKeyboardSafeAreaObservation()
        quickLayoutEnvironmentState.update(self)
        QuickLayoutDiagnostics.recordLayoutPass(for: String(describing: Self.self), measuredSize: bounds.size)
        let transition = pendingKeyboardTransition
        let previous = keyboardLayoutPending ? keyboardAnimator : nil
        pendingKeyboardTransition = nil
        keyboardLayoutPending = false

        let interrupted = previous?.state == .active
        if interrupted {
            // 从当前呈现位置接续；移除旧轨迹后再写入新目标，避免两段位移相加。
            keyboardAnimator = nil
            previous?.stopAnimation(false)
            previous?.finishAnimation(at: .current)
        }
        let now = CACurrentMediaTime()
        if let transition, transition.end > now, window != nil, UIView.areAnimationsEnabled {
            let animator = UIViewPropertyAnimator(duration: transition.end - now,
                                                  curve: interrupted ? .easeOut : transition.curve) { [weak self] in
                self?.layoutQuickLayoutBody()
            }
            animator.isUserInteractionEnabled = true
            keyboardAnimator = animator
            animator.startAnimation()
        } else {
            layoutQuickLayoutBody()
        }
    }

    private func layoutQuickLayoutBody() {
        withQuickLayoutManagedViewState {
            withQuickLayoutContainerSize(
                bounds.size,
                keyboardInsets: quickLayoutKeyboardSafeAreaInsets
            ) {
                QuickLayoutSafeAreaBodyBridge.layoutSubviews(self)
            }
        }
    }

    /// 同步最新方向和键盘上下文后测量内容；无法获得 QuickLayout 尺寸时使用父类结果。
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
                QuickLayoutSafeAreaBodyBridge.sizeThatFits(
                    self,
                    size: size
                ) ?? super.sizeThatFits(size)
            }
        }
    }

    /// 优先使用显式轴弹性，否则从布局内容推导，最后回退到 UIKit 桥接默认值。
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

    /// 仅在键盘边距变化时更新宿主；有有效动画上下文且已挂载窗口时同步动画。
    func applyQuickLayoutKeyboardSafeAreaInsets(
        _ insets: UIEdgeInsets,
        transition: QuickLayoutKeyboardTransition?
    ) {
        if quickLayoutKeyboardSafeAreaInsets != insets {
            quickLayoutKeyboardSafeAreaInsets = insets
            keyboardLayoutPending = true
            pendingKeyboardTransition = transition
            setNeedsQuickLayout()
        } else if keyboardLayoutPending, let transition {
            // 同一目标可能先由零时长的 didChangeFrame 发布，再收到 will 通知。
            pendingKeyboardTransition = transition
        }
    }

    /// 根据启用策略创建或刷新协调器，禁用时恢复布局指南配置并清空发布边距。
    private func updateKeyboardSafeAreaObservation() {
        if !hasExplicitKeyboardSafeAreaBehavior {
            var ancestor = superview
            var inheritsKeyboardRegion = false
            while let current = ancestor {
                if current is QuickLayoutView || current is UIScrollView {
                    inheritsKeyboardRegion = true
                    break
                }
                ancestor = current.superview
            }
            // 默认仅由最外层宿主观察系统键盘，后代继承已消费的区域；原生滚动项目
            // 不能根据自己不断变化的可见位置再独立增加键盘高度。
            if window == nil || inheritsKeyboardRegion {
                keyboardSafeAreaCoordinator?.stop()
                keyboardSafeAreaCoordinator = nil
                applyQuickLayoutKeyboardSafeAreaInsets(.zero, transition: nil)
                return
            }
        }
        switch quickLayoutKeyboardSafeAreaBehavior {
        case .disabled:
            keyboardSafeAreaCoordinator?.stop()
            keyboardSafeAreaCoordinator = nil
            applyQuickLayoutKeyboardSafeAreaInsets(.zero, transition: nil)
        case .followsDockedKeyboard:
            if keyboardSafeAreaCoordinator == nil {
                keyboardSafeAreaCoordinator =
                    QuickLayoutKeyboardSafeAreaCoordinator(
                        hostView: self,
                        notificationCenter:
                            keyboardSafeAreaDependencies.notificationCenter,
                        dockingResolver:
                            keyboardSafeAreaDependencies.dockingResolver
                    )
            }
            keyboardSafeAreaCoordinator?.refresh()
        }
    }

    /// 替换键盘 safe-area 的事件源与 docked 判定器，仅供确定性测试使用。
    ///
    /// 替换时停止旧协调器并按当前策略重新订阅，支持默认已启用的宿主。
    /// 测试仍经过完整宿主协调链路，不直接修改安全区数值。
    @_spi(Testing)
    public final func configureQuickLayoutKeyboardSafeAreaForTesting(
        notificationCenter: NotificationCenter,
        dockingResolver: @MainActor @escaping (
            QuickLayoutKeyboardContext,
            UIView
        ) -> Bool
    ) {
        keyboardSafeAreaCoordinator?.stop()
        keyboardSafeAreaCoordinator = nil
        keyboardSafeAreaDependencies =
            QuickLayoutKeyboardSafeAreaDependencies(
                notificationCenter: notificationCenter,
                dockingResolver: dockingResolver
            )
        updateKeyboardSafeAreaObservation()
    }

}
