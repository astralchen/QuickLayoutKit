//
//  ScrollView.swift
//  QuickLayoutKit
//
//  由 Sondra 创建于 2025/12/24。
//

import UIKit
import QuickLayout

// MARK: - 滚动视图容器

/// 创建由滚动视图承载的布局元素。
///
/// 在布局构建器中使用此函数声明可滚动的 QuickLayout 内容，并复用指定的
/// `QuickLayoutScrollView` 实例。
///
/// 显式传入滚动视图，可以提供稳定的 UIKit 对象标识；对于值类型的 `ScrollView`，
/// 该标识通常由 SwiftUI 管理。
///
/// 与 SwiftUI 的 `ScrollView` 一样，滚动轴接受建议长度，交叉轴按内容和建议尺寸测量。
/// UIKit 通过调整后的内容边距表示与滚动视图相交的安全区域，QuickLayout 会将这些值
/// 传递给滚动内容。
/// 对必须保持在安全区域内的非滚动内容使用 `safeAreaPadding`；需要让可滚动内容的起止
/// 边缘在安全区域内可达时，使用 `contentMargins`。
///
/// - Parameters:
///   - scrollView: 用作承载视图的滚动视图。
///   - axis: 滚动视图滚动的单一轴。
///   - showsIndicators: 是否显示相应轴的滚动指示器。
///   - content: 返回待显示元素的构建器闭包。
/// - Returns: 用于渲染滚动视图的布局元素。
@MainActor public func ScrollView(
    _ scrollView: QuickLayoutScrollView,
    _ axis: QuickLayout.Axis = .vertical,
    showsIndicators: Bool = true,
    @FastArrayBuilder<Element> content: () -> [Element]
) -> LeafElement & Layout {
    scrollView.configure(
        axis: axis,
        showsIndicators: showsIndicators,
        content: content()
    )
    return ScrollElement(scrollView)
}

/// 将稳定的滚动视图实例适配为 QuickLayout 叶子节点。
@MainActor
private struct ScrollElement: @MainActor Layout, @MainActor LeafElement {

    /// 由调用方持有并复用的滚动宿主。
    private let child: QuickLayoutScrollView

    /// 保存滚动宿主，不创建新的 UIKit 实例。
    init(_ scrollView: QuickLayoutScrollView) {
        self.child = scrollView
    }

    /// 由 QuickLayout 的 UIScrollView 桥接调用宿主的 sizeThatFits。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    /// 构建器与直接使用宿主视图时采用相同的轴弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    /// 返回该叶子节点使用的滚动宿主视图。
    func backingView() -> UIView? {
        child
    }

}
