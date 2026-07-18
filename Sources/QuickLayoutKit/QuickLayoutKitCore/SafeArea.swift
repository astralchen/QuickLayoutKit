import CoreGraphics
import QuickLayout
import UIKit

/// The safe-area regions that a layout can ignore.
public struct SafeAreaRegions: OptionSet, Sendable {

    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The safe area supplied by the containing view or scroll viewport.
    public static let container = SafeAreaRegions(rawValue: 1 << 0)

    /// The safe area occupied by the software keyboard.
    ///
    /// `QuickLayoutKeyboardAvoider` publishes this region when it manages a
    /// `QuickLayoutScrollView`.
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)

    /// All safe-area regions known to QuickLayoutKit.
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

/// A vertical edge used by `safeAreaInset`.
public enum VerticalEdge: Sendable {
    case top
    case bottom
}

/// A horizontal edge used by `safeAreaInset`.
public enum HorizontalEdge: Sendable {
    case leading
    case trailing
}

/// Safe-area values propagated while a QuickLayout hierarchy is measured.
package struct QuickLayoutSafeAreaValues: Sendable {

    package var containerSize: CGSize
    package var containerInsets: EdgeInsets
    package var keyboardInsets: EdgeInsets

    package init(
        containerSize: CGSize,
        containerInsets: EdgeInsets = .zero,
        keyboardInsets: EdgeInsets = .zero
    ) {
        self.containerSize = containerSize
        self.containerInsets = containerInsets.sanitized
        self.keyboardInsets = keyboardInsets.sanitized
    }

    package var resolvedContainerSize: CGSize {
        let insets = effectiveInsets
        return CGSize(
            width: insetDimension(
                containerSize.width,
                before: insets.leading,
                after: insets.trailing
            ),
            height: insetDimension(
                containerSize.height,
                before: insets.top,
                after: insets.bottom
            )
        )
    }

    fileprivate var effectiveInsets: EdgeInsets {
        EdgeInsets(
            top: max(containerInsets.top, keyboardInsets.top),
            leading: max(containerInsets.leading, keyboardInsets.leading),
            bottom: max(containerInsets.bottom, keyboardInsets.bottom),
            trailing: max(containerInsets.trailing, keyboardInsets.trailing)
        )
    }

    fileprivate func ignoring(
        _ regions: SafeAreaRegions,
        edges: EdgeSet
    ) -> QuickLayoutSafeAreaValues {
        var values = self
        if regions.contains(.container) {
            values.containerInsets.clear(edges)
        }
        if regions.contains(.keyboard) {
            values.keyboardInsets.clear(edges)
        }
        return values
    }

    fileprivate func consuming(_ edges: EdgeSet) -> QuickLayoutSafeAreaValues {
        var values = self
        values.containerInsets.clear(edges)
        values.keyboardInsets.clear(edges)
        return values
    }
}

/// The task-local safe-area scope established by QuickLayoutKit hosts.
package enum QuickLayoutSafeAreaContext {

    @TaskLocal package static var current: QuickLayoutSafeAreaValues?

    package static func withValues<Result>(
        _ values: QuickLayoutSafeAreaValues,
        operation: () throws -> Result
    ) rethrows -> Result {
        try $current.withValue(values, operation: operation)
    }
}

public extension Element {

    /// Adds fixed insets to the safe area seen by this element.
    ///
    /// The modifier consumes the inherited safe-area insets and then adds the
    /// supplied amount of space before laying out the element.
    func safeAreaPadding(_ insets: EdgeInsets) -> Element & Layout {
        SafeAreaPaddingElement(
            child: self,
            edges: .all,
            additionalInsets: insets.sanitized
        )
    }

    /// Adds fixed padding to selected safe-area edges.
    ///
    /// Passing `nil` uses QuickLayoutKit's platform-style default of 16 points.
    ///
    /// - Parameters:
    ///   - edges: The safe-area edges to pad.
    ///   - length: The additional spacing, or `nil` for 16 points.
    func safeAreaPadding(
        _ edges: EdgeSet = .all,
        _ length: CGFloat? = nil
    ) -> Element & Layout {
        let value = sanitized(length ?? 16)
        return SafeAreaPaddingElement(
            child: self,
            edges: edges,
            additionalInsets: EdgeInsets(
                top: edges.contains(.top) ? value : 0,
                leading: edges.contains(.leading) ? value : 0,
                bottom: edges.contains(.bottom) ? value : 0,
                trailing: edges.contains(.trailing) ? value : 0
            )
        )
    }

    /// Adds the same fixed padding to every safe-area edge.
    func safeAreaPadding(_ length: CGFloat) -> Element & Layout {
        safeAreaPadding(.all, length)
    }

    /// Places content at a vertical safe-area edge and reserves space for it.
    ///
    /// A `nil` spacing value resolves to zero.
    func safeAreaInset(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @LayoutBuilder content: () -> Element?
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content() ?? EmptyLayout(),
            edge: edge.edge,
            alignment: Alignment(horizontal: alignment, vertical: edge.verticalAlignment),
            spacing: sanitized(spacing ?? 0)
        )
    }

    /// Places content at a horizontal safe-area edge and reserves space for it.
    ///
    /// A `nil` spacing value resolves to zero.
    func safeAreaInset(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @LayoutBuilder content: () -> Element?
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content() ?? EmptyLayout(),
            edge: edge.edge,
            alignment: Alignment(horizontal: edge.horizontalAlignment, vertical: alignment),
            spacing: sanitized(spacing ?? 0)
        )
    }

    /// Expands the safe area for this element on selected edges.
    func ignoresSafeArea(
        _ regions: SafeAreaRegions = .all,
        edges: EdgeSet = .all
    ) -> Element & Layout {
        IgnoresSafeAreaElement(child: self, regions: regions, edges: edges)
    }
}

private struct SafeAreaPaddingElement: Layout {

    let child: Element
    let edges: EdgeSet
    let additionalInsets: EdgeInsets

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let inheritedInsets = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let padding = EdgeInsets(
            top: edges.contains(.top) ? inheritedInsets.top + additionalInsets.top : 0,
            leading: edges.contains(.leading) ? inheritedInsets.leading + additionalInsets.leading : 0,
            bottom: edges.contains(.bottom) ? inheritedInsets.bottom + additionalInsets.bottom : 0,
            trailing: edges.contains(.trailing) ? inheritedInsets.trailing + additionalInsets.trailing : 0
        )

        let scopedChild = SafeAreaScopedElement(
            child: child,
            values: QuickLayoutSafeAreaContext.current?.consuming(edges)
        )
        return scopedChild
            .padding(padding)
            .quick_layoutThatFits(proposedSize)
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private struct SafeAreaInsetElement: Layout {

    let child: Element
    let inset: Element
    let edge: Edge
    let alignment: Alignment
    let spacing: CGFloat

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let inheritedInsets = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let consumedEdges = edge.edgeSet
        let childValues = QuickLayoutSafeAreaContext.current?.consuming(consumedEdges)
        let scopedInset = SafeAreaScopedElement(child: inset, values: childValues)
        let insetSize = scopedInset.sizeThatFits(insetProposal(for: proposedSize))
        let insetLength = insetSize.length(for: edge.axis)
        let inheritedLength = inheritedInsets.value(for: edge)
        let reservedLength = inheritedLength + insetLength + spacing

        let target = SafeAreaScopedElement(child: child, values: childValues)
            .padding(edge.edgeSet, reservedLength)
        let insetLayer = scopedInset
            .frame(
                width: edge.axis == .horizontal ? insetLength : nil,
                height: edge.axis == .vertical ? insetLength : nil
            )
            .padding(edge.edgeSet, inheritedLength)

        return target
            .overlay(alignment: alignment) {
                insetLayer
            }
            .quick_layoutThatFits(proposedSize)
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        inset.quick_extractViewsIntoArray(&views)
    }

    private func insetProposal(for proposedSize: CGSize) -> CGSize {
        switch edge.axis {
        case .horizontal:
            return CGSize(width: .infinity, height: proposedSize.height)
        case .vertical:
            return CGSize(width: proposedSize.width, height: .infinity)
        }
    }
}

private struct IgnoresSafeAreaElement: Layout {

    let child: Element
    let regions: SafeAreaRegions
    let edges: EdgeSet

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard let values = QuickLayoutSafeAreaContext.current else {
            return child.quick_layoutThatFits(proposedSize)
        }
        return QuickLayoutSafeAreaContext.withValues(
            values.ignoring(regions, edges: edges)
        ) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private struct SafeAreaScopedElement: Layout {

    let child: Element
    let values: QuickLayoutSafeAreaValues?

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard var values else {
            return child.quick_layoutThatFits(proposedSize)
        }
        values.containerSize = proposedSize.normalizedContainerSize
        return QuickLayoutSafeAreaContext.withValues(values) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private extension VerticalEdge {

    var edge: Edge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }

    var verticalAlignment: VerticalAlignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }
}

private extension HorizontalEdge {

    var edge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private extension Edge {

    var edgeSet: EdgeSet {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var axis: Axis {
        switch self {
        case .top, .bottom: .vertical
        case .leading, .trailing: .horizontal
        }
    }
}

private extension EdgeInsets {

    var sanitized: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaValue(top),
            leading: sanitizedSafeAreaValue(leading),
            bottom: sanitizedSafeAreaValue(bottom),
            trailing: sanitizedSafeAreaValue(trailing)
        )
    }

    mutating func clear(_ edges: EdgeSet) {
        if edges.contains(.top) { top = 0 }
        if edges.contains(.leading) { leading = 0 }
        if edges.contains(.bottom) { bottom = 0 }
        if edges.contains(.trailing) { trailing = 0 }
    }

    func value(for edge: Edge) -> CGFloat {
        switch edge {
        case .top: top
        case .bottom: bottom
        case .leading: leading
        case .trailing: trailing
        }
    }
}

private extension CGSize {

    var normalizedContainerSize: CGSize {
        CGSize(width: normalized(width), height: normalized(height))
    }

    func length(for axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: width
        case .vertical: height
        }
    }
}

private func sanitized(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

private func sanitizedSafeAreaValue(_ value: CGFloat) -> CGFloat {
    sanitized(value)
}

private func normalized(_ value: CGFloat) -> CGFloat {
    if value.isNaN {
        return 0
    }
    if value == .greatestFiniteMagnitude {
        return .infinity
    }
    return max(0, value)
}

private func insetDimension(
    _ length: CGFloat,
    before: CGFloat,
    after: CGFloat
) -> CGFloat {
    let length = normalized(length)
    guard length.isFinite else {
        return length
    }
    return max(0, length - before - after)
}
