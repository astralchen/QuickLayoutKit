import CoreGraphics
import QuickLayout
import UIKit

/// QuickLayoutKit 布局宿主使用的容器尺寸作用域。
///
/// 任务局部值使嵌套布局与非主线程代理测量彼此隔离。宿主未建立作用域时，
/// ``containerRelativeFrame`` 使用父元素建议的尺寸作为备用值。
package enum QuickLayoutContainerRelativeFrameContext {

    @TaskLocal package static var containerSize: CGSize?

    package static func withContainerSize<Result>(
        _ size: CGSize,
        operation: () throws -> Result
    ) rethrows -> Result {
        try $containerSize.withValue(size, operation: operation)
    }
}

public extension Element {

    /// 将元素放置在相对于最近 QuickLayoutKit 容器确定尺寸的框架中。
    ///
    /// QuickLayoutKit 会为 ``QuickLayoutView``、``QuickLayoutHostingController``、列表单元格
    /// 和 ``QuickLayoutScrollView`` 建立容器尺寸作用域。滚动视图使用扣除调整后内容边距的
    /// 可见视口；其他宿主使用扣除安全区域边距后的建议尺寸。
    ///
    /// 在没有 QuickLayoutKit 宿主的情况下布局元素时，该方法使用直接父元素建议的尺寸。
    ///
    /// - Parameters:
    ///   - axes: 框架长度与容器匹配的轴。
    ///   - alignment: 元素在结果框架中的对齐方式。
    /// - Returns: 具有容器相对尺寸的元素。
    func containerRelativeFrame(
        _ axes: AxisSet,
        alignment: Alignment = .center
    ) -> Element & Layout {
        ContainerRelativeFrameElement(
            child: self,
            axes: axes,
            alignment: alignment,
            length: { containerLength, _ in containerLength }
        )
    }

    /// 将元素放置在占据最近 QuickLayoutKit 容器若干等分的框架中。
    ///
    /// 该方法使用与 SwiftUI 相同的公式计算长度：
    ///
    /// ```swift
    /// let available = containerLength - spacing * CGFloat(count - 1)
    /// let column = available / CGFloat(count)
    /// let result = column * CGFloat(span) + spacing * CGFloat(span - 1)
    /// ```
    ///
    /// `count` 的最小值为一，`span` 会限制在 `1...count` 范围内。非有限间距按零处理。
    ///
    /// - Parameters:
    ///   - axes: 对容器进行等分的轴。
    ///   - count: 容器在相应轴上的等分数量。
    ///   - span: 元素占据的等分数量。
    ///   - spacing: 相邻等分之间的间距。
    ///   - alignment: 元素在结果框架中的对齐方式。
    /// - Returns: 具有容器相对尺寸的元素。
    func containerRelativeFrame(
        _ axes: AxisSet,
        count: Int,
        span: Int = 1,
        spacing: CGFloat,
        alignment: Alignment = .center
    ) -> Element & Layout {
        let resolvedCount = max(1, count)
        let resolvedSpan = min(max(1, span), resolvedCount)
        let resolvedSpacing = spacing.isFinite ? spacing : 0

        return ContainerRelativeFrameElement(
            child: self,
            axes: axes,
            alignment: alignment
        ) { containerLength, _ in
            let totalSpacing = resolvedSpacing * CGFloat(resolvedCount - 1)
            let sectionLength = (containerLength - totalSpacing) / CGFloat(resolvedCount)
            return sectionLength * CGFloat(resolvedSpan)
                + resolvedSpacing * CGFloat(resolvedSpan - 1)
        }
    }

    /// 将元素放置在长度根据最近 QuickLayoutKit 容器计算得出的框架中。
    ///
    /// 对于每个已请求且容器长度有限的轴，该方法都会调用一次闭包。负数结果按零处理；
    /// 非有限结果表示不约束相应轴。
    ///
    /// - Parameters:
    ///   - axes: 需要计算长度的轴。
    ///   - alignment: 元素在结果框架中的对齐方式。
    ///   - length: 接收容器长度和当前轴，并返回元素长度的闭包。
    /// - Returns: 具有容器相对尺寸的元素。
    func containerRelativeFrame(
        _ axes: AxisSet,
        alignment: Alignment = .center,
        _ length: @escaping @Sendable (CGFloat, Axis) -> CGFloat
    ) -> Element & Layout {
        ContainerRelativeFrameElement(
            child: self,
            axes: axes,
            alignment: alignment,
            length: length
        )
    }
}

private struct ContainerRelativeFrameElement: Layout {

    let child: Element
    let axes: AxisSet
    let alignment: Alignment
    let length: @Sendable (CGFloat, Axis) -> CGFloat

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axes.contains(axis.axisSet) ? .fixedSize : child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let scopedContainerSize = QuickLayoutSafeAreaContext.current?.resolvedContainerSize
            ?? QuickLayoutContainerRelativeFrameContext.containerSize
        let width = resolvedLength(
            for: .horizontal,
            scopedContainerSize: scopedContainerSize,
            proposedSize: proposedSize
        )
        let height = resolvedLength(
            for: .vertical,
            scopedContainerSize: scopedContainerSize,
            proposedSize: proposedSize
        )

        return child
            .frame(width: width, height: height, alignment: alignment)
            .quick_layoutThatFits(proposedSize)
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    private func resolvedLength(
        for axis: Axis,
        scopedContainerSize: CGSize?,
        proposedSize: CGSize
    ) -> CGFloat? {
        guard axes.contains(axis.axisSet) else {
            return nil
        }

        let containerLength: CGFloat
        if let scopedContainerSize {
            containerLength = scopedContainerSize.length(for: axis)
        } else {
            containerLength = proposedSize.length(for: axis)
        }

        guard containerLength.isFinite else {
            return nil
        }

        let result = length(containerLength, axis)
        guard result.isFinite else {
            return nil
        }
        return max(0, result)
    }
}

private extension Axis {

    var axisSet: AxisSet {
        switch self {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        }
    }
}

private extension CGSize {

    func length(for axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return width
        case .vertical:
            return height
        }
    }
}
