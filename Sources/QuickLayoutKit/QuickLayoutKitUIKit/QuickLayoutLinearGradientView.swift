import QuartzCore
import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 描述渐变颜色及其位置的值类型。
///
/// API 对照 SwiftUI `Gradient`：调用方可以直接提供颜色，让组件生成均匀分布的停靠点，
/// 也可以通过 ``Stop`` 精确控制每种颜色的位置。该类型只描述渐变内容，不负责渲染。
public struct QuickLayoutGradient: Equatable {

    /// 渐变中的一个颜色停靠点。
    public struct Stop: Equatable {
        /// 停靠点颜色，支持动态 `UIColor`。
        public var color: UIColor

        /// 停靠点在渐变轴上的位置，通常位于 `0...1`。
        public var location: CGFloat

        /// 创建颜色停靠点。
        public init(color: UIColor, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    /// 当前渐变包含的颜色停靠点。
    public var stops: [Stop]

    /// 使用精确的颜色停靠点创建渐变。
    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// 使用均匀分布的颜色创建渐变。
    ///
    /// 单个颜色位于 `0`；两个及以上颜色覆盖完整的 `0...1` 渐变轴。
    public init(colors: [UIColor]) {
        guard colors.count > 1 else {
            stops = colors.map { Stop(color: $0, location: 0) }
            return
        }
        let denominator = CGFloat(colors.count - 1)
        stops = colors.enumerated().map { index, color in
            Stop(color: color, location: CGFloat(index) / denominator)
        }
    }
}

/// 使用 `CAGradientLayer` 作为根图层的线性渐变视图。
///
/// API 对照 SwiftUI `LinearGradient`，将渐变内容和单位坐标中的起止点作为独立输入。
/// 视图尺寸变化时，UIKit 会自动调整根图层，因此调用方不需要在 `layoutSubviews()` 中
/// 手动同步渐变图层的 frame。``gradient`` 中的动态颜色也会在界面样式变化后重新解析。
/// 类保持开放以支持组合专用视图；受管理的渐变状态可公开读写，但不允许子类覆写同步逻辑。
@MainActor
open class QuickLayoutLinearGradientView: UIView {

    /// 让视图的根图层直接承载渐变，避免额外子图层及其尺寸同步逻辑。
    public override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    /// 框架内部使用的类型化根图层访问入口。
    ///
    /// 不对外暴露，避免调用方直接修改图层后与 `gradient`、`startPoint`、`endPoint`
    /// 形成两套状态源。外部确有 Core Animation 定制需求时，仍可自行检查 UIView 的
    /// `layer`，但该用法不属于组件保证兼容性的公共 API。
    internal final var gradientLayer: CAGradientLayer {
        guard let gradientLayer = layer as? CAGradientLayer else {
            preconditionFailure("QuickLayoutLinearGradientView 的根图层必须是 CAGradientLayer")
        }
        return gradientLayer
    }

    /// 当前渐变内容。
    ///
    /// 建议通过该属性而不是直接修改 `gradientLayer.colors`，以保留停靠点一致性和动态颜色
    /// 在深色模式、浅色模式及高对比度环境变化时的自动更新能力。
    public var gradient: QuickLayoutGradient {
        didSet {
            updateGradient()
        }
    }

    /// 渐变轴起点，默认值为 `UnitPoint.top`。
    public var startPoint: UnitPoint {
        didSet { updateResolvedPoints() }
    }

    /// 渐变轴终点，默认值为 `UnitPoint.bottom`。
    public var endPoint: UnitPoint {
        didSet { updateResolvedPoints() }
    }

    /// 创建使用系统默认渐变参数的空视图。
    public override init(frame: CGRect) {
        gradient = QuickLayoutGradient(stops: [])
        startPoint = .top
        endPoint = .bottom
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 归档创建渐变视图。
    public required init?(coder: NSCoder) {
        gradient = QuickLayoutGradient(stops: [])
        startPoint = .top
        endPoint = .bottom
        super.init(coder: coder)
        configureView()
    }

    /// 使用渐变值创建视图。
    public convenience init(
        gradient: QuickLayoutGradient,
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) {
        self.init(frame: .zero)
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// 使用均匀分布的颜色创建视图。
    public convenience init(
        colors: [UIColor],
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) {
        self.init(
            gradient: QuickLayoutGradient(colors: colors),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// 使用精确的颜色停靠点创建视图。
    public convenience init(
        stops: [QuickLayoutGradient.Stop],
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) {
        self.init(
            gradient: QuickLayoutGradient(stops: stops),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else { return }
        updateGradient()
        updateResolvedPoints()
    }

    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            updateResolvedPoints()
        }
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        updateResolvedPoints()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit 不会像 SwiftUI 一样自动把单位坐标原点切换到 RTL 的右上角。
        updateResolvedPoints()
    }

    private func configureView() {
        isOpaque = false
        gradientLayer.type = .axial
        updateGradient()
        updateResolvedPoints()
    }

    private func updateGradient() {
        gradientLayer.colors = gradient.stops.map {
            $0.color.resolvedColor(with: traitCollection).cgColor
        }
        gradientLayer.locations = gradient.stops.map {
            NSNumber(value: Double($0.location))
        }
    }

    private func updateResolvedPoints() {
        let direction = effectiveUserInterfaceLayoutDirection
        gradientLayer.startPoint = startPoint.layerPoint(
            layoutDirection: direction
        )
        gradientLayer.endPoint = endPoint.layerPoint(
            layoutDirection: direction
        )
    }
}

private extension UnitPoint {
    func layerPoint(
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> CGPoint {
        let resolvedX = layoutDirection == .rightToLeft ? 1 - x : x
        return CGPoint(x: resolvedX, y: y)
    }
}
