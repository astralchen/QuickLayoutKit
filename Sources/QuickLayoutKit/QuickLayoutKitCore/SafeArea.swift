import CoreGraphics
import QuickLayout
import UIKit

/// 布局可以忽略的安全区域类型。
public struct SafeAreaRegions: OptionSet, Sendable {

    /// 选项集合的原始位掩码。
    public let rawValue: UInt

    /// 使用原始位掩码创建安全区域选项集合。
    ///
    /// - Parameter rawValue: 安全区域类型的位掩码。
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// 包含视图或滚动视口提供的安全区域。
    public static let container = SafeAreaRegions(rawValue: 1 << 0)

    /// 软件键盘占用的安全区域。
    ///
    /// `QuickLayoutKeyboardAvoider` 管理 `QuickLayoutScrollView` 时会发布该区域。
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)

    /// QuickLayoutKit 已知的所有安全区域类型。
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

/// `safeAreaInset` 使用的垂直边缘。
public enum VerticalEdge: Sendable {
    /// 顶部边缘。
    case top

    /// 底部边缘。
    case bottom
}

/// `safeAreaInset` 使用的水平边缘。
public enum HorizontalEdge: Sendable {
    /// 前缘。
    case leading

    /// 后缘。
    case trailing
}

/// 测量 QuickLayout 层级时传递的安全区域值。
package struct QuickLayoutSafeAreaValues: Sendable {

    package var containerSize: CGSize
    private var physicalContainerInsets: QuickLayoutPhysicalInsets
    private var physicalKeyboardInsets: QuickLayoutPhysicalInsets

    package var containerInsets: EdgeInsets {
        get {
            physicalContainerInsets.directional(
                for: LayoutContext.layoutDirection
            )
        }
        set {
            physicalContainerInsets = QuickLayoutPhysicalInsets(
                newValue,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
    }

    package var keyboardInsets: EdgeInsets {
        get {
            physicalKeyboardInsets.directional(
                for: LayoutContext.layoutDirection
            )
        }
        set {
            physicalKeyboardInsets = QuickLayoutPhysicalInsets(
                newValue,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
    }

    package init(
        containerSize: CGSize,
        containerInsets: EdgeInsets = .zero,
        keyboardInsets: EdgeInsets = .zero
    ) {
        self.containerSize = containerSize
        physicalContainerInsets = QuickLayoutPhysicalInsets(
            containerInsets,
            layoutDirection: LayoutContext.layoutDirection
        )
        physicalKeyboardInsets = QuickLayoutPhysicalInsets(
            keyboardInsets,
            layoutDirection: LayoutContext.layoutDirection
        )
    }

    package init(
        containerSize: CGSize,
        physicalContainerInsets: UIEdgeInsets,
        physicalKeyboardInsets: UIEdgeInsets = .zero
    ) {
        self.containerSize = containerSize
        self.physicalContainerInsets = QuickLayoutPhysicalInsets(
            physicalContainerInsets
        )
        self.physicalKeyboardInsets = QuickLayoutPhysicalInsets(
            physicalKeyboardInsets
        )
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
        physicalContainerInsets
            .combined(with: physicalKeyboardInsets)
            .directional(for: LayoutContext.layoutDirection)
    }

    fileprivate func ignoring(
        _ regions: SafeAreaRegions,
        edges: EdgeSet
    ) -> QuickLayoutSafeAreaValues {
        var values = self
        if regions.contains(.container) {
            values.physicalContainerInsets.clear(
                edges,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
        if regions.contains(.keyboard) {
            values.physicalKeyboardInsets.clear(
                edges,
                layoutDirection: LayoutContext.layoutDirection
            )
        }
        return values
    }

    fileprivate func consuming(_ edges: EdgeSet) -> QuickLayoutSafeAreaValues {
        var values = self
        values.physicalContainerInsets.clear(
            edges,
            layoutDirection: LayoutContext.layoutDirection
        )
        values.physicalKeyboardInsets.clear(
            edges,
            layoutDirection: LayoutContext.layoutDirection
        )
        return values
    }
}

private struct QuickLayoutPhysicalInsets: Sendable {

    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    init(_ insets: UIEdgeInsets) {
        top = sanitizedSafeAreaValue(insets.top)
        left = sanitizedSafeAreaValue(insets.left)
        bottom = sanitizedSafeAreaValue(insets.bottom)
        right = sanitizedSafeAreaValue(insets.right)
    }

    init(
        _ insets: EdgeInsets,
        layoutDirection: LayoutDirection
    ) {
        let insets = insets.sanitized
        top = insets.top
        bottom = insets.bottom

        switch layoutDirection {
        case .leftToRight:
            left = insets.leading
            right = insets.trailing
        case .rightToLeft:
            left = insets.trailing
            right = insets.leading
        }
    }

    func combined(with other: QuickLayoutPhysicalInsets) -> Self {
        Self(
            UIEdgeInsets(
                top: max(top, other.top),
                left: max(left, other.left),
                bottom: max(bottom, other.bottom),
                right: max(right, other.right)
            )
        )
    }

    func directional(for layoutDirection: LayoutDirection) -> EdgeInsets {
        switch layoutDirection {
        case .leftToRight:
            EdgeInsets(
                top: top,
                leading: left,
                bottom: bottom,
                trailing: right
            )
        case .rightToLeft:
            EdgeInsets(
                top: top,
                leading: right,
                bottom: bottom,
                trailing: left
            )
        }
    }

    mutating func clear(
        _ edges: EdgeSet,
        layoutDirection: LayoutDirection
    ) {
        if edges.contains(.top) { top = 0 }
        if edges.contains(.bottom) { bottom = 0 }

        switch layoutDirection {
        case .leftToRight:
            if edges.contains(.leading) { left = 0 }
            if edges.contains(.trailing) { right = 0 }
        case .rightToLeft:
            if edges.contains(.leading) { right = 0 }
            if edges.contains(.trailing) { left = 0 }
        }
    }
}

/// QuickLayoutKit 宿主建立的任务局部安全区域作用域。
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

    /// 向元素可见的安全区域添加固定边距。
    ///
    /// 该修饰符先占用继承的安全区域边距，再添加指定间距并布局元素。
    /// 负值与非有限值按 `0` 处理。
    ///
    /// - Parameter insets: 添加到各个安全区域边缘的间距。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(_ insets: EdgeInsets) -> Element & Layout {
        SafeAreaPaddingElement(
            child: self,
            edges: .all,
            additionalInsets: insets.sanitizedSafeAreaPadding
        )
    }

    /// 向选定的安全区域边缘添加固定内边距。
    ///
    /// 传入 `nil` 不会添加额外间距，但仍会消费选中边缘继承的安全区域。这是
    /// QuickLayout 的稳定契约，不采用 SwiftUI 的平台默认间距。负值与非有限值按 `0`
    /// 处理。
    ///
    /// - Parameters:
    ///   - edges: 需要添加内边距的安全区域边缘。
    ///   - length: 额外间距；传入 `nil` 表示零。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(
        _ edges: EdgeSet = .all,
        _ length: CGFloat? = nil
    ) -> Element & Layout {
        let value = sanitizedSafeAreaPaddingValue(length ?? 0)
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

    /// 向所有安全区域边缘添加相同的固定内边距。
    ///
    /// 负值与非有限值按 `0` 处理。
    ///
    /// - Parameter length: 添加到每个安全区域边缘的间距。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(_ length: CGFloat) -> Element & Layout {
        safeAreaPadding(.all, length)
    }

    /// 在安全区域的垂直边缘放置内容并为其预留空间。
    ///
    /// `spacing` 为 `nil` 时按零处理。内容构建结果为 `nil` 时使用空布局，但仍消费并
    /// 预留选中边缘继承的安全区域。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的垂直边缘。
    ///   - alignment: 内容在垂直边缘上的水平对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
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

    /// 在安全区域的水平边缘放置内容并为其预留空间。
    ///
    /// `spacing` 为 `nil` 时按零处理。内容构建结果为 `nil` 时使用空布局，但仍消费并
    /// 预留选中边缘继承的安全区域。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的水平边缘。
    ///   - alignment: 内容在水平边缘上的垂直对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
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

    /// 在选定边缘上扩展元素可用的安全区域。
    ///
    /// - Parameters:
    ///   - regions: 要忽略的安全区域类型。
    ///   - edges: 要忽略安全区域的边缘。
    /// - Returns: 忽略指定安全区域后的元素。
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

    var sanitizedSafeAreaPadding: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaPaddingValue(top),
            leading: sanitizedSafeAreaPaddingValue(leading),
            bottom: sanitizedSafeAreaPaddingValue(bottom),
            trailing: sanitizedSafeAreaPaddingValue(trailing)
        )
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

private func sanitizedSafeAreaPaddingValue(_ value: CGFloat) -> CGFloat {
    max(0, sanitized(value))
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
