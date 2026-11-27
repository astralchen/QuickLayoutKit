import UIKit

/// 适用于 UIKit 和 QuickLayoutKit 浮层的纯色背景。主体和箭头共用视图的背景色。
open class SolidPopoverBackground: UIPopoverBackgroundView, PopoverBackgroundAppearanceProviding {
    open override class func arrowBase() -> CGFloat { 28 }
    open override class func arrowHeight() -> CGFloat { 12 }
    open override class func contentViewInsets() -> UIEdgeInsets {
        UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    }

    private let nativeFill = NativePopoverFill()
    private let fill = UIView()
    private let outline = CAShapeLayer()
    private var offset: CGFloat = 0
    private var direction: UIPopoverArrowDirection = []
    open override var backgroundColor: UIColor? {
        get { fill.backgroundColor }
        set { fill.backgroundColor = newValue }
    }

    open override var arrowOffset: CGFloat {
        get { offset }
        set { offset = newValue; setNeedsLayout() }
    }
    open override var arrowDirection: UIPopoverArrowDirection {
        get { direction }
        set { direction = newValue; setNeedsLayout() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // 遮罩随布局同步更新；浮层入场的动画由呈现控制器驱动。
        outline.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        // UIKit 会给背景视图自身设置圆角。独立的填色视图只沿完整的箭头轮廓裁剪一次。
        fill.isUserInteractionEnabled = false
        fill.layer.mask = outline
        addSubview(fill)
        backgroundColor = .systemBackground
    }

    public required init?(coder: NSCoder) { nil }

    private var configuredRadii: [CGFloat]?

    /// QuickLayoutKit 的协议入口会同步圆角，再调用两种呈现共用的外观回调。
    open func applyPopoverAppearance(from controller: PopoverPresentationController) {
        let radii = controller.backgroundRadii(for: arrowDirection)
        if radii != configuredRadii {
            configuredRadii = radii
            setNeedsLayout()
        }
        applyPopoverAppearance(from: controller, backgroundColor: controller.backgroundColor)
    }

    /// UIKit 与 QuickLayoutKit 在呈现及控制器背景色变化时调用。传入 nil 表示恢复背景默认色。
    open func applyPopoverAppearance(from controller: UIPresentationController, backgroundColor: UIColor?) {
        self.backgroundColor = backgroundColor ?? .systemBackground
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        nativeFill.bind(to: self) { [weak self] controller in
            self?.applyPopoverAppearance(from: controller, backgroundColor: controller.backgroundColor)
        }
        if let native = nativeFill.controller {
            configuredRadii = native.customBackgroundRadii(in: self, height: max(0, Self.arrowHeight()))
        }
        // 外层呈现容器已经绘制阴影，避免自定义背景再叠加一层。
        layer.shadowOpacity = 0
        let horizontal = arrowDirection == .left || arrowDirection == .right
        let size = bounds.size
        let width = horizontal ? size.height : size.width
        let height = horizontal ? size.width : size.height
        guard width > 0, height > 0 else {
            outline.path = nil
            return
        }
        let arrowHeight = max(0, Self.arrowHeight())
        let hasArrow = arrowHeight > 0 && (horizontal || arrowDirection == .up || arrowDirection == .down)
        let top = hasArrow ? min(arrowHeight, height) : 0
        let radii = (configuredRadii ?? Array(repeating: 32, count: 4)).map {
            max(0, min($0, width / 2, (height - top) / 2))
        }
        var leftCorner = radii[0]
        var rightCorner = radii[1]
        var leftSpace = width
        var rightSpace = width
        let path = UIBezierPath()

        // 先画向上的箭头。两侧曲线在箭尖共用水平切线，箭根也沿主体边缘接入。
        if hasArrow {
            let halfBase = min(max(0, Self.arrowBase()) / 2, width / 2)
            // 默认底边 28 pt 时箭尖距边至少 19 pt，加宽后也要为箭根留出圆角过渡。
            let clearance = min(width / 2, halfBase + 5)
            let offset = arrowDirection == .down || arrowDirection == .left ? -arrowOffset : arrowOffset
            let tip = min(width - clearance, max(clearance, width / 2 + offset))
            let start = tip - halfBase
            let end = tip + halfBase
            leftSpace = start
            rightSpace = width - end
            leftCorner = min(leftCorner, start)
            rightCorner = min(rightCorner, width - end)
            path.move(to: CGPoint(x: leftCorner, y: top))
            path.addLine(to: CGPoint(x: start, y: top))
            path.addCurve(to: CGPoint(x: tip, y: 0),
                          controlPoint1: CGPoint(x: start + halfBase / 3, y: top),
                          controlPoint2: CGPoint(x: tip - halfBase / 6, y: 0))
            path.addCurve(to: CGPoint(x: end, y: top),
                          controlPoint1: CGPoint(x: tip + halfBase / 6, y: 0),
                          controlPoint2: CGPoint(x: end - halfBase / 3, y: top))
        } else {
            path.move(to: CGPoint(x: leftCorner, y: top))
        }

        // 默认外形保留较长的平滑过渡。显式半径以四分之一圆为准，靠近箭根时延长手柄。
        let regularHandle: CGFloat = configuredRadii == nil ? 0.72 : 4 * (sqrt(2) - 1) / 3
        func handle(radius: CGFloat, space: CGFloat) -> CGFloat {
            guard configuredRadii != nil, hasArrow, radius > 0 else { return regularHandle }
            let proximity = max(0, min(1, (1.5 - space / radius) * 1.5))
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
            ? popoverTrailingCornerHandle(radius: radii[1], space: rightSpace, arrowHeight: arrowHeight)
            : regularHandle
        addCorner(from: CGPoint(x: width - rightCorner, y: top), through: CGPoint(x: width, y: top),
                  to: CGPoint(x: width, y: top + trailingDepth), handle: trailingHandle)
        addCorner(from: CGPoint(x: width, y: height - radii[2]), through: CGPoint(x: width, y: height),
                  to: CGPoint(x: width - radii[2], y: height), handle: regularHandle)
        addCorner(from: CGPoint(x: radii[3], y: height), through: CGPoint(x: 0, y: height),
                  to: CGPoint(x: 0, y: height - radii[3]), handle: regularHandle)
        addCorner(from: CGPoint(x: 0, y: top + leftCorner), through: CGPoint(x: 0, y: top),
                  to: CGPoint(x: leftCorner, y: top), handle: handle(radius: radii[0], space: leftSpace))
        path.close()
        switch arrowDirection {
        case .down: path.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height))
        case .left: path.apply(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.height))
        case .right: path.apply(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0))
        default: break
        }
        fill.frame = bounds
        outline.frame = fill.bounds
        outline.path = path.cgPath
    }
}
