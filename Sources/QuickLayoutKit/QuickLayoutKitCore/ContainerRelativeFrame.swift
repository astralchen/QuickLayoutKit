import CoreGraphics
import QuickLayout
import UIKit

/// The container-size scope used by QuickLayoutKit layout hosts.
///
/// A task-local value keeps nested layout and off-main-thread proxy
/// measurements isolated from one another. When no host establishes a scope,
/// ``containerRelativeFrame`` falls back to the size proposed by its parent.
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

    /// Positions this element in a frame sized relative to the nearest
    /// QuickLayoutKit container.
    ///
    /// QuickLayoutKit establishes a container-size scope for
    /// ``QuickLayoutView``, ``QuickLayoutHostingController``, list cells, and
    /// ``QuickLayoutScrollView``. A scroll view uses its visible viewport,
    /// excluding adjusted content insets. Other hosts use their proposed size,
    /// excluding safe-area insets.
    ///
    /// When an element is laid out without a QuickLayoutKit host, the size
    /// proposed by its immediate parent is used as a fallback.
    ///
    /// - Parameters:
    ///   - axes: The axes whose frame lengths should match the container.
    ///   - alignment: The alignment of the element inside the resulting frame.
    /// - Returns: An element with container-relative dimensions.
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

    /// Positions this element in a frame that occupies a number of equal
    /// sections of the nearest QuickLayoutKit container.
    ///
    /// The resolved length uses the same formula as SwiftUI:
    ///
    /// ```swift
    /// let available = containerLength - spacing * CGFloat(count - 1)
    /// let column = available / CGFloat(count)
    /// let result = column * CGFloat(span) + spacing * CGFloat(span - 1)
    /// ```
    ///
    /// `count` is clamped to at least one, and `span` is clamped to the range
    /// `1...count`. A non-finite spacing is treated as zero.
    ///
    /// - Parameters:
    ///   - axes: The axes on which to divide the container.
    ///   - count: The number of equal sections in the container.
    ///   - span: The number of sections occupied by this element.
    ///   - spacing: The spacing between adjacent sections.
    ///   - alignment: The alignment of the element inside the resulting frame.
    /// - Returns: An element with container-relative dimensions.
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

    /// Positions this element in a frame whose length is calculated from the
    /// nearest QuickLayoutKit container.
    ///
    /// The closure runs once for each requested axis with a finite container
    /// length. Negative results are clamped to zero. Non-finite results leave
    /// that axis unconstrained.
    ///
    /// - Parameters:
    ///   - axes: The axes whose lengths should be calculated.
    ///   - alignment: The alignment of the element inside the resulting frame.
    ///   - length: A closure that receives the container length and current axis.
    /// - Returns: An element with container-relative dimensions.
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
