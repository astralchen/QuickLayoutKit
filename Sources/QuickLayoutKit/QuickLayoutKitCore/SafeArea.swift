import CoreGraphics
import QuickLayout
import UIKit

/// 几何观察标记在放置后读取继承区域；保持 Core 与 UIKit 宿主模块之间的依赖方向。
@MainActor
package protocol QuickLayoutSafeAreaGeometryObserver: AnyObject {
    var quickLayoutSafeAreaGeometry: (@MainActor () -> UIEdgeInsets?)? { get set }
}

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
    /// `QuickLayoutView` 启用 `quickLayoutKeyboardSafeAreaBehavior` 时会自动发布该区域；
    /// `QuickLayoutKeyboardAvoider` 管理 `QuickLayoutScrollView` 时也会发布该区域。
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
package struct QuickLayoutSafeAreaValues: Sendable, Equatable {

    /// 本层收到的完整容器尺寸，尚未扣除有效安全区域。
    package var containerSize: CGSize
    /// 当前坐标空间属于哪个滚动主轴；该轴上的局部视口不能再次恢复外层安全区。
    package var scrollContentAxis: Axis?
    /// 按物理左右方向保存的容器安全区域，避免局部 RTL 切换重复镜像。
    private var physicalContainerInsets: QuickLayoutPhysicalInsets
    /// 按物理左右方向保存的键盘占用区域。
    private var physicalKeyboardInsets: QuickLayoutPhysicalInsets

    // 已由外层 padding 消费的区域仍保留几何意义，供后代 ignoresSafeArea 扩展。
    private var consumedContainerInsets = QuickLayoutPhysicalInsets(UIEdgeInsets.zero)
    private var consumedKeyboardInsets = QuickLayoutPhysicalInsets(UIEdgeInsets.zero)
    private var ignoredContainerInsets = QuickLayoutPhysicalInsets(UIEdgeInsets.zero)
    private var ignoredKeyboardInsets = QuickLayoutPhysicalInsets(UIEdgeInsets.zero)

    /// 按当前布局方向读写的容器安全区域边距。
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

    /// 按当前布局方向读写的键盘安全区域边距。
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

    /// 将方向性边距按当前布局方向转为物理存储。
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

    /// 直接保存 UIKit 物理边距，避免在宿主边界丢失左右语义。
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

    /// 扣除逐边合并的有效安全区域后可用的容器尺寸。
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

    /// 容器与键盘边距逐边取较大值后的方向性结果，避免重复叠加。
    package var effectiveInsets: EdgeInsets {
        physicalContainerInsets
            .combined(with: physicalKeyboardInsets)
            .directional(for: LayoutContext.layoutDirection)
    }

    /// 显式忽略容器区域的物理边缘标记，供滚动视口撤销 UIKit 的自动补偿。
    package var ignoredPhysicalContainerEdges: UIEdgeInsets {
        UIEdgeInsets(top: ignoredContainerInsets.top, left: ignoredContainerInsets.left,
                     bottom: ignoredContainerInsets.bottom, right: ignoredContainerInsets.right)
    }

    /// 当前安全边界相对完整参照矩形的位置，供 UIKit 宿主转换实际坐标。
    package var physicalSafeBoundaryInsets: UIEdgeInsets {
        UIEdgeInsets(top: max(physicalContainerInsets.top + consumedContainerInsets.top,
                              physicalKeyboardInsets.top + consumedKeyboardInsets.top),
                     left: max(physicalContainerInsets.left + consumedContainerInsets.left,
                               physicalKeyboardInsets.left + consumedKeyboardInsets.left),
                     bottom: max(physicalContainerInsets.bottom + consumedContainerInsets.bottom,
                                 physicalKeyboardInsets.bottom + consumedKeyboardInsets.bottom),
                     right: max(physicalContainerInsets.right + consumedContainerInsets.right,
                                physicalKeyboardInsets.right + consumedKeyboardInsets.right))
    }

    /// 仅清除指定区域和边缘，返回不修改原值的上下文副本。
    package func ignoring(
        _ regions: SafeAreaRegions,
        edges: EdgeSet
    ) -> QuickLayoutSafeAreaValues {
        var values = self
        if regions.contains(.container) {
            values.ignoredContainerInsets.add(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1), on: edges)
            values.physicalContainerInsets.clear(edges, layoutDirection: LayoutContext.layoutDirection)
            values.consumedContainerInsets.clear(edges, layoutDirection: LayoutContext.layoutDirection)
        }
        if regions.contains(.keyboard) {
            values.ignoredKeyboardInsets.add(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1), on: edges)
            values.physicalKeyboardInsets.clear(edges, layoutDirection: LayoutContext.layoutDirection)
            values.consumedKeyboardInsets.clear(edges, layoutDirection: LayoutContext.layoutDirection)
        }
        return values
    }

    /// 子宿主独立重排时，按真实几何投影父级安全区，避免重新消费父级已让出的区域。
    /// 只有贴着安全边界的子宿主继承可恢复的外延；普通 padding 不会被误当作安全区。
    package func projected(from bounds: CGRect, into rect: CGRect, keyboard: UIEdgeInsets) -> QuickLayoutSafeAreaValues {
        // 键盘覆盖底部容器区域时，两种约束仍需同时保留；内层只忽略键盘后，
        // Home 指示器对应的容器安全区必须继续生效。
        let combinedBoundary = bounds.inset(by: physicalSafeBoundaryInsets)
        func project(_ pending: QuickLayoutPhysicalInsets, _ consumed: QuickLayoutPhysicalInsets,
                     _ ignored: QuickLayoutPhysicalInsets)
            -> (QuickLayoutPhysicalInsets, QuickLayoutPhysicalInsets) {
            let top = bounds.minY + pending.top + consumed.top
            let left = bounds.minX + pending.left + consumed.left
            let bottom = bounds.maxY - pending.bottom - consumed.bottom
            let right = bounds.maxX - pending.right - consumed.right
            let remaining = UIEdgeInsets(
                top: ignored.top > 0 ? 0 : min(pending.top + consumed.top, rect.height, max(0, top - rect.minY)),
                left: ignored.left > 0 ? 0 : min(pending.left + consumed.left, rect.width, max(0, left - rect.minX)),
                bottom: ignored.bottom > 0 ? 0 : min(pending.bottom + consumed.bottom, rect.height, max(0, rect.maxY - bottom)),
                right: ignored.right > 0 ? 0 : min(pending.right + consumed.right, rect.width, max(0, rect.maxX - right)))
            let expansion = UIEdgeInsets(
                top: abs(rect.minY - top) < 0.5 || abs(rect.minY - combinedBoundary.minY) < 0.5 ? consumed.top : 0,
                left: abs(rect.minX - left) < 0.5 || abs(rect.minX - combinedBoundary.minX) < 0.5 ? consumed.left : 0,
                bottom: abs(rect.maxY - bottom) < 0.5 || abs(rect.maxY - combinedBoundary.maxY) < 0.5 ? consumed.bottom : 0,
                right: abs(rect.maxX - right) < 0.5 || abs(rect.maxX - combinedBoundary.maxX) < 0.5 ? consumed.right : 0)
            return (QuickLayoutPhysicalInsets(remaining), QuickLayoutPhysicalInsets(expansion))
        }
        var result = self
        result.containerSize = rect.size
        (result.physicalContainerInsets, result.consumedContainerInsets) = project(
            physicalContainerInsets, consumedContainerInsets, ignoredContainerInsets)
        (result.physicalKeyboardInsets, result.consumedKeyboardInsets) = project(
            physicalKeyboardInsets, consumedKeyboardInsets, ignoredKeyboardInsets)
        // 子宿主可以收到自己的键盘事件；只合并实际相交量，容器安全区仍以父级投影为准。
        result.physicalKeyboardInsets = result.physicalKeyboardInsets.combined(with: QuickLayoutPhysicalInsets(
            UIEdgeInsets(top: ignoredKeyboardInsets.top > 0 ? 0 : keyboard.top,
                         left: ignoredKeyboardInsets.left > 0 ? 0 : keyboard.left,
                         bottom: ignoredKeyboardInsets.bottom > 0 ? 0 : keyboard.bottom,
                         right: ignoredKeyboardInsets.right > 0 ? 0 : keyboard.right)))
        return result
    }

    /// 忽略区域时只恢复已消费且不再受其他区域遮挡的边距。
    package func expansion(ignoring regions: SafeAreaRegions, edges: EdgeSet) -> EdgeInsets {
        let before = consumedContainerInsets.combined(with: consumedKeyboardInsets)
            .directional(for: LayoutContext.layoutDirection)
        let remaining = ignoring(regions, edges: edges)
        let after = remaining.consumedContainerInsets.combined(with: remaining.consumedKeyboardInsets)
            .directional(for: LayoutContext.layoutDirection)
        return EdgeInsets(top: before.top - after.top, leading: before.leading - after.leading,
                          bottom: before.bottom - after.bottom, trailing: before.trailing - after.trailing)
    }

    /// 同时消费指定边缘上的容器与键盘安全区域，避免后代重复避让。
    package func consuming(_ edges: EdgeSet, additionalInsets: EdgeInsets = .zero) -> QuickLayoutSafeAreaValues {
        var values = self
        values.consumedContainerInsets.add(containerInsets, on: edges)
        values.consumedContainerInsets.add(additionalInsets, on: edges)
        values.consumedKeyboardInsets.add(keyboardInsets, on: edges)
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

    /// 滚动宿主只消费已由 adjustedContentInset 实际承担的部分；.never 下的剩余区域仍须避让。
    package func consumingAppliedInsets(_ applied: UIEdgeInsets) -> QuickLayoutSafeAreaValues {
        func split(_ value: QuickLayoutPhysicalInsets) -> (QuickLayoutPhysicalInsets, QuickLayoutPhysicalInsets) {
            let consumed = UIEdgeInsets(top: min(value.top, max(0, applied.top)),
                                        left: min(value.left, max(0, applied.left)),
                                        bottom: min(value.bottom, max(0, applied.bottom)),
                                        right: min(value.right, max(0, applied.right)))
            return (QuickLayoutPhysicalInsets(UIEdgeInsets(top: value.top - consumed.top,
                left: value.left - consumed.left, bottom: value.bottom - consumed.bottom,
                right: value.right - consumed.right)), QuickLayoutPhysicalInsets(consumed))
        }
        var values = self
        (values.physicalContainerInsets, values.consumedContainerInsets) = split(physicalContainerInsets)
        (values.physicalKeyboardInsets, values.consumedKeyboardInsets) = split(physicalKeyboardInsets)
        return values
    }
}

/// 普通宿主默认消费剩余安全区；显式 padding 只再添加调用方要求的额外间距。
/// 保留已消费的区域，使后代可以按边、按区域恢复布局空间。
package struct QuickLayoutDefaultSafeAreaElement: Layout {
    package let child: Element
    package init(child: Element) { self.child = child }
    package func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard let values = QuickLayoutSafeAreaContext.current else { return child.quick_layoutThatFits(proposedSize) }
        var consumed = values.consuming(.all)
        consumed.containerSize = values.resolvedContainerSize
        // 默认包装保留有限视口参照；滚动轴的无界内容提议不能覆盖容器尺寸。
        return SafeAreaScopedElement(child: child, values: consumed, preservesContainerSize: true)
            .padding(values.effectiveInsets).quick_layoutThatFits(proposedSize)
    }
    package func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    package func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    package func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
}

/// 滚动视口恢复外层已消费的区域，用内容 inset 避让；报告尺寸仍参与安全区内的父布局。
package struct QuickLayoutSafeAreaScrollViewport: Layout {
    package let child: Element
    package let expansion: EdgeInsets
    package init(child: Element, expansion: EdgeInsets) {
        self.child = child
        self.expansion = expansion
    }
    package func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let expanded = CGSize(width: proposedSize.width + expansion.leading + expansion.trailing,
                              height: proposedSize.height + expansion.top + expansion.bottom)
        let node = child.quick_layoutThatFits(expanded)
        return SafeAreaMeasuredElement(node: node)
            .frame(width: max(0, node.size.width - expansion.leading - expansion.trailing),
                   height: max(0, node.size.height - expansion.top - expansion.bottom), alignment: .topLeading)
            .offset(x: -expansion.leading, y: -expansion.top)
            .quick_layoutThatFits(proposedSize)
    }
    package func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    package func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    package func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
}

/// 按物理边保存安全区域，以便跨局部布局方向稳定传递。
private struct QuickLayoutPhysicalInsets: Sendable, Equatable {

    /// 物理顶部边距。
    var top: CGFloat
    /// 物理左侧边距。
    var left: CGFloat
    /// 物理底部边距。
    var bottom: CGFloat
    /// 物理右侧边距。
    var right: CGFloat

    /// 保存 UIKit 边距并将非有限分量归零，保留有限负值。
    init(_ insets: UIEdgeInsets) {
        top = sanitizedSafeAreaValue(insets.top)
        left = sanitizedSafeAreaValue(insets.left)
        bottom = sanitizedSafeAreaValue(insets.bottom)
        right = sanitizedSafeAreaValue(insets.right)
    }

    /// 按指定方向将前后边距映射到物理左右边距。
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

    /// 逐边取较大值合并两个区域，重叠部分不重复累加。
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

    /// 按请求的布局方向将物理左右边距转为前后边距。
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

    /// 将已消费的方向性边距累加到物理边，保持局部 RTL 切换时的方向。
    mutating func add(_ insets: EdgeInsets, on edges: EdgeSet) {
        let selected = EdgeInsets(top: edges.contains(.top) ? insets.top : 0,
                                  leading: edges.contains(.leading) ? insets.leading : 0,
                                  bottom: edges.contains(.bottom) ? insets.bottom : 0,
                                  trailing: edges.contains(.trailing) ? insets.trailing : 0)
        let physical = Self(selected, layoutDirection: LayoutContext.layoutDirection)
        top += physical.top
        left += physical.left
        bottom += physical.bottom
        right += physical.right
    }

    /// 将指定方向性边缘映射为物理边并清零。
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

    /// 当前测量继承的安全区域；没有宿主发布时为 `nil`。
    @TaskLocal package static var current: QuickLayoutSafeAreaValues?
    /// 双轴 resizable 会跳过 UIView 测量，因此在布局包装器边界记录直接子宿主的继承值。
    @TaskLocal package static var capture: (@MainActor @Sendable ([UIView], QuickLayoutSafeAreaValues) -> Void)?
    @TaskLocal package static var touchingEdges: (@MainActor @Sendable ([UIView], QuickLayoutSafeAreaValues) -> EdgeSet)?

    package static func touchingEdges(of element: Element, values: QuickLayoutSafeAreaValues) -> EdgeSet {
        guard let touchingEdges else { return [] }
        var views: [UIView] = []
        element.quick_extractViewsIntoArray(&views)
        return MainActor.assumeIsolated { touchingEdges(views, values) }
    }

    static func captureInheritance(of element: Element, values: QuickLayoutSafeAreaValues) {
        guard let capture else { return }
        var views: [UIView] = []
        element.quick_extractViewsIntoArray(&views)
        MainActor.assumeIsolated { capture(views, values) }
    }

    /// 临时发布安全区域上下文，闭包返回或抛错时恢复外层值。
    package static func withValues<Result>(
        _ values: QuickLayoutSafeAreaValues,
        operation: () throws -> Result
    ) rethrows -> Result {
        try $current.withValue(values, operation: operation)
    }
}

/// 显式支持完整滚动视口的元素适配边界。普通布局仍使用几何预留。
package protocol QuickLayoutSafeAreaInsetTarget: Element {
    var quickLayoutAcceptsSafeAreaInset: Bool { get }
    func quick_layoutWithSafeAreaInset(
        _ proposedSize: CGSize,
        reservation: QuickLayoutSafeAreaInsetReservation
    ) -> LayoutNode
}

/// 相对于当前元素完整边界的最小遮挡量；物理存储避免局部 RTL 重复镜像。
package struct QuickLayoutSafeAreaInsetReservation: Sendable, Equatable {
    package var insets: UIEdgeInsets
    package var selected: UIEdgeInsets
    package var ignoredContainerEdges: UIEdgeInsets = .zero

    package init(insets: UIEdgeInsets = .zero, selected: UIEdgeInsets = .zero) {
        self.insets = insets
        self.selected = selected
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
    /// 额外间距默认为零，但仍会消费选中边缘继承的安全区域。
    /// 不采用 SwiftUI 的平台默认间距。负值与非有限值按 `0` 处理。
    ///
    /// - Parameters:
    ///   - edges: 需要添加内边距的安全区域边缘。
    ///   - length: 额外间距，默认为 0。
    /// - Returns: 应用安全区域内边距后的元素。
    func safeAreaPadding(
        _ edges: EdgeSet = .all,
        _ length: CGFloat = 0
    ) -> Element & Layout {
        let value = sanitizedSafeAreaPaddingValue(length)
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
    /// 间距默认为零。构建器将可选内容的 `nil` 和未命中的条件分支转换为空布局，
    /// 此时仍消费并预留选中边缘继承的安全区域，显式间距也仍参与布局。
    /// 直接修饰声明式 `ScrollView`（可包含连续的 `contentMargins` / `safeAreaInset`）时，
    /// 保留完整滚动视口并调整内容及指示器边距；其他元素按几何尺寸预留空间。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的垂直边缘。
    ///   - alignment: 内容在垂直边缘上的水平对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距，默认为 0；允许有限负值，非有限值按 0 处理。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
    func safeAreaInset(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat = 0,
        @LayoutBuilder content: () -> Layout
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content(),
            edge: edge.edge,
            alignment: Alignment(horizontal: alignment, vertical: edge.verticalAlignment),
            spacing: sanitized(spacing)
        )
    }

    /// 在安全区域的水平边缘放置内容并为其预留空间。
    ///
    /// 间距默认为零。构建器将可选内容的 `nil` 和未命中的条件分支转换为空布局，
    /// 此时仍消费并预留选中边缘继承的安全区域，显式间距也仍参与布局。
    /// 声明式滚动适配的包装顺序和行为与垂直重载相同。
    ///
    /// - Parameters:
    ///   - edge: 放置内容的水平边缘。
    ///   - alignment: 内容在水平边缘上的垂直对齐方式。
    ///   - spacing: 插入内容与主体内容之间的间距，默认为 0；允许有限负值，非有限值按 0 处理。
    ///   - content: 生成插入内容的构建器。
    /// - Returns: 在指定边缘插入内容后的元素。
    func safeAreaInset(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: CGFloat = 0,
        @LayoutBuilder content: () -> Layout
    ) -> Element & Layout {
        SafeAreaInsetElement(
            child: self,
            inset: content(),
            edge: edge.edge,
            alignment: Alignment(horizontal: edge.horizontalAlignment, vertical: alignment),
            spacing: sanitized(spacing)
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

/// 消费继承安全区域并叠加显式内边距的布局包装器。
private struct SafeAreaPaddingElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 本层需要消费并添加内边距的边缘。
    let edges: EdgeSet
    /// 已归一化为有限非负值的额外边距。
    let additionalInsets: EdgeInsets

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 在所选边缘消费继承区域后包裹 padding，避免子元素再次消费同一边距。
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
            values: QuickLayoutSafeAreaContext.current?.consuming(edges, additionalInsets: additionalInsets)
        )
        return scopedChild
            .padding(padding)
            .quick_layoutThatFits(proposedSize)
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 先测量边缘插入内容，再为主体预留安全区域和插入长度的包装器。
private struct SafeAreaInsetElement: Layout, QuickLayoutSafeAreaInsetTarget {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 布局于选定边缘的插入内容。
    let inset: Element
    /// 插入内容所在的单一边缘。
    let edge: Edge
    /// 内容在结果框架中的对齐方式。
    let alignment: Alignment
    /// 插入内容与主体之间的间距；允许有限负值。
    let spacing: CGFloat

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 消费目标边缘，测量插入内容，并叠放预留空间后的主体与边缘内容。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        if quickLayoutAcceptsSafeAreaInset {
            let inherited = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
            let physical = QuickLayoutPhysicalInsets(inherited, layoutDirection: LayoutContext.layoutDirection)
            return quick_layoutWithSafeAreaInset(proposedSize, reservation: .init(
                insets: UIEdgeInsets(top: physical.top, left: physical.left, bottom: physical.bottom, right: physical.right)
            ))
        }
        let inheritedInsets = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let consumedEdges = edge.edgeSet
        let childValues = QuickLayoutSafeAreaContext.current?.consuming(consumedEdges)
        let scopedInset = SafeAreaScopedElement(child: inset, values: childValues)
        let insetSize = scopedInset.sizeThatFits(insetProposal(for: proposedSize))
        let insetLength = insetSize.length(for: edge.axis)
        let inheritedLength = inheritedInsets.value(for: edge)
        let reservedLength = inheritedLength + insetLength + spacing

        let additional = EdgeInsets(top: edge == .top ? insetLength + spacing : 0,
                                    leading: edge == .leading ? insetLength + spacing : 0,
                                    bottom: edge == .bottom ? insetLength + spacing : 0,
                                    trailing: edge == .trailing ? insetLength + spacing : 0)
        let targetValues = QuickLayoutSafeAreaContext.current?.consuming(consumedEdges, additionalInsets: additional)
        let target = SafeAreaScopedElement(child: child, values: targetValues)
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

    var quickLayoutAcceptsSafeAreaInset: Bool {
        (child as? any QuickLayoutSafeAreaInsetTarget)?.quickLayoutAcceptsSafeAreaInset == true
    }

    /// 保留滚动视口外框，逐层扩展其可见内容边界；外层插入内容先占用区域。
    func quick_layoutWithSafeAreaInset(
        _ proposedSize: CGSize,
        reservation: QuickLayoutSafeAreaInsetReservation
    ) -> LayoutNode {
        guard let target = child as? any QuickLayoutSafeAreaInsetTarget else {
            return quick_layoutThatFits(proposedSize)
        }
        let values = QuickLayoutSafeAreaValues(containerSize: proposedSize, physicalContainerInsets: reservation.insets)
        let effective = values.effectiveInsets
        let inherited = effective.value(for: edge)
        let crossEdges: EdgeSet = edge.axis == .vertical ? .horizontal : .vertical
        let crossPadding = EdgeInsets(
            top: edge.axis == .horizontal ? effective.top : 0,
            leading: edge.axis == .vertical ? effective.leading : 0,
            bottom: edge.axis == .horizontal ? effective.bottom : 0,
            trailing: edge.axis == .vertical ? effective.trailing : 0
        )
        let scopedInset = SafeAreaScopedElement(child: inset, values: values.consuming(edge.edgeSet.union(crossEdges)))
        let available = CGSize(width: max(0, proposedSize.width - crossPadding.leading - crossPadding.trailing),
                               height: max(0, proposedSize.height - crossPadding.top - crossPadding.bottom))
        let length = scopedInset.sizeThatFits(insetProposal(for: available)).length(for: edge.axis)
        var next = reservation
        let isRTL = LayoutContext.layoutDirection == .rightToLeft
        switch edge {
        case .top: next.insets.top = inherited + length + spacing; next.selected.top = 1
        case .bottom: next.insets.bottom = inherited + length + spacing; next.selected.bottom = 1
        case .leading where !isRTL, .trailing where isRTL:
            next.insets.left = inherited + length + spacing; next.selected.left = 1
        case .leading, .trailing:
            next.insets.right = inherited + length + spacing; next.selected.right = 1
        }
        let node = target.quick_layoutWithSafeAreaInset(proposedSize, reservation: next)
        return SafeAreaMeasuredElement(node: node)
            .overlay(alignment: alignment) {
                scopedInset
                    .frame(width: edge.axis == .horizontal ? length : nil,
                           height: edge.axis == .vertical ? length : nil)
                    .padding(crossPadding)
                    .padding(edge.edgeSet, inherited)
            }
            .quick_layoutThatFits(proposedSize)
    }

    /// 同时提取主体和插入内容的视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        inset.quick_extractViewsIntoArray(&views)
    }

    /// 沿插入轴使用无界建议，交叉轴保留父布局约束。
    private func insetProposal(for proposedSize: CGSize) -> CGSize {
        switch edge.axis {
        case .horizontal:
            return CGSize(width: .infinity, height: proposedSize.height)
        case .vertical:
            return CGSize(width: proposedSize.width, height: .infinity)
        }
    }
}

/// 清除指定区域，并在放置阶段恢复已消费的边距。
private struct IgnoresSafeAreaElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 需要忽略的安全区域种类。
    let regions: SafeAreaRegions
    /// 需要从指定区域中清除的边缘。
    let edges: EdgeSet

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 报告原建议下的尺寸，使用扩展建议放置子元素；前缘偏移随 RTL 镜像。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard let values = QuickLayoutSafeAreaContext.current else {
            return child.quick_layoutThatFits(proposedSize)
        }
        let inheritedExpansion = values.expansion(ignoring: regions, edges: edges)
        // 无界滚动轴没有可贴合的远端安全边界，不能据此移动固定尺寸的内容。
        let ignored = values.ignoring(regions, edges: edges)
        QuickLayoutSafeAreaContext.captureInheritance(of: child, values: ignored)
        return QuickLayoutSafeAreaContext.withValues(ignored) {
            let measured = child.quick_layoutThatFits(proposedSize)
            // 未铺满建议的固定尺寸内容没有接触该轴的安全边界，忽略安全区不应将它平移。
            let fillsWidth = proposedSize.width.isFinite && measured.size.width >= proposedSize.width
            let fillsHeight = proposedSize.height.isFinite && measured.size.height >= proposedSize.height
            let touches = QuickLayoutSafeAreaContext.touchingEdges(of: child, values: values)
            let spansWidth = proposedSize.width >= values.containerSize.width
            let spansHeight = proposedSize.height >= values.containerSize.height
            let expansion = EdgeInsets(top: fillsHeight && (spansHeight || touches.contains(.top)) ? inheritedExpansion.top : 0,
                                       leading: fillsWidth && (spansWidth || touches.contains(.leading)) ? inheritedExpansion.leading : 0,
                                       bottom: fillsHeight && (spansHeight || touches.contains(.bottom)) ? inheritedExpansion.bottom : 0,
                                       trailing: fillsWidth && (spansWidth || touches.contains(.trailing)) ? inheritedExpansion.trailing : 0)
            guard expansion.top != 0 || expansion.leading != 0
                    || expansion.bottom != 0 || expansion.trailing != 0 else {
                return measured
            }
            let expanded = CGSize(
                width: proposedSize.width + expansion.leading + expansion.trailing,
                height: proposedSize.height + expansion.top + expansion.bottom
            )
            let placed = child.quick_layoutThatFits(expanded)
            return SafeAreaMeasuredElement(node: placed)
                .frame(width: measured.size.width, height: measured.size.height, alignment: .topLeading)
                .offset(x: -expansion.leading, y: -expansion.top)
                .quick_layoutThatFits(proposedSize)
        }
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 保留扩展建议测得的节点，同时由外层框架报告未扩展尺寸。
private struct SafeAreaMeasuredElement: Layout {
    let node: LayoutNode
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 在子元素测量时重新发布安全区域，并同步本层容器尺寸。
private struct SafeAreaScopedElement: Layout {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 待传给后代的区域副本；`nil` 表示无需建立新作用域。
    let values: QuickLayoutSafeAreaValues?
    var preservesContainerSize = false

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 以本层建议更新容器尺寸，并在该安全区域作用域中测量内容。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard var values else {
            return child.quick_layoutThatFits(proposedSize)
        }
        if !preservesContainerSize { values.containerSize = proposedSize.normalizedContainerSize }
        QuickLayoutSafeAreaContext.captureInheritance(of: child, values: values)
        return QuickLayoutSafeAreaContext.withValues(values) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private extension VerticalEdge {

    /// 与垂直边缘对应的通用布局边缘。
    var edge: Edge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// 使插入内容贴合该边缘的垂直对齐方式。
    var verticalAlignment: VerticalAlignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }
}

private extension HorizontalEdge {

    /// 与水平边缘对应的通用布局边缘。
    var edge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// 使插入内容贴合该边缘的水平对齐方式。
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private extension Edge {

    /// 仅包含当前边缘的集合。
    var edgeSet: EdgeSet {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// 当前边缘占用长度所在的轴。
    var axis: Axis {
        switch self {
        case .top, .bottom: .vertical
        case .leading, .trailing: .horizontal
        }
    }
}

private extension EdgeInsets {

    /// 将各边的非有限值归零，保留有限负值。
    var sanitized: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaValue(top),
            leading: sanitizedSafeAreaValue(leading),
            bottom: sanitizedSafeAreaValue(bottom),
            trailing: sanitizedSafeAreaValue(trailing)
        )
    }

    /// 将各边归一化为有限非负的额外 padding。
    var sanitizedSafeAreaPadding: EdgeInsets {
        EdgeInsets(
            top: sanitizedSafeAreaPaddingValue(top),
            leading: sanitizedSafeAreaPaddingValue(leading),
            bottom: sanitizedSafeAreaPaddingValue(bottom),
            trailing: sanitizedSafeAreaPaddingValue(trailing)
        )
    }

    /// 读取指定方向性边缘的边距。
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

    /// 将尺寸归一化为非负建议，并将最大有限哨兵转为无穷。
    var normalizedContainerSize: CGSize {
        CGSize(width: normalized(width), height: normalized(height))
    }

    /// 读取指定轴对应的长度。
    func length(for axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: width
        case .vertical: height
        }
    }
}

/// 将非有限值归零，保留有限数值及其符号。
private func sanitized(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

/// 归一化安全区域分量；负值按原样保留。
private func sanitizedSafeAreaValue(_ value: CGFloat) -> CGFloat {
    sanitized(value)
}

/// 将额外安全区域内边距限制为有限非负值。
private func sanitizedSafeAreaPaddingValue(_ value: CGFloat) -> CGFloat {
    max(0, sanitized(value))
}

/// 规范容器长度：`NaN` 和负值归零，最大有限哨兵转为无穷。
private func normalized(_ value: CGFloat) -> CGFloat {
    if value.isNaN {
        return 0
    }
    if value == .greatestFiniteMagnitude {
        return .infinity
    }
    return max(0, value)
}

/// 从有限长度中扣除两端边距并限制为非负；无界长度直接保留。
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
