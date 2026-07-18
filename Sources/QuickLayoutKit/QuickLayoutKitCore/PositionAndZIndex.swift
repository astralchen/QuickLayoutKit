import QuickLayout
import UIKit

public extension Element {

    /// Positions the center of this element at a point in the space proposed
    /// by its parent.
    func position(_ position: CGPoint) -> Element & Layout {
        PositionElement(child: self, position: position)
    }

    /// Positions the center of this element at the specified coordinates in
    /// the space proposed by its parent.
    func position(x: CGFloat, y: CGFloat) -> Element & Layout {
        position(CGPoint(x: x, y: y))
    }

    /// Controls the display order of overlapping elements.
    ///
    /// Larger values appear in front of smaller values. Equal values retain
    /// source order.
    func zIndex(_ value: Double) -> Element & Layout {
        ZIndexElement(child: self, value: value.isFinite ? value : 0)
    }
}

enum _ZIndexLayoutValueKey: LayoutValueKey {
    static let defaultValue: Double = 0
}

private struct PositionElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let position: CGPoint

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let childLayout = child.quick_layoutThatFits(
            ProposedSize.unspecified.quickLayoutProposal
        )
        let size = CGSize(
            width: proposedSize.width.isFinite
                ? max(0, proposedSize.width)
                : childLayout.size.width,
            height: proposedSize.height.isFinite
                ? max(0, proposedSize.height)
                : childLayout.size.height
        )
        let origin = CGPoint(
            x: finite(position.x) - childLayout.size.width / 2,
            y: finite(position.y) - childLayout.size.height / 2
        )

        return positionedPositionElement(
            childLayout,
            at: origin,
            in: size
        ).quick_layoutThatFits(size)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private struct ZIndexElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let value: Double

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? {
        guard key == ObjectIdentifier(_ZIndexLayoutValueKey.self) else { return nil }
        return _AnyLayoutValue(value: value)
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        let startIndex = views.endIndex
        child.quick_extractViewsIntoArray(&views)
        guard Thread.isMainThread else { return }
        let zPosition = CGFloat(value)
        MainActor.assumeIsolated {
            for view in views[startIndex...] {
                view.layer.zPosition = zPosition
            }
        }
    }
}

private struct PositionPrecomputedLayoutElement: Layout {
    let layout: LayoutNode

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func positionedPositionElement(
    _ layout: LayoutNode,
    at origin: CGPoint,
    in containerSize: CGSize
) -> Element & Layout {
    let horizontalOffset: CGFloat
    if LayoutContext.layoutDirection == .rightToLeft {
        let leadingOrigin = containerSize.width - layout.size.width
        horizontalOffset = leadingOrigin - origin.x
    } else {
        horizontalOffset = origin.x
    }

    return FixedFrameElement(
        child: OffsetElement(
            child: PositionPrecomputedLayoutElement(layout: layout),
            offset: CGPoint(x: horizontalOffset, y: origin.y)
        ),
        width: containerSize.width,
        height: containerSize.height,
        alignment: .topLeading
    )
}

private func finite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}
