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
    /// 接收目标矩形并返回绘制路径的可发送闭包。
    public typealias PathProvider = @Sendable (_ rect: CGRect) -> CGPath

    /// 类型擦除后保存的路径生成闭包。
    private let pathProvider: PathProvider

    /// 擦除具体形状类型。
    public init<Shape: QuickLayoutShape>(_ shape: Shape) {
        pathProvider = shape.path(in:)
    }

    /// 使用纯路径提供者创建形状值。
    public init(path: @escaping PathProvider) {
        pathProvider = path
    }

    /// 在指定矩形中生成形状路径。
    ///
    /// - Parameter rect: 形状路径使用的目标矩形。
    /// - Returns: 路径闭包生成的 Core Graphics 路径。
    public func path(in rect: CGRect) -> CGPath {
        pathProvider(rect)
    }
}

/// 描述形状描边样式的值类型。
///
/// 属性语义与 SwiftUI `StrokeStyle` 对齐，并由 ``QuickLayoutShapeView`` 映射到
/// `CAShapeLayer`。
public struct QuickLayoutStrokeStyle: Equatable, Sendable {
    /// 描边宽度，单位为点；默认值为 `1`。
    public var lineWidth: CGFloat
    /// 开放路径端点的样式，默认为 `.butt`。
    public var lineCap: CGLineCap
    /// 路径转角的连接样式，默认为 `.miter`。
    public var lineJoin: CGLineJoin
    /// 斜接连接的限制值，默认为 `10`。
    public var miterLimit: CGFloat
    /// 虚线各段的长度序列，默认为空数组，表示实线。
    public var dash: [CGFloat]
    /// 虚线模式的起始相位，默认为零。
    public var dashPhase: CGFloat

    /// 创建描边样式，数值原样保存并交给 `CAShapeLayer`。
    ///
    /// - Parameters:
    ///   - lineWidth: 线宽，默认 `1`。
    ///   - lineCap: 端点样式，默认 `.butt`。
    ///   - lineJoin: 转角样式，默认 `.miter`。
    ///   - miterLimit: 斜接限制，默认 `10`。
    ///   - dash: 虚线段长度，默认空数组。
    ///   - dashPhase: 虚线起始相位，默认零。
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

    /// 创建填充规则与抗锯齿配置。
    ///
    /// - Parameters:
    ///   - eoFill: 是否使用奇偶填充规则；默认 `false`，采用非零绕数规则。
    ///   - antialiased: 是否允许边缘抗锯齿，默认 `true`。
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

    /// 以 `CAShapeLayer` 作为视图的后备图层。
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

    /// 按最新边界重新生成路径；没有形状时清空图层路径。
    open override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.path = shape?.path(in: bounds)
    }

    /// 颜色外观变化后重新解析填充与描边的动态颜色。
    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else { return }
        updateResolvedColors()
    }

    /// 关闭不透明标记并应用初始图层配置。
    private func configureView() {
        isOpaque = false
        applyConfiguration()
    }

    /// 同步颜色、描边和填充规则，并请求按最新边界更新路径。
    private func applyConfiguration() {
        updateResolvedColors()
        updateStrokeStyle()
        updateFillStyle()
        setNeedsLayout()
    }

    /// 将动态填充色与描边色解析为当前特征对应的 `CGColor`。
    private func updateResolvedColors() {
        shapeLayer.fillColor = fillColor?
            .resolvedColor(with: traitCollection).cgColor
        shapeLayer.strokeColor = strokeColor?
            .resolvedColor(with: traitCollection).cgColor
    }

    /// 将描边样式映射到图层；空虚线数组使用实线，未知连接样式采用默认值。
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

    /// 将奇偶填充与边缘抗锯齿配置应用到图层。
    private func updateFillStyle() {
        shapeLayer.fillRule = fillStyle.isEOFilled ? .evenOdd : .nonZero
        shapeLayer.allowsEdgeAntialiasing = fillStyle.isAntialiased
    }
}
