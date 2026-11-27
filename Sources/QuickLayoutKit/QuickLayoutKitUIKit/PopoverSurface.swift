import UIKit
import SwiftUI

extension UIPopoverArrowDirection {
    /// 向上绘图再旋转时，路径的左上、右上、右下、左下分别对应的物理角。
    var outlineCorners: [UIRectCorner] {
        switch self {
        case .down: return [.bottomRight, .bottomLeft, .topLeft, .topRight]
        case .left: return [.bottomLeft, .topLeft, .topRight, .bottomRight]
        case .right: return [.topRight, .bottomRight, .bottomLeft, .topLeft]
        default: return [.topLeft, .topRight, .bottomRight, .bottomLeft]
        }
    }
}

/// 以上边缘为基准构造轮廓，再旋转至实际方向。
/// 箭头贴角时一起移动尖端和底边，并为邻近的圆角保留可用空间。
@MainActor
enum PopoverOutline {
    static let height: CGFloat = 13
    // 27.2 的默认箭头从中心向两侧各约 16 pt 处接回直边。
    static let base: CGFloat = 32

    static func path(for layout: PopoverLayout, offset: CGFloat, radius: (UIRectCorner) -> CGFloat) -> CGPath {
        let size = layout.frame.size
        let dir = layout.direction
        let vertical = dir.isEmpty || dir == .up || dir == .down
        let width = vertical ? size.width : size.height
        let height = vertical ? size.height : size.width
        let top = dir.isEmpty ? 0 : min(Self.height, height)

        // 按路径旋转后的顺序读取物理圆角，左右方向也支持非对称圆角。
        var radii = dir.outlineCorners.map { max(0, min(radius($0), width / 2, (height - top) / 2)) }
        // 四分之一圆的标准三次曲线手柄。箭根接近时逐渐延长，使角部更贴近平直的两侧。
        let circularHandle: CGFloat = 4 * (sqrt(2) - 1) / 3
        func shoulderHandle(radius: CGFloat, space: CGFloat) -> CGFloat {
            guard radius > 0 else { return 0 }
            let proximity = max(0, min(1, 2 - space / radius))
            // 以 27.2 玻璃角部的双侧截面校准，手柄始终留在圆角范围内。
            let pinnedHandle: CGFloat = 0.97
            return radius * (circularHandle + (pinnedHandle - circularHandle) * proximity)
        }
        var leftHandle = radii[0] * circularHandle
        var rightHandle = radii[1] * circularHandle
        let p = UIBezierPath()
        if dir.isEmpty {
            p.move(to: CGPoint(x: radii[0], y: top))
        } else {
            let halfBase = min(Self.base / 2, width / 2)
            // 27.2 原生玻璃在箭根外侧留约 3 pt。这里只限制可见轮廓，保留原始布局偏移。
            let clearance = min(width / 2, halfBase + 3)
            let tipOffset = dir == .down || dir == .left ? -offset : offset
            let tip = min(width - clearance, max(clearance, width / 2 + tipOffset))
            let start = tip - halfBase
            let end = tip + halfBase
            radii[0] = min(radii[0], start)
            radii[1] = min(radii[1], width - end)
            leftHandle = shoulderHandle(radius: radii[0], space: start)
            rightHandle = shoulderHandle(radius: radii[1], space: width - end)
            p.move(to: CGPoint(x: radii[0], y: top))
            p.addLine(to: CGPoint(x: start, y: top))
            p.addCurve(to: CGPoint(x: tip, y: 0), controlPoint1: CGPoint(x: start + halfBase / 3, y: top),
                       controlPoint2: CGPoint(x: tip - halfBase / 6, y: 0))
            p.addCurve(to: CGPoint(x: end, y: top), controlPoint1: CGPoint(x: tip + halfBase / 6, y: 0),
                       controlPoint2: CGPoint(x: end - halfBase / 3, y: top))
        }
        p.addLine(to: CGPoint(x: width - radii[1], y: top))
        p.addCurve(to: CGPoint(x: width, y: top + radii[1]),
                   controlPoint1: CGPoint(x: width - radii[1] + rightHandle, y: top),
                   controlPoint2: CGPoint(x: width, y: top + radii[1] - rightHandle))
        p.addLine(to: CGPoint(x: width, y: height - radii[2]))
        p.addArc(withCenter: CGPoint(x: width - radii[2], y: height - radii[2]), radius: radii[2], startAngle: 0, endAngle: .pi/2, clockwise: true)
        p.addLine(to: CGPoint(x: radii[3], y: height))
        p.addArc(withCenter: CGPoint(x: radii[3], y: height - radii[3]), radius: radii[3], startAngle: .pi/2, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: 0, y: top + radii[0]))
        p.addCurve(to: CGPoint(x: radii[0], y: top),
                   controlPoint1: CGPoint(x: 0, y: top + radii[0] - leftHandle),
                   controlPoint2: CGPoint(x: radii[0] - leftHandle, y: top))
        p.close()
        switch dir {
        case .down: p.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height))
        case .left: p.apply(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.height))
        case .right: p.apply(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0))
        default: break
        }
        return p.cgPath
    }
}

@MainActor
final class PopoverSurface: UIView {
    private let clipped = UIView()
    private let maskShape = CAShapeLayer()
    private let material = UIVisualEffectView()
    private var glassView: (UIView & UIContentView)?
    private var glassPath: CGPath?
    private let arrowTint = UIView()
    private let bodyGuide = UIView()
    private var appliedEffect: UIVisualEffect?
    private var appliedBlur: UIBlurEffect.Style?
    private var custom: (any PopoverBackgroundDrawing)?
    private weak var contentView: UIView?

    func install(_ content: UIView, background: (any PopoverBackgroundDrawing.Type)?) {
        if clipped.superview == nil {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: 4)
            addSubview(clipped)
            clipped.addSubview(material)
            bodyGuide.isHidden = true
            addSubview(bodyGuide)
            arrowTint.isUserInteractionEnabled = false
            clipped.addSubview(arrowTint)
            if #available(iOS 26, *) { material.cornerConfiguration = .corners(radius: .fixed(0)) }
            material.isUserInteractionEnabled = false
        }
        if let background, custom.map({ type(of: $0) != background }) ?? true {
            custom?.removeFromSuperview()
            let view = background.init(frame: .zero)
            view.isUserInteractionEnabled = false
            clipped.insertSubview(view, at: 0)
            custom = view
        } else if background == nil {
            custom?.removeFromSuperview()
            custom = nil
        }
        if custom != nil { glassView?.isHidden = true }
        if content.superview !== clipped { clipped.addSubview(content) }
        contentView = content
    }

    func configuredRadii(for controller: PopoverPresentationController, direction: UIPopoverArrowDirection) -> [CGFloat]? {
        if #available(iOS 26, *), controller.hasExplicitCornerConfiguration {
            return direction.outlineCorners.map { bodyGuide.effectiveRadius(corner: $0) }
        }
        guard controller.cornerRadius >= 0 else { return nil }
        return Array(repeating: controller.cornerRadius, count: 4)
    }

    func apply(_ layout: PopoverLayout, controller: PopoverPresentationController) {
        clipped.frame = bounds
        material.frame = bounds
        arrowTint.isHidden = custom != nil || controller.arrowBackgroundColor == nil || layout.direction.isEmpty
        bodyGuide.frame = layout.body
        if #available(iOS 26, *), let corners = controller.cornerConfiguration, bodyGuide.cornerConfiguration != corners {
            bodyGuide.cornerConfiguration = corners
        }
        if let custom {
            material.isHidden = true
            layer.shadowOpacity = custom is UIPopoverBackgroundView ? 0.18 : 0
            clipped.layer.mask = nil
            custom.frame = bounds
            if custom.arrowDirection != layout.direction { custom.arrowDirection = layout.direction }
            if custom.arrowOffset != controller.arrowOffset { custom.arrowOffset = controller.arrowOffset }
            (custom as? any PopoverBackgroundAppearanceProviding)?.applyPopoverAppearance(from: controller)
            layer.shadowPath = nil
        } else {
            var effect: UIVisualEffect?
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 26.1, *) { effect = controller.backgroundEffect }
            #endif
            // 显式效果或背景色（包括 clear）让 UIKit 切换到浮层内的效果视图。
            let usesGlass: Bool
            if #available(iOS 26, *) { usesGlass = effect == nil && controller.backgroundColor == nil }
            else { usesGlass = false }
            let blur: UIBlurEffect.Style? = usesGlass || effect != nil ? nil : (controller.backgroundBlurEffectStyle ?? .systemMaterial)
            if appliedEffect !== effect || appliedBlur != blur {
                if appliedEffect == nil, effect != nil { material.contentView.backgroundColor = nil }
                appliedEffect = effect
                appliedBlur = blur
                material.effect = effect ?? blur.map { UIBlurEffect(style: $0) }
            }
            material.isHidden = usesGlass || controller.backgroundBlurDisabled

            let path = PopoverOutline.path(for: layout, offset: controller.arrowOffset) { corner in
                if #available(iOS 26, *) { return bodyGuide.effectiveRadius(corner: corner) }
                return controller.cornerRadius >= 0 ? controller.cornerRadius : 13
            }
            maskShape.frame = bounds
            maskShape.path = path
            clipped.layer.mask = maskShape
            if #available(iOS 26, *), usesGlass {
                // 把完整轮廓交给玻璃材质，系统会沿圆角和箭头生成连续的折射边缘和阴影。
                // 玻璃放在裁剪层外，内容的遮罩不会截掉边缘高光。
                if glassPath != path {
                    let configuration = UIHostingConfiguration {
                        Color.clear.glassEffect(.regular, in: Path(path))
                    }.margins(.all, 0)
                    if let glassView { glassView.configuration = configuration }
                    else {
                        let view = configuration.makeContentView()
                        view.isUserInteractionEnabled = false
                        view.accessibilityElementsHidden = true
                        insertSubview(view, belowSubview: clipped)
                        glassView = view
                    }
                    glassPath = path
                }
                glassView?.frame = bounds
                glassView?.isHidden = false
                layer.shadowOpacity = 0
            } else {
                glassView?.isHidden = true
                layer.shadowOpacity = controller.backgroundBlurDisabled || controller.backgroundColor != nil || effect != nil ? 0 : 0.18
            }
            if effect == nil { material.contentView.backgroundColor = controller.backgroundColor }
            layer.shadowPath = path
            if !arrowTint.isHidden {
                arrowTint.backgroundColor = controller.arrowBackgroundColor
                switch layout.direction {
                case .up: arrowTint.frame = bounds.divided(atDistance: layout.body.minY, from: .minYEdge).slice
                case .down: arrowTint.frame = bounds.divided(atDistance: bounds.maxY - layout.body.maxY, from: .maxYEdge).slice
                case .left: arrowTint.frame = bounds.divided(atDistance: layout.body.minX, from: .minXEdge).slice
                case .right: arrowTint.frame = bounds.divided(atDistance: bounds.maxX - layout.body.maxX, from: .maxXEdge).slice
                default: break
                }
            }
        }
        contentView?.frame = layout.content
    }
}

@MainActor
final class PopoverBackdrop: UIControl {
    weak var owner: PopoverPresentationController?
    private let dimmingMask = CALayer()

    // 只裁切遮罩绘制。系统对照中顶部 inset 不改变背景外框或命中范围。
    func update(in container: UIView, topInset: CGFloat) {
        frame = container.bounds
        guard topInset > 0 else { layer.mask = nil; return }
        let top = min(topInset, bounds.height)
        dimmingMask.backgroundColor = UIColor.black.cgColor
        dimmingMask.frame = CGRect(x: bounds.minX, y: bounds.minY + top, width: bounds.width, height: bounds.height - top)
        layer.mask = dimmingMask
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let owner, let root = owner.presentingViewController.viewIfLoaded,
              let allowed = owner.passthroughViews, !allowed.isEmpty,
              let hit = root.hitTest(convert(point, to: root), with: event),
              allowed.contains(where: { hit === $0 || hit.isDescendant(of: $0) }) else {
            return super.hitTest(point, with: event)
        }
        return hit
    }
}
