import QuickLayout
import UIKit

public extension Element {

    /// 按指定的宽高比约束元素。
    ///
    /// - Parameters:
    ///   - aspectRatio: 元素的宽高比。
    ///   - contentMode: 调整元素大小时使用的内容模式。
    /// - Returns: 应用宽高比约束后的元素。
    func aspectRatio(
        _ aspectRatio: CGFloat,
        contentMode: ContentMode = .fit
    ) -> Element & Layout {
        AspectRatioModifierElement(
            child: self,
            aspectRatio: aspectRatio,
            contentMode: contentMode
        )
    }

    /// 按指定的宽高比约束元素。
    ///
    /// 当 `aspectRatio` 为 `nil` 时，该方法使用元素的理想宽高比。
    ///
    /// - Parameters:
    ///   - aspectRatio: 元素的宽高比；传入 `nil` 表示保留元素的理想宽高比。
    ///   - contentMode: 调整元素大小时使用的内容模式。
    /// - Returns: 应用宽高比约束后的元素。
    func aspectRatio(
        _ aspectRatio: CGFloat? = nil,
        contentMode: ContentMode
    ) -> Element & Layout {
        AspectRatioModifierElement(
            child: self,
            aspectRatio: aspectRatio,
            contentMode: contentMode
        )
    }

    /// 在保持理想宽高比的同时，缩放元素以适应父元素。
    ///
    /// - Returns: 使用适应模式缩放后的元素。
    func scaledToFit() -> Element & Layout {
        aspectRatio(nil, contentMode: .fit)
    }

    /// 在保持理想宽高比的同时，缩放元素以填满父元素。
    ///
    /// - Returns: 使用填充模式缩放后的元素。
    func scaledToFill() -> Element & Layout {
        aspectRatio(nil, contentMode: .fill)
    }
}

/// 在测量时解析显式或理想宽高比的布局包装器。
private struct AspectRatioModifierElement: Layout, _LayoutValueProvidingElement {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 显式宽高比；`nil` 表示先测量子元素的理想尺寸。
    let aspectRatio: CGFloat?
    /// 宽高比约束采用的适应或填充策略。
    let contentMode: ContentMode

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }

    /// 本层不提供布局值，交由查询器继续访问子元素。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    /// 先确定宽高比，再由 QuickLayout 的宽高比元素完成约束测量。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let ratio: CGFloat
        if let aspectRatio {
            ratio = aspectRatio
        } else {
            let idealSize = child.quick_layoutThatFits(
                CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
            ).size
            ratio = idealAspectRatio(for: idealSize)
        }

        return AspectRatioElement(
            child: child,
            aspectRatio: ratio,
            contentMode: contentMode
        ).quick_layoutThatFits(proposedSize)
    }

    /// 允许父布局在指定轴上部分调整尺寸。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        .partial
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 从有限且为正的理想尺寸计算宽高比；无法计算时返回零。
private func idealAspectRatio(for size: CGSize) -> CGFloat {
    guard size.width > 0,
          size.height > 0,
          size.width.isFinite,
          size.height.isFinite else {
        return 0
    }
    return size.width / size.height
}
