import QuickLayout
import UIKit

/// 在 `UIVisualEffectView.contentView` 中承载 QuickLayout 内容的可复用视觉效果视图。
///
/// 使用模糊、材质或玻璃效果包装 QuickLayout 层级时，使用该类型。`body` 中提取的
/// UIKit 视图会自动安装到 ``UIVisualEffectView/contentView``，不会直接添加到视觉效果
/// 视图本身，从而保持 UIKit 要求的合成层级。
///
/// 该类型不提供默认效果或视觉样式。应用可以传入任意 `UIVisualEffect`，通过布局构建器
/// 初始化方法提供内容，也可以创建子类并重写 ``body``。
@MainActor
open class QuickLayoutVisualEffectView:
    UIVisualEffectView,
    HasBody,
    QuickLayoutUpdating,
    QuickLayoutEnvironmentUpdating {

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?
    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()

    /// 宿主水平尺寸弹性的显式覆盖值。
    ///
    /// 默认值 `nil` 表示从 ``body`` 推导水平尺寸弹性。
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
    /// 默认值 `nil` 表示从 ``body`` 推导垂直尺寸弹性。
    open var quickLayoutVerticalFlexibility: Flexibility? {
        didSet {
            guard quickLayoutVerticalFlexibility != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsQuickLayout()
            superview?.setNeedsLayout()
        }
    }

    /// 控制宿主在附加、测量或布局时如何恢复语义方向。
    ///
    /// 默认值 `.preserve` 保持 UIKit 的局部语义。需要跟随直接外层容器时，设置为
    /// `.followEnclosingContainer`。
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

    /// 视觉效果视图承载的 QuickLayout 内容。
    ///
    /// 默认实现使用布局构建器初始化方法提供的内容；通过 `init(effect:)` 创建时为空布局。
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    /// 记录上一次环境快照，并向宿主合并发布实际环境变化。
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    /// 创建不包含 QuickLayout 内容的视觉效果宿主。
    ///
    /// - Parameter effect: UIKit 视觉效果；`nil` 表示暂不应用效果。
    public override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
    }

    /// 从 Interface Builder 归档创建视觉效果宿主。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// 创建包含 QuickLayout 内容的视觉效果宿主。
    ///
    /// - Parameters:
    ///   - effect: UIKit 视觉效果；`nil` 表示暂不应用效果。
    ///   - content: 安装到 ``UIVisualEffectView/contentView`` 的 QuickLayout 层级。
    public convenience init(
        effect: UIVisualEffect? = nil,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(effect: effect)
        contentProvider = content
    }

    /// 在窗口归属变化前通知 QuickLayout 桥接层更新宿主。
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        _QuickLayoutViewImplementation.willMove(self, toWindow: newWindow)
    }

    /// 进入窗口后同步语义方向，并刷新效果宿主的环境快照。
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        synchronizeDirectionIfNeeded()
        quickLayoutEnvironmentState.update(self)
    }

    /// 将 UIKit 特征变化发布给宿主环境，触发依赖环境的内容更新。
    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .traitCollection
        )
    }

    /// 将安全区域变化发布给宿主环境。
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    /// 将布局边距变化发布给宿主环境。
    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(
            self,
            explicitReason: .layoutMargins
        )
    }

    /// 同步方向和环境后，在宿主状态与容器作用域中布局效果内容。
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

    /// 使用最新方向和环境测量效果内容，无法测量时使用父类结果。
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

    /// 优先采用显式轴弹性，否则从内容推导，最后回退到父类。
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

    /// 将宿主的 QuickLayout 内容标记为需要更新。
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// 根据需要立即布局视觉效果宿主。
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// 返回 QuickLayout 内容最适合指定约束的尺寸。
    ///
    /// - Parameter size: 内容可使用的最大尺寸。
    /// - Returns: QuickLayout 内容的适合尺寸。
    open func sizeThatFits(in size: CGSize) -> CGSize {
        sizeThatFits(size)
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

    /// 按效果宿主的语义策略同步容器方向。
    private func synchronizeDirectionIfNeeded() {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
    }
}
