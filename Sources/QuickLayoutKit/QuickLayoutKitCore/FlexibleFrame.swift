import QuickLayout
import OSLog
import UIKit

/// 记录矛盾尺寸约束的非致命布局诊断。
private let flexibleFrameRuntimeLogger = Logger(
    subsystem: "com.astralchen.QuickLayoutKit",
    category: "LayoutRuntimeIssues"
)

public extension Element {

    /// 将元素放置在具有最小、理想和最大尺寸的弹性框架中。
    ///
    /// 理想尺寸用于替换对应轴上未指定的尺寸建议。父元素提供的有限尺寸建议仍具有更高优先级。
    /// 固定尺寸与弹性尺寸分属 SwiftUI 的两个重载；需要混合两个轴时，应按期望的布局顺序
    /// 连续调用，例如 `.frame(minWidth: 96).frame(height: 42)`。
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
        if !flexibleFrameConstraintsAreNondecreasing(
            minimum: minWidth,
            ideal: idealWidth,
            maximum: maxWidth
        ) || !flexibleFrameConstraintsAreNondecreasing(
            minimum: minHeight,
            ideal: idealHeight,
            maximum: maxHeight
        ) {
            // 对齐 SwiftUI：矛盾约束只记录非致命运行时问题，原始参数仍交给布局处理。
            flexibleFrameRuntimeLogger.fault(
                "Contradictory frame constraints specified."
            )
        }
        return IdealFlexibleFrameElement(
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

/// 判断单个轴上的最小、理想和最大约束是否按非递减顺序排列。
///
/// `nil` 的替换方式与 SwiftUI 当前实现一致，仅用于诊断，不会修改实际传给布局的参数。
internal func flexibleFrameConstraintsAreNondecreasing(
    minimum: CGFloat?,
    ideal: CGFloat?,
    maximum: CGFloat?
) -> Bool {
    let resolvedMinimum = minimum ?? -.infinity
    let resolvedIdeal = ideal ?? resolvedMinimum
    let resolvedMaximum = maximum ?? resolvedIdeal
    return resolvedMinimum <= resolvedIdeal && resolvedIdeal <= resolvedMaximum
}

/// 组合最小、理想和最大尺寸，并保留布局值传递的弹性框架。
private struct IdealFlexibleFrameElement: Layout, _LayoutValueProvidingElement {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 最小宽度；`nil` 表示未指定该约束。
    let minWidth: CGFloat?
    /// 理想宽度；`nil` 表示未指定该约束。
    let idealWidth: CGFloat?
    /// 最大宽度；`nil` 表示未指定该约束。
    let maxWidth: CGFloat?
    /// 最小高度；`nil` 表示未指定该约束。
    let minHeight: CGFloat?
    /// 理想高度；`nil` 表示未指定该约束。
    let idealHeight: CGFloat?
    /// 最大高度；`nil` 表示未指定该约束。
    let maxHeight: CGFloat?
    /// 内容在结果框架中的对齐方式。
    let alignment: Alignment

    /// 保存对齐方式并归一化各项尺寸；负值归零，`NaN` 转为未指定。
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

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }

    /// 本层不提供布局值，交由查询器继续访问子元素。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    /// 先约束子元素建议，再根据测量结果确定外框尺寸并复用测量节点。
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
        // 子元素只测量一次，后续对齐使用同一节点，避免二次测量改变理想尺寸。
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

    /// 设置最大尺寸的轴允许部分伸缩，其余轴继承子元素的尺寸弹性。
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

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 包装已测量节点，避免固定框架再次测量原始内容。
private struct FlexibleFramePrecomputedElement: Layout {
    /// 已完成测量的布局节点，供包装层直接复用。
    let layout: LayoutNode

    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }
    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 将未指定值及 `NaN` 保留为 `nil`，其余尺寸限制为非负数。
private func flexibleFrameDimension(_ value: CGFloat?) -> CGFloat? {
    guard let value, !value.isNaN else { return nil }
    return max(0, value)
}

/// 有限建议优先；仅在建议非有限时使用可选理想尺寸。
private func resolvedFlexibleFrameProposal(
    _ proposal: CGFloat,
    ideal: CGFloat?
) -> CGFloat {
    proposal.isFinite ? proposal : ideal ?? proposal
}

/// 将长度限制在最小值与最大值之间，缺省边界为零和正无穷。
private func clampFlexibleFrameDimension(
    _ value: CGFloat,
    minimum: CGFloat?,
    maximum: CGFloat?
) -> CGFloat {
    min(max(value, minimum ?? 0), maximum ?? .infinity)
}

/// 结合子元素尺寸与父建议计算外框长度；未设置上下限时保留内容尺寸。
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
