import UIKit

/// 用于 QuickLayoutKit 浮层的描边背景，主体、圆角和箭头共享一条闭合轮廓。
/// 子类可覆写箭头尺寸、内容边距或绘制方法，并通过 popoverBackgroundViewClass 使用。
open class OutlinedPopoverBackground: UIView, PopoverBackgroundDrawing, PopoverBackgroundAppearanceProviding {
    open nonisolated class func arrowBase() -> CGFloat { 32 }
    open nonisolated class func arrowHeight() -> CGFloat { 13 }
    open nonisolated class func contentViewInsets() -> UIEdgeInsets { .init(top: 12, left: 16, bottom: 12, right: 16) }

    /// 只填充闭合轮廓内部；透明填色仍保留描边。
    open var fillColor: UIColor = .secondarySystemBackground {
        didSet { if fillColor != oldValue { setNeedsDisplay() } }
    }

    fileprivate var configuredRadii: [CGFloat]? {
        didSet { if configuredRadii != oldValue { setNeedsDisplay() } }
    }

    open func applyPopoverAppearance(from controller: PopoverPresentationController) {
        configuredRadii = controller.backgroundRadii(for: arrowDirection)
        applyPopoverAppearance(from: controller, backgroundColor: controller.backgroundColor)
    }

    /// 两种呈现共用的配色回调；背景色为 nil 时使用描边背景的默认填色。
    open func applyPopoverAppearance(from controller: UIPresentationController, backgroundColor: UIColor?) {
        fillColor = backgroundColor ?? .secondarySystemBackground
    }

    open var arrowDirection: UIPopoverArrowDirection = [] { didSet { setNeedsDisplay() } }
    open var arrowOffset: CGFloat = 0 { didSet { setNeedsDisplay() } }

    /// 包装层从子类类型创建实例，因此每个绘图子类都必须提供或继承此初始化器。
    public required override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    public required init?(coder: NSCoder) { nil }

    open override func draw(_ rect: CGRect) {
        // 以箭头向上为基准，在最后一步把整条轮廓旋转到实际方向。
        let horizontal = arrowDirection == .left || arrowDirection == .right
        let width = horizontal ? bounds.height : bounds.width
        let height = horizontal ? bounds.width : bounds.height
        guard width > 3, height > 3 else { return }
        let inset: CGFloat = 1.5
        let arrowHeight = max(0, Self.arrowHeight())
        let hasArrow = arrowHeight > 0 && [.up, .down, .left, .right].contains(arrowDirection)
        let top = inset + (hasArrow ? min(arrowHeight, height - 2 * inset) : 0)
        let right = width - inset
        let bottom = height - inset
        let halfWidth = (right - inset) / 2
        let halfBase = hasArrow ? min(max(0, Self.arrowBase()) / 2, halfWidth / 2) : 0
        let radii = (configuredRadii ?? Array(repeating: 37 + inset, count: 4)).map {
            max(0, min($0 - inset, halfWidth, (bottom - top) / 2))
        }
        let offset = arrowDirection == .down || arrowDirection == .left ? -arrowOffset : arrowOffset
        // 同机 UIKit 截图中，32 pt 宽箭头的尖端最靠近边缘约 19 pt。
        // 移动整支箭头，并用剩余空间收小相邻圆角，避免箭尖越过箭根后描边折返。
        let minimumTipDistance = min(width / 2, halfBase + 3)
        let tipX = min(width - minimumTipDistance, max(minimumTipDistance, width / 2 + offset))
        let start = tipX - halfBase
        let end = tipX + halfBase
        let leftCorner = hasArrow ? min(radii[0], start - inset) : radii[0]
        let rightCorner = hasArrow ? min(radii[1], right - end) : radii[1]
        let path = UIBezierPath()
        path.move(to: CGPoint(x: inset + leftCorner, y: top))
        if hasArrow {
            // 两侧控制点依序落在各自的半个底边内，根部和尖端都与水平切线相接。
            let rootHandle = halfBase / 3
            let tipHandle = halfBase / 6
            path.addLine(to: CGPoint(x: start, y: top))
            path.addCurve(to: CGPoint(x: tipX, y: inset),
                          controlPoint1: CGPoint(x: start + rootHandle, y: top),
                          controlPoint2: CGPoint(x: tipX - tipHandle, y: inset))
            path.addCurve(to: CGPoint(x: end, y: top),
                          controlPoint1: CGPoint(x: tipX + tipHandle, y: inset),
                          controlPoint2: CGPoint(x: end - rootHandle, y: top))
        }
        // 以原生浮层外沿为参照，控制点沿两侧直边布置。靠近箭根时，
        // 缩短该角的过渡范围，并延长相对手柄，让粗描边平滑接回主体。
        let regularHandle: CGFloat = configuredRadii == nil ? 0.64 : 4 * (sqrt(2) - 1) / 3
        func handle(for space: CGFloat, radius corner: CGFloat) -> CGFloat {
            guard hasArrow, corner > 0 else { return regularHandle }
            let proximity = max(0, min(1, (1.5 - space / corner) * (configuredRadii == nil ? 2 : 1.5)))
            return regularHandle + (0.98 - regularHandle) * proximity
        }
        func addCorner(from start: CGPoint, through vertex: CGPoint, to end: CGPoint, handle: CGFloat) {
            path.addLine(to: start)
            path.addCurve(to: end,
                          controlPoint1: CGPoint(x: start.x + (vertex.x - start.x) * handle,
                                                 y: start.y + (vertex.y - start.y) * handle),
                          controlPoint2: CGPoint(x: end.x + (vertex.x - end.x) * handle,
                                                 y: end.y + (vertex.y - end.y) * handle))
        }
        let configuredTrailingCorner = configuredRadii != nil && hasArrow
        let trailingDepth = configuredTrailingCorner ? radii[1] : rightCorner
        let trailingHandle = configuredTrailingCorner
            ? popoverTrailingCornerHandle(radius: radii[1], space: right - end, arrowHeight: arrowHeight)
            : handle(for: right - end, radius: radii[1])
        addCorner(from: CGPoint(x: right - rightCorner, y: top), through: CGPoint(x: right, y: top),
                  to: CGPoint(x: right, y: top + trailingDepth), handle: trailingHandle)
        addCorner(from: CGPoint(x: right, y: bottom - radii[2]), through: CGPoint(x: right, y: bottom),
                  to: CGPoint(x: right - radii[2], y: bottom), handle: regularHandle)
        addCorner(from: CGPoint(x: inset + radii[3], y: bottom), through: CGPoint(x: inset, y: bottom),
                  to: CGPoint(x: inset, y: bottom - radii[3]), handle: regularHandle)
        addCorner(from: CGPoint(x: inset, y: top + leftCorner), through: CGPoint(x: inset, y: top),
                  to: CGPoint(x: inset + leftCorner, y: top), handle: handle(for: start - inset, radius: radii[0]))
        path.close()
        switch arrowDirection {
        case .down: path.apply(.init(a: -1, b: 0, c: 0, d: -1, tx: bounds.width, ty: bounds.height))
        case .left: path.apply(.init(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: bounds.height))
        case .right: path.apply(.init(a: 0, b: 1, c: -1, d: 0, tx: bounds.width, ty: 0))
        default: break
        }
        fillColor.setFill()
        path.fill()
        UIColor.systemIndigo.setStroke()
        path.lineWidth = 2 * inset
        path.lineJoinStyle = .round
        path.stroke()
    }
}

/// 用于 UIPopoverPresentationController 的描边背景，复用 OutlinedPopoverBackground 绘制轮廓。
open class UIOutlinedPopoverBackground: UIPopoverBackgroundView, PopoverBackgroundAppearanceProviding {
    private let nativeFill = NativePopoverFill()
    private let drawing: OutlinedPopoverBackground

    /// 子类覆写此类型即可复用自己的描边背景。布局度量和实际绘图均使用该类型。
    open nonisolated class var drawingViewClass: OutlinedPopoverBackground.Type { OutlinedPopoverBackground.self }

    public override class func arrowBase() -> CGFloat { drawingViewClass.arrowBase() }
    public override class func arrowHeight() -> CGFloat { drawingViewClass.arrowHeight() }
    public override class func contentViewInsets() -> UIEdgeInsets { drawingViewClass.contentViewInsets() }

    /// UIKit 包装视图与内部绘图视图共用填色。
    open var fillColor: UIColor {
        get { drawing.fillColor }
        set {
            drawing.fillColor = newValue
            nativeFill.updateShadow(of: self, fill: newValue)
        }
    }

    open func applyPopoverAppearance(from controller: PopoverPresentationController) {
        drawing.applyPopoverAppearance(from: controller)
        nativeFill.updateShadow(of: self, fill: fillColor)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        nativeFill.bind(to: self) { [weak self] controller in
            guard let self else { return }
            drawing.applyPopoverAppearance(from: controller, backgroundColor: controller.backgroundColor)
            nativeFill.updateShadow(of: self, fill: fillColor)
        }
        if let native = nativeFill.controller {
            drawing.configuredRadii = native.customBackgroundRadii(in: self, height: max(0, Self.arrowHeight()))
        }
        nativeFill.updateShadow(of: self, fill: fillColor)
    }

    open override var arrowDirection: UIPopoverArrowDirection {
        get { drawing.arrowDirection }
        set { drawing.arrowDirection = newValue }
    }
    open override var arrowOffset: CGFloat {
        get { drawing.arrowOffset }
        set { drawing.arrowOffset = newValue }
    }

    public override init(frame: CGRect) {
        drawing = Self.drawingViewClass.init(frame: .zero)
        super.init(frame: frame)
        drawing.frame = bounds
        drawing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(drawing)
    }

    public required init?(coder: NSCoder) { nil }
}
