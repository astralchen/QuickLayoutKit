import QuartzCore
import UIKit

/// 描述可在给定矩形中生成路径的形状。
///
/// 该协议对照 SwiftUI `Shape.path(in:)`，只负责几何路径；填充、描边和动画由
/// ``QuickLayoutShapeView`` 负责。
public protocol QuickLayoutShape: Sendable {
    /// 返回形状在指定矩形中的 Core Graphics 路径。
    func path(in rect: CGRect) -> CGPath
}

/// 类型擦除后的可复用形状值。
///
/// API 对照 SwiftUI `AnyShape`。它保留 ``QuickLayoutShape/path(in:)`` 的非可选路径
/// 契约，同时允许 ``QuickLayoutShapeView`` 在运行时更换不同的具体形状类型。
public struct QuickLayoutAnyShape: QuickLayoutShape {
    public typealias PathProvider = @Sendable (_ rect: CGRect) -> CGPath

    private let pathProvider: PathProvider

    /// 擦除具体形状类型。
    public init<Shape: QuickLayoutShape>(_ shape: Shape) {
        pathProvider = shape.path(in:)
    }

    /// 使用纯路径提供者创建形状值。
    public init(path: @escaping PathProvider) {
        pathProvider = path
    }

    public func path(in rect: CGRect) -> CGPath {
        pathProvider(rect)
    }
}

/// 描述形状描边样式的值类型。
///
/// 属性语义与 SwiftUI `StrokeStyle` 对齐，并由 ``QuickLayoutShapeView`` 映射到
/// `CAShapeLayer`。
public struct QuickLayoutStrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    public init(
        lineWidth: CGFloat = 1,
        lineCap: CGLineCap = .butt,
        lineJoin: CGLineJoin = .miter,
        miterLimit: CGFloat = 10,
        dash: [CGFloat] = [],
        dashPhase: CGFloat = 0
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

/// 描述形状填充规则的值类型。
public struct QuickLayoutFillStyle: Equatable, Sendable {
    /// 是否使用奇偶填充规则。
    public var isEOFilled: Bool

    /// 是否允许边缘抗锯齿。
    ///
    /// UIKit 没有与 SwiftUI `FillStyle.antialiased` 完全等价的路径级开关，组件将该值
    /// 映射到根图层的 `allowsEdgeAntialiasing`；最终栅格化效果仍由 Core Animation 决定。
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

/// 使用 `CAShapeLayer` 作为根图层的通用形状视图。
///
/// 路径提供者会在视图尺寸改变时重新接收最新 `bounds`，因此调用方不需要维护图层 frame
/// 或在外部 `layoutSubviews()` 中重建路径。动态填充色和描边色会跟随界面样式更新。
/// 类保持开放以支持组合专用视图；受管理的形状状态可公开读写，但不允许子类覆写同步逻辑。
@MainActor
open class QuickLayoutShapeView: UIView {

    /// 根据当前视图边界生成路径的闭包类型。
    public typealias PathProvider = QuickLayoutAnyShape.PathProvider

    public override class var layerClass: AnyClass {
        CAShapeLayer.self
    }

    /// 框架内部使用的类型化根图层访问入口。
    ///
    /// 不对外暴露，避免调用方直接修改图层后与 `shape`、颜色及样式属性形成两套状态源。
    /// 外部确有 Core Animation 定制需求时，仍可自行检查 UIView 的 `layer`，但该用法
    /// 不属于组件保证兼容性的公共 API。
    internal final var shapeLayer: CAShapeLayer {
        guard let shapeLayer = layer as? CAShapeLayer else {
            preconditionFailure("QuickLayoutShapeView 的根图层必须是 CAShapeLayer")
        }
        return shapeLayer
    }

    /// 当前形状几何；`nil` 表示不绘制路径。
    public var shape: QuickLayoutAnyShape? {
        didSet { setNeedsLayout() }
    }

    /// 形状填充颜色；`nil` 表示不填充。
    public var fillColor: UIColor? {
        didSet { updateResolvedColors() }
    }

    /// 形状描边颜色；`nil` 表示不描边。
    public var strokeColor: UIColor? {
        didSet { updateResolvedColors() }
    }

    /// 形状描边样式。
    public var strokeStyle: QuickLayoutStrokeStyle {
        didSet { updateStrokeStyle() }
    }

    /// 形状填充规则。
    public var fillStyle: QuickLayoutFillStyle {
        didSet { updateFillStyle() }
    }

    /// 创建尚未提供路径的形状视图。
    public override init(frame: CGRect) {
        fillColor = .label
        strokeColor = nil
        strokeStyle = QuickLayoutStrokeStyle()
        fillStyle = QuickLayoutFillStyle()
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 归档创建形状视图。
    public required init?(coder: NSCoder) {
        fillColor = .label
        strokeColor = nil
        strokeStyle = QuickLayoutStrokeStyle()
        fillStyle = QuickLayoutFillStyle()
        super.init(coder: coder)
        configureView()
    }

    /// 使用路径提供者创建形状视图。
    public convenience init(
        fillColor: UIColor? = .label,
        strokeColor: UIColor? = nil,
        strokeStyle: QuickLayoutStrokeStyle = QuickLayoutStrokeStyle(),
        fillStyle: QuickLayoutFillStyle = QuickLayoutFillStyle(),
        path: @escaping PathProvider
    ) {
        self.init(frame: .zero)
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeStyle = strokeStyle
        self.fillStyle = fillStyle
        shape = QuickLayoutAnyShape(path: path)
        applyConfiguration()
    }

    /// 使用符合 ``QuickLayoutShape`` 的几何值创建形状视图。
    public convenience init<Shape: QuickLayoutShape>(
        shape: Shape,
        fillColor: UIColor? = .label,
        strokeColor: UIColor? = nil,
        strokeStyle: QuickLayoutStrokeStyle = QuickLayoutStrokeStyle(),
        fillStyle: QuickLayoutFillStyle = QuickLayoutFillStyle()
    ) {
        self.init(
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeStyle: strokeStyle,
            fillStyle: fillStyle,
            path: QuickLayoutAnyShape(shape).path(in:)
        )
    }

    /// 更换形状几何，同时保留当前填充和描边样式。
    public func setShape<Shape: QuickLayoutShape>(_ shape: Shape) {
        self.shape = QuickLayoutAnyShape(shape)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.path = shape?.path(in: bounds)
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else { return }
        updateResolvedColors()
    }

    private func configureView() {
        isOpaque = false
        applyConfiguration()
    }

    private func applyConfiguration() {
        updateResolvedColors()
        updateStrokeStyle()
        updateFillStyle()
        setNeedsLayout()
    }

    private func updateResolvedColors() {
        shapeLayer.fillColor = fillColor?
            .resolvedColor(with: traitCollection).cgColor
        shapeLayer.strokeColor = strokeColor?
            .resolvedColor(with: traitCollection).cgColor
    }

    private func updateStrokeStyle() {
        shapeLayer.lineWidth = strokeStyle.lineWidth
        shapeLayer.lineCap = switch strokeStyle.lineCap {
        case .butt: .butt
        case .round: .round
        case .square: .square
        @unknown default: .butt
        }
        shapeLayer.lineJoin = switch strokeStyle.lineJoin {
        case .miter: .miter
        case .round: .round
        case .bevel: .bevel
        @unknown default: .miter
        }
        shapeLayer.miterLimit = strokeStyle.miterLimit
        shapeLayer.lineDashPattern = strokeStyle.dash.isEmpty
            ? nil
            : strokeStyle.dash.map { NSNumber(value: Double($0)) }
        shapeLayer.lineDashPhase = strokeStyle.dashPhase
    }

    private func updateFillStyle() {
        shapeLayer.fillRule = fillStyle.isEOFilled ? .evenOdd : .nonZero
        shapeLayer.allowsEdgeAntialiasing = fillStyle.isAntialiased
    }
}
