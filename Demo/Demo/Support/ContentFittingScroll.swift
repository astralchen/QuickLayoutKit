import QuickLayout
import QuickLayoutKit
import UIKit

/// 内容较短时采用自然高度，较长时在父布局实际提供的空间内滚动。
/// QuickLayoutKit 的垂直 ScrollView 默认填满提议；这里仅补充视口测量策略。
/// 外层负责安全区，内部内容与测量使用同一宽度，不读取尚未布局的视图 bounds。
@MainActor
struct ContentFittingScroll: @MainActor Layout {
    private let viewport: Layout
    private let maximumHeightFraction: CGFloat

    init(
        _ scrollView: QuickLayoutScrollView,
        maximumHeightFraction: CGFloat = 1,
        @LayoutBuilder content: () -> Layout
    ) {
        let content = content()
        self.maximumHeightFraction = min(1, max(0, maximumHeightFraction))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        viewport = ScrollView(scrollView) { content }
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        // 通过滚动宿主测量：它负责扣除 contentInset，并建立自己的
        // containerRelativeFrame / safe-area 上下文。直接测量 content 会误用外层宿主。
        let natural = viewport.quick_layoutThatFits(
            CGSize(width: proposedSize.width, height: .infinity)
        ).size
        let width = proposedSize.width.isFinite ? max(0, proposedSize.width) : natural.width
        let limit = proposedSize.height.isFinite
            ? max(0, proposedSize.height) * maximumHeightFraction : natural.height
        return viewport.quick_layoutThatFits(CGSize(width: width, height: min(natural.height, limit)))
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axis == .vertical ? .fixedSize : viewport.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat { 0 }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        viewport.quick_extractViewsIntoArray(&views)
    }
}
