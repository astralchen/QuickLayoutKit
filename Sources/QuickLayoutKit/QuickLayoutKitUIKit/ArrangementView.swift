import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 样式接收的两块内容；更换排列时复用原来的视图。
public struct ArrangementViewStyleConfiguration {
    public struct Primary: Layout, _LayoutValueProvidingElement {
        let content: Layout
        package var _layoutValueChild: Element { content }
        package func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }
        public func quick_layoutThatFits(_ size: CGSize) -> LayoutNode { content.quick_layoutThatFits(size) }
        public func quick_flexibility(for axis: Axis) -> Flexibility { content.quick_flexibility(for: axis) }
        public func quick_layoutPriority() -> CGFloat { content.quick_layoutPriority() }
        public func quick_extractViewsIntoArray(_ views: inout [UIView]) { content.quick_extractViewsIntoArray(&views) }
    }

    public struct Secondary: Layout, _LayoutValueProvidingElement {
        let content: Layout
        package var _layoutValueChild: Element { content }
        package func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }
        public func quick_layoutThatFits(_ size: CGSize) -> LayoutNode { content.quick_layoutThatFits(size) }
        public func quick_flexibility(for axis: Axis) -> Flexibility { content.quick_flexibility(for: axis) }
        public func quick_layoutPriority() -> CGFloat { content.quick_layoutPriority() }
        public func quick_extractViewsIntoArray(_ views: inout [UIView]) { content.quick_extractViewsIntoArray(&views) }
    }

    public let primary: Primary
    public let secondary: Secondary

    init(primary: Layout, secondary: Layout) {
        self.primary = Primary(content: primary)
        self.secondary = Secondary(content: secondary)
    }
}

/// 决定主、辅内容如何排列。自定义样式可以组合已有 QuickLayout 元素。
@MainActor
public protocol ArrangementViewStyle {
    associatedtype Body: Layout
    typealias Configuration = ArrangementViewStyleConfiguration
    func makeBody(configuration: Configuration) -> Body
}

/// 排列两块相关内容，对应 SwiftUI 的 `ArrangementView { … } secondary: { … }`。
@MainActor
public struct ArrangementView: @MainActor Layout {
    private let storage: Storage

    public init(@LayoutBuilder primary: () -> Layout, @LayoutBuilder secondary: () -> Layout) {
        storage = Storage(configuration: .init(primary: primary(), secondary: secondary()))
    }

    /// 在自定义样式内重新使用原内容，并允许显式指定另一种样式。
    public init(_ configuration: ArrangementViewStyleConfiguration) {
        storage = Storage(configuration: configuration, excluding: ArrangementStyleScope.current)
    }

    public func quick_layoutThatFits(_ size: CGSize) -> LayoutNode { storage.body.quick_layoutThatFits(size) }
    public func quick_flexibility(for axis: Axis) -> Flexibility { storage.body.quick_flexibility(for: axis) }
    public func quick_layoutPriority() -> CGFloat { storage.body.quick_layoutPriority() }
    public func quick_extractViewsIntoArray(_ views: inout [UIView]) { storage.body.quick_extractViewsIntoArray(&views) }

    @MainActor
    private final class Storage {
        let configuration: ArrangementViewStyleConfiguration
        let excludedStyle: ArrangementStyleBox?
        private var previous: ArrangementStyleBox?
        private var cachedBody: Layout?

        init(configuration: ArrangementViewStyleConfiguration, excluding style: ArrangementStyleBox? = nil) {
            self.configuration = configuration
            excludedStyle = style
        }

        var body: Layout {
            let inherited = ArrangementStyleScope.current
            let style = inherited === excludedStyle ? ArrangementStyleBox.standard : (inherited ?? .standard)
            if previous === style, let cachedBody { return cachedBody }
            let body = style.makeBody(configuration)
            previous = style
            cachedBody = body
            return body
        }
    }
}

@MainActor
private final class ArrangementStyleBox {
    static let standard = ArrangementStyleBox(AutomaticArrangementViewStyle())
    let makeBody: (ArrangementViewStyleConfiguration) -> Layout

    init(_ style: some ArrangementViewStyle) {
        makeBody = { style.makeBody(configuration: $0) }
    }
}

private enum ArrangementStyleScope {
    @TaskLocal static var current: ArrangementStyleBox?
}

@MainActor
func inheritingArrangementStyle(_ element: Layout) -> Layout {
    guard let style = ArrangementStyleScope.current else { return element }
    return StyledArrangementContent(content: element, style: style)
}

public extension Element {
    /// 为该元素及其后代的 ArrangementView 设置样式；更近的设置优先。
    @MainActor
    func arrangementViewStyle(_ style: some ArrangementViewStyle) -> some Layout {
        StyledArrangementContent(content: self, style: ArrangementStyleBox(style))
    }
}

private struct StyledArrangementContent: @MainActor Layout {
    let content: Element
    let style: ArrangementStyleBox

    func quick_layoutThatFits(_ size: CGSize) -> LayoutNode {
        ArrangementStyleScope.$current.withValue(style) { content.quick_layoutThatFits(size) }
    }
    func quick_flexibility(for axis: Axis) -> Flexibility {
        ArrangementStyleScope.$current.withValue(style) { content.quick_flexibility(for: axis) }
    }
    func quick_layoutPriority() -> CGFloat {
        ArrangementStyleScope.$current.withValue(style) { content.quick_layoutPriority() }
    }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        ArrangementStyleScope.$current.withValue(style) { content.quick_extractViewsIntoArray(&views) }
    }
}

/// 布局元素在测量时可读取的当前排列上下文。离开排列后恢复外层值。
public enum ArrangementLayoutContext {
    @TaskLocal private static var axis: Axis?
    @TaskLocal private static var zIndex = 0
    public static var splitArrangementAxis: Axis? { axis }
    public static var overlayArrangementZIndex: Int { zIndex }

    static func measure<T>(axis: Axis?, zIndex: Int = 0, _ work: () -> T) -> T {
        $axis.withValue(axis) { $zIndex.withValue(zIndex, operation: work) }
    }
}

/// QuickLayout 排列宿主为 UIKit 后代提供当前分栏轴和叠放次序。
@MainActor
protocol ArrangementContextSource: AnyObject {
    var arrangementAxis: Axis? { get }
    var arrangementZIndex: Int { get }
}

public extension UIView {
    /// 读取最近排列宿主中的分栏轴；单区域或浮层状态返回 nil。
    var splitArrangementAxis: Axis? {
        if let source = arrangementContextSource { return source.arrangementAxis }
        return ArrangementLayoutContext.splitArrangementAxis
    }

    /// 读取本视图在浮层排列中的层级，普通视图默认是 0。
    var overlayArrangementZIndex: Int {
        arrangementContextSource?.arrangementZIndex ?? ArrangementLayoutContext.overlayArrangementZIndex
    }

    private var arrangementContextSource: ArrangementContextSource? {
        var ancestor: UIView? = self
        while let current = ancestor {
            if let source = current as? ArrangementContextSource { return source }
            ancestor = current.superview
        }
        return nil
    }
}

/// 自动样式默认使用分割排列。
public struct AutomaticArrangementViewStyle: ArrangementViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some Layout {
        SplitArrangementViewStyle().makeBody(configuration: configuration)
    }
}

public extension ArrangementViewStyle where Self == AutomaticArrangementViewStyle {
    static var automatic: Self { Self() }
}
