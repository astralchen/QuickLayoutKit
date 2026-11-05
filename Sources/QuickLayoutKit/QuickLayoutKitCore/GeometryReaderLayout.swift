import QuickLayout
import UIKit

/// Reader 的测量实现。没有内部内容宿主，业务视图与观察标记共享外层宿主。
@MainActor
package struct GeometryReaderLayout: @MainActor Layout {
    private let marker: GeometryReaderMarker
    private let state: GeometryReaderState
    private let content: (GeometryProxy) -> [Element]

    package init(file: String, line: UInt, column: UInt,
                 content: @escaping (GeometryProxy) -> [Element]) {
        marker = (QuickLayoutGeometryObservationContext.current?.readerMarker(
            file: file, line: line, column: column, make: { GeometryReaderMarker() }
        ) as? GeometryReaderMarker) ?? GeometryReaderMarker()
        state = marker.readerState
        self.content = content
    }

    package func quick_flexibility(for axis: Axis) -> Flexibility { .fullyFlexible }
    package func quick_layoutPriority() -> CGFloat { 0 }
    package func quick_extractViewsIntoArray(_ views: inout [UIView]) { views.append(marker) }

    /// 每次调用只构建一次内容，子节点只测量一次。没有挂载、frame 写入或业务回调。
    package func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let size = CGSize(width: readerLength(proposedSize.width), height: readerLength(proposedSize.height))
        let direction = LayoutContext.layoutDirection
        let scopes = GeometryScopeContext.scopes
        let proxy = GeometryProxy(measuring: size, direction: direction, previous: state.latestSnapshot)
        return QuickLayoutGeometryObservationContext.withRegistry(state.registry) {
            let children = content(proxy).enumerated().sorted {
                let a = $0.element._layoutValue(for: _ZIndexLayoutValueKey.self)
                let b = $1.element._layoutValue(for: _ZIndexLayoutValueKey.self)
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            var views: [UIView] = []
            children.forEach { $0.quick_extractViewsIntoArray(&views) }
            let nodes = children.map { $0.quick_layoutThatFits(size) }
            // 捕获本次测量的应用信息。后续 B 测量不会修改缓存 A 的方向、视图集合或尺寸。
            let commit = GeometryReaderCommit(marker: marker, state: state, views: views,
                                              proxy: proxy, direction: direction, scopes: scopes)
            var layers: [Element] = [ReaderFixedNode(LayoutNode(view: commit, dimensions: ElementDimensions(size))),
                                     ReaderFixedNode(LayoutNode(view: marker, dimensions: ElementDimensions(size)))]
            for node in nodes {
                // 不让内容的 alignment guide 改变 Reader 的顶部前缘放置规则。
                let child = ReaderFixedNode(node)
                    .defaultPlacementGuides()
                let layer = FixedFrameElement(child: child, width: size.width, height: size.height,
                                              alignment: .topLeading)
                    .defaultPlacementGuides()
                layers.append(layer)
            }
            return ZStackElement(children: layers, alignment: .topLeading).quick_layoutThatFits(size)
        }
    }
}

private func readerLength(_ value: CGFloat) -> CGFloat {
    if value.isNaN || value < 0 { return 0 }
    return value.isFinite && value != .greatestFiniteMagnitude ? value : 10
}

/// 唯一挂载的辅助视图是无交互的同级观察标记；它不承载业务子视图。
@MainActor
private final class GeometryReaderMarker: GeometryObserverView {
    let readerState = GeometryReaderState()
    override init() {
        super.init()
        readerState.marker = self
        geometryDidChange = { [readerState] in readerState.receive($0) }
        didDetach = { [readerState] in readerState.detach() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil { readerState.detach() }
    }
}

@MainActor
private final class GeometryReaderState {
    weak var marker: GeometryObserverView?
    weak var container: UIView?
    let registry = QuickLayoutGeometryObservationRegistry()
    var latestSnapshot: GeometryProxy?
    var appliedInput: GeometryProxy?
    private var activeViews: [UIView] = []

    /// 仅提交真正应用的节点；测量另一个候选节点不会提前移除或重排当前视图。
    func apply(views: [UIView], input: GeometryProxy) {
        guard let marker, let parent = marker.superview else { return }
        let identifiers = Set(views.map(ObjectIdentifier.init))
        for view in activeViews where !identifiers.contains(ObjectIdentifier(view)) {
            if view.superview === container { view.removeFromSuperview() }
        }
        container = parent
        activeViews = views
        appliedInput = input
        // 动态内容紧随标记。其他元素仍由外层 QuickLayout 协调，Reader 不插入内容容器。
        var index = (parent.subviews.firstIndex(of: marker) ?? 0) + 1
        for view in views {
            if view.superview !== parent || parent.subviews.firstIndex(of: view) != index {
                parent.insertSubview(view, at: min(index, parent.subviews.count))
            }
            index += 1
        }
    }

    func receive(_ snapshot: GeometryProxy) {
        latestSnapshot = snapshot
        guard snapshot != appliedInput else { return }
        // 父位置在测量完成后才确定；实际几何变化只使外层宿主失效，不在这里测量子树。
        var ancestor = marker?.superview
        while let view = ancestor {
            view.setNeedsLayout()
            if view is any HasBody { break }
            ancestor = view.superview
        }
    }

    func detach() {
        for view in activeViews where view.superview === container { view.removeFromSuperview() }
        activeViews.removeAll()
        latestSnapshot = nil
        appliedInput = nil
        container = nil
    }
}

/// QuickLayout 的公开节点只提供 UIView 应用入口。此未挂载的提交节点携带不可变事务，
/// 在引擎写入 center 时同步视图集合和观察元数据；它不触发布局，也不生成子节点。
@MainActor
private final class GeometryReaderCommit: UIView {
    let marker: GeometryObserverView
    let state: GeometryReaderState
    let views: [UIView]
    let input: GeometryProxy
    let direction: LayoutDirection
    let scopes: [GeometryScope]

    init(marker: GeometryObserverView, state: GeometryReaderState, views: [UIView],
         proxy: GeometryProxy, direction: LayoutDirection, scopes: [GeometryScope]) {
        self.marker = marker
        self.state = state
        self.views = views
        input = proxy
        self.direction = direction
        self.scopes = scopes
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var center: CGPoint {
        didSet {
            state.apply(views: views, input: input)
            marker.pendingLayoutDirection = direction
            marker.pendingScopes = scopes
        }
    }
}

private struct ReaderFixedNode: Layout {
    let node: LayoutNode
    init(_ node: LayoutNode) { self.node = node }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}
