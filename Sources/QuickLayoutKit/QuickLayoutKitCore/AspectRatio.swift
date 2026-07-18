import QuickLayout
import UIKit

public extension Element {

    /// Constrains this element to a width-to-height ratio.
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

    /// Constrains this element to a width-to-height ratio.
    ///
    /// Pass `nil` to preserve the element's ideal aspect ratio.
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

    /// Scales this element to fit its parent while preserving its ideal aspect
    /// ratio.
    func scaledToFit() -> Element & Layout {
        aspectRatio(nil, contentMode: .fit)
    }

    /// Scales this element to fill its parent while preserving its ideal
    /// aspect ratio.
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
