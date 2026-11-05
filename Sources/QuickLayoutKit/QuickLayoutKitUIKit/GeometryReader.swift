import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 根据自身尺寸和坐标空间构建内容的弹性布局容器。
///
/// Reader 接受父布局在各轴提供的有限尺寸；未指定的轴使用 10 点理想长度。
/// 内容不会反向撑大容器。多个直接子元素叠放在顶部前缘，且不会自动裁剪溢出内容。
/// 在垂直滚动内容中，应显式设置高度，否则未指定的垂直轴仅占 10 点。
///
/// ```swift
/// GeometryReader { proxy in
///     card.resizable().frame(width: proxy.size.width * 0.5, height: 80)
/// }
/// .frame(height: 160)
/// ```
///
/// 内容在主线程测量阶段构建，同一次测量生成完整子树，业务视图直接挂在外层宿主。
/// `size` 来自本轮建议；位置和安全区域使用最近一次已应用的快照，首次测量时尚不可知。
/// 实际几何变化会使外层宿主重新布局。UIView 应由调用方保持稳定身份；
/// 闭包中创建的 UIView 不具有 SwiftUI 值类型视图的自动状态协调机制。
@MainActor
public struct GeometryReader: @MainActor Layout {
    private let layout: GeometryReaderLayout

    /// 内容闭包在每次测量中执行一次；应返回布局声明，不执行视图挂载或业务副作用。
    public init(
        _fileID: StaticString = #fileID,
        _line: UInt = #line,
        _column: UInt = #column,
        @FastArrayBuilder<Element> content: @escaping (GeometryProxy) -> [Element]
    ) {
        layout = GeometryReaderLayout(file: String(describing: _fileID), line: _line,
                                      column: _column, content: content)
    }

    public func quick_flexibility(for axis: Axis) -> Flexibility { layout.quick_flexibility(for: axis) }
    public func quick_layoutPriority() -> CGFloat { 0 }
    public func quick_extractViewsIntoArray(_ views: inout [UIView]) { layout.quick_extractViewsIntoArray(&views) }
    public func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout.quick_layoutThatFits(proposedSize) }
}
