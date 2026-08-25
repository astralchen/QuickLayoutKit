import QuickLayout
import UIKit

public extension Element {

    /// 将元素放置在具有最小、理想和最大尺寸的弹性框架中。
    ///
    /// 理想尺寸用于替换对应轴上未指定的尺寸建议。父元素提供的有限尺寸建议仍具有更高优先级。
    ///
    /// - Parameters:
    ///   - minWidth: 框架的最小宽度；`nil` 表示不设置最小宽度。
    ///   - idealWidth: 未指定水平约束时使用的理想宽度；`nil` 表示不提供备用宽度。
    ///   - maxWidth: 框架的最大宽度；`nil` 表示不设置最大宽度。
    ///   - minHeight: 框架的最小高度；`nil` 表示不设置最小高度。
    ///   - idealHeight: 未指定垂直约束时使用的理想高度；`nil` 表示不提供备用高度。
    ///   - maxHeight: 框架的最大高度；`nil` 表示不设置最大高度。
    ///   - alignment: 元素在框架内的对齐方式。
    /// - Returns: 放置在弹性框架中的元素。
    func frame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> Element & Layout {
        IdealFlexibleFrameElement(
            child: self,
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight,
            alignment: alignment
        )
    }
}

private struct IdealFlexibleFrameElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let idealHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    init(
        child: Element,
        minWidth: CGFloat?,
        idealWidth: CGFloat?,
        maxWidth: CGFloat?,
        minHeight: CGFloat?,
        idealHeight: CGFloat?,
        maxHeight: CGFloat?,
        alignment: Alignment
    ) {
        self.child = child
        self.minWidth = flexibleFrameDimension(minWidth)
        self.idealWidth = flexibleFrameDimension(idealWidth)
        self.maxWidth = flexibleFrameDimension(maxWidth)
        self.minHeight = flexibleFrameDimension(minHeight)
        self.idealHeight = flexibleFrameDimension(idealHeight)
        self.maxHeight = flexibleFrameDimension(maxHeight)
        self.alignment = alignment
    }

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let resolvedProposal = CGSize(
            width: resolvedFlexibleFrameProposal(
                proposedSize.width,
                ideal: idealWidth
            ),
            height: resolvedFlexibleFrameProposal(
                proposedSize.height,
                ideal: idealHeight
            )
        )
        let childProposal = CGSize(
            width: clampFlexibleFrameDimension(
                resolvedProposal.width,
                minimum: minWidth,
                maximum: maxWidth
            ),
            height: clampFlexibleFrameDimension(
                resolvedProposal.height,
                minimum: minHeight,
                maximum: maxHeight
            )
        )
        let childLayout = child.quick_layoutThatFits(childProposal)
        let frameSize = CGSize(
            width: flexibleFrameSize(
                child: childLayout.size.width,
                proposal: resolvedProposal.width,
                minimum: minWidth,
                maximum: maxWidth
            ),
            height: flexibleFrameSize(
                child: childLayout.size.height,
                proposal: resolvedProposal.height,
                minimum: minHeight,
                maximum: maxHeight
            )
        )

        return FixedFrameElement(
            child: FlexibleFramePrecomputedElement(layout: childLayout),
            width: frameSize.width,
            height: frameSize.height,
            alignment: alignment
        ).quick_layoutThatFits(frameSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        switch axis {
        case .horizontal where maxWidth != nil:
            .partial
        case .vertical where maxHeight != nil:
            .partial
        default:
            child.quick_flexibility(for: axis)
        }
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private struct FlexibleFramePrecomputedElement: Layout {
    let layout: LayoutNode

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func flexibleFrameDimension(_ value: CGFloat?) -> CGFloat? {
    guard let value, !value.isNaN else { return nil }
    return max(0, value)
}

private func resolvedFlexibleFrameProposal(
    _ proposal: CGFloat,
    ideal: CGFloat?
) -> CGFloat {
    proposal.isFinite ? proposal : ideal ?? proposal
}

private func clampFlexibleFrameDimension(
    _ value: CGFloat,
    minimum: CGFloat?,
    maximum: CGFloat?
) -> CGFloat {
    min(max(value, minimum ?? 0), maximum ?? .infinity)
}

private func flexibleFrameSize(
    child: CGFloat,
    proposal: CGFloat,
    minimum: CGFloat?,
    maximum: CGFloat?
) -> CGFloat {
    if minimum == nil, maximum == nil {
        return child
    }

    if let minimum, let maximum,
       proposal.isFinite || maximum.isFinite {
        return clampFlexibleFrameDimension(
            proposal,
            minimum: minimum,
            maximum: maximum
        )
    }

    if let minimum, proposal < child {
        return max(proposal, minimum)
    }

    if let maximum, proposal > child,
       proposal.isFinite || maximum.isFinite {
        return min(proposal, maximum)
    }

    return clampFlexibleFrameDimension(
        child,
        minimum: minimum,
        maximum: maximum
    )
}
