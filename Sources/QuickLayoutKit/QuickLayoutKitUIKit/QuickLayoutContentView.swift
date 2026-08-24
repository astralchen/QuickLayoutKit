import UIKit

/// 使用 QuickLayout 实现 UIKit 内容配置的基类。
///
/// 使用 `UIContentConfiguration` 渲染 QuickLayout 内容时，应创建该类型的子类。
/// 基类会在应用配置、测量、布局和附加视图前，从最近的公开复用容器恢复布局方向。
/// 该机制能够覆盖 UIKit 插入的中间配置宿主，而无需检查或修改其私有视图层级。
open class QuickLayoutContentView: QuickLayoutView, UIContentView {

    private var storedConfiguration: UIContentConfiguration

    /// 该内容视图表示的 UIKit 配置。
    ///
    /// 单元格更新配置状态时，UIKit 会写入该属性。每次赋值都会先恢复复用容器的布局方向，
    /// 再调用 ``applyContentConfiguration(_:)``。子类只需在这一边界验证具体配置类型，
    /// 从而保持与 UIKit 原生类型擦除 `UIContentView` 契约一致。
    public final var configuration: UIContentConfiguration {
        get {
            storedConfiguration
        }
        set {
            storedConfiguration = newValue
            synchronizeConfiguredDirectionIfNeeded()
            applyContentConfiguration(newValue)
        }
    }

    /// 使用 UIKit 内容配置创建 QuickLayout 内容视图。
    ///
    /// - Parameter configuration: 内容视图表示的初始配置。
    public init(configuration: UIContentConfiguration) {
        storedConfiguration = configuration
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior =
            .followEnclosingReusableView
    }

    @available(*, unavailable, message: "Use init(configuration:) instead.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 在子类完成初始化后应用当前配置。
    ///
    /// 子类配置完内部视图后，应在初始化方法末尾调用一次。此后为 `configuration` 赋值时，
    /// 会自动调用同一个可重写方法。
    public final func applyCurrentContentConfiguration() {
        synchronizeConfiguredDirectionIfNeeded()
        applyContentConfiguration(storedConfiguration)
    }

    /// 响应 `configuration` 的变化。
    ///
    /// 子类应验证具体配置类型、更新自身内容，然后调用 `super`。此处保留类型擦除参数，
    /// 以遵循 `UIContentView` 的契约，而不引入另一套泛型类型系统。默认实现会使
    /// QuickLayout 的测量和放置失效。
    ///
    /// - Parameter configuration: 当前的类型擦除内容配置。
    open func applyContentConfiguration(
        _ configuration: UIContentConfiguration
    ) {
        setNeedsQuickLayout()
    }

    @discardableResult
    private func synchronizeConfiguredDirectionIfNeeded() -> Bool {
        synchronizeQuickLayoutSemanticDirectionIfNeeded(
            for: self,
            behavior: quickLayoutSemanticDirectionBehavior
        )
    }
}
