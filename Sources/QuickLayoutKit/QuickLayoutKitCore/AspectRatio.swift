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

private struct AspectRatioModifierElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let aspectRatio: CGFloat?
    let contentMode: ContentMode

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

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

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .partial
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private func idealAspectRatio(for size: CGSize) -> CGFloat {
    guard size.width > 0,
          size.height > 0,
          size.width.isFinite,
          size.height.isFinite else {
        return 0
    }
    return size.width / size.height
}
