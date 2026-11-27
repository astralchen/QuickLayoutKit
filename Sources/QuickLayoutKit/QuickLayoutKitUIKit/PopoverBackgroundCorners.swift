import UIKit
import ObjectiveC

/// UIKit 只公开自定义背景的类型。将自定义圆角保存在本次呈现上，让两个内置背景在布局时读取。
extension UIPopoverPresentationController {
    /// 给 QuickLayoutKit 的纯色或描边背景设置统一半径。传 nil 或负数恢复背景的默认外形。
    public func setCustomBackgroundCornerRadius(_ radius: CGFloat?) {
        let guide = customBackgroundCornerGuide
        guide.usesConfiguration = false
        guide.fixedRadius = radius.flatMap { $0 >= 0 ? $0 : nil }
        guide.superview?.setNeedsLayout()
    }

    /// 在主体的实际尺寸和视图环境中解析四个物理角。传 nil 恢复默认外形。
    @available(iOS 26, *)
    public func setCustomBackgroundCornerConfiguration(_ configuration: UICornerConfiguration?) {
        let guide = customBackgroundCornerGuide
        guide.fixedRadius = nil
        if let configuration { guide.cornerConfiguration = configuration }
        guide.usesConfiguration = configuration != nil
        guide.superview?.setNeedsLayout()
    }

    private var customBackgroundCornerGuide: PopoverCornerGuide {
        if let existing = objc_getAssociatedObject(self, &PopoverCornerGuide.key) as? PopoverCornerGuide { return existing }
        let guide = PopoverCornerGuide()
        guide.isHidden = true
        objc_setAssociatedObject(self, &PopoverCornerGuide.key, guide, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return guide
    }

    func customBackgroundRadii(in view: UIPopoverBackgroundView, height: CGFloat) -> [CGFloat]? {
        let guide = customBackgroundCornerGuide
        if guide.superview !== view { view.addSubview(guide) }
        if let radius = guide.fixedRadius { return Array(repeating: radius, count: 4) }
        if #available(iOS 26, *), guide.usesConfiguration {
            var insets = UIEdgeInsets.zero
            switch view.arrowDirection {
            case .up: insets.top = min(height, view.bounds.height)
            case .down: insets.bottom = min(height, view.bounds.height)
            case .left: insets.left = min(height, view.bounds.width)
            case .right: insets.right = min(height, view.bounds.width)
            default: break
            }
            guide.frame = view.bounds.inset(by: insets)
            return view.arrowDirection.outlineCorners.map { guide.effectiveRadius(corner: $0) }
        }
        return nil
    }
}

private final class PopoverCornerGuide: UIView {
    static var key: UInt8 = 0
    var fixedRadius: CGFloat?
    var usesConfiguration = false
}

/// 箭根之后的圆角沿侧边保留配置的切点，沿箭头所在边的跨度由剩余空间决定。
/// 两个轴分开计算，使被箭根挤窄的圆角仍能平滑接回侧边。
func popoverTrailingCornerHandle(radius: CGFloat, space: CGFloat, arrowHeight: CGFloat) -> CGFloat {
    let circular: CGFloat = 4 * (sqrt(2) - 1) / 3
    guard radius > 0 else { return circular }
    let proximity = max(0, min(1, (1.5 - space / radius) * 1.5))
    // 小圆角保留弧度；圆角大于箭头高度时，逐渐拉长切线以接回直边。
    let pinned = min(0.98, max(2.0 / 3.0, radius / (2 * arrowHeight)))
    return circular + (pinned - circular) * proximity
}
