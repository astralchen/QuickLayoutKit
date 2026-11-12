import QuickLayout
import UIKit

/// 提取作用域只读取最终测量树；不使用理想尺寸试探或上一轮布局留下的选择。
enum QuickLayoutCandidateSelection {
    @TaskLocal static var current: [ObjectIdentifier: [UIView]]?

    static func views(of element: Element, measured node: LayoutNode) -> [UIView] {
        var selections: [ObjectIdentifier: [UIView]] = [:]
        func collect(_ node: LayoutNode) {
            if let marker = node.view as? CandidateSelectionMarker {
                // 同一布局值可复用在不同位置，保留各位置实际使用的视图并集。
                selections[ObjectIdentifier(marker.identity), default: []].append(contentsOf: marker.selectedViews)
            }
            node.children.forEach { collect($0.layout) }
        }
        collect(node)
        return $current.withValue(selections) {
            var views: [UIView] = []
            element.quick_extractViewsIntoArray(&views)
            var seen = Set<ObjectIdentifier>()
            return views.filter { seen.insert(ObjectIdentifier($0)).inserted }
        }
    }
}

/// 节点专属的只读元数据，不加入宿主、不修改候选视图，也不产生布局提交回调。
@MainActor
final class CandidateSelectionMarker: UIView {
    nonisolated let identity: CandidateIdentity
    nonisolated let selectedViews: [UIView]

    init(identity: CandidateIdentity, views: [UIView]) {
        self.identity = identity
        selectedViews = views
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 同一份测量结果同时提供挂载列表和布局节点，避免同步层级后再次选择不同分支。
package struct QuickLayoutMeasuredLayout: Layout {
    package let node: LayoutNode
    package let mountedViews: [UIView]

    package init(element: Element, node: LayoutNode) {
        self.node = node
        mountedViews = QuickLayoutCandidateSelection.views(of: element, measured: node)
    }

    init(node: LayoutNode, mountedViews: [UIView]) {
        self.node = node
        self.mountedViews = mountedViews
    }

    package func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    package func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    package func quick_layoutPriority() -> CGFloat { 0 }
    package func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        views.append(contentsOf: mountedViews)
    }
}
