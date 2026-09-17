import QuickLayout
import UIKit

/// 为标记了 `.bubbleWidth()` 的子元素提供相对于当前容器的宽度上限。
///
/// - Parameters:
///   - ratio: 相对于整行建议宽度的比例；限界到 0...1，NaN 使用默认值 0.70。
///   - minWidth: 比例计算结果的下限；实际宽度仍受父布局可用空间限制。
///   - maxWidth: 比例计算结果的上限。
///   - content: 立即构建的布局内容。
func BubbleWidth(
    ratio: CGFloat = 0.70,
    minWidth: CGFloat = 0,
    maxWidth: CGFloat = .infinity,
    @LayoutBuilder content: () -> Layout
) -> BubbleWidthElement {
    BubbleWidthElement(child: content(), ratio: ratio, minWidth: minWidth, maxWidth: maxWidth)
}

/// 立即构建并保存布局内容，测量时为标记的气泡元素提供宽度上限。
/// 实际可用空间仍由内部 stack 分配，不依赖 cell bounds 或延迟构建闭包。
struct BubbleWidthElement: Layout {
    /// 相对于整行建议宽度的比例；越界值限界到 0...1，NaN 使用默认值 0.70。
    var ratio: CGFloat {
        get { storedRatio }
        set { storedRatio = Self.validatedRatio(newValue) }
    }
    private var storedRatio: CGFloat
    var minWidth: CGFloat
    var maxWidth: CGFloat
    private let child: Element

    init(child: Element, ratio: CGFloat, minWidth: CGFloat, maxWidth: CGFloat) {
        storedRatio = Self.validatedRatio(ratio)
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.child = child
    }

    private static func validatedRatio(_ value: CGFloat) -> CGFloat {
        value.isNaN ? 0.70 : min(1, max(0, value))
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        // 无界 proposal 与零比例相乘会产生 NaN，零比例直接提供零宽度。
        let proportionalWidth = ratio == 0 ? 0 : proposedSize.width * ratio
        let bubbleWidth = min(maxWidth, max(minWidth, proportionalWidth))
        return BubbleWidthContext.$maxWidth.withValue(bubbleWidth) {
            child.quick_layoutThatFits(proposedSize)
        }
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    func quick_layoutPriority() -> CGFloat { 0 }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axis == .horizontal ? .fixedSize : .fullyFlexible
    }
}

/// 嵌套测量自动恢复外层宽度，各次测量之间不保留临时状态。
private enum BubbleWidthContext {
    @TaskLocal static var maxWidth: CGFloat = .infinity
}

extension Element {
    /// 应用最近一层 BubbleWidth 的宽度上限，保留内容自身的收紧尺寸。
    func bubbleWidth() -> Element & Layout {
        BubbleWidthLimitElement(child: self)
    }
}

private struct BubbleWidthLimitElement: Layout {
    let child: Element

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(CGSize(
            width: min(proposedSize.width, BubbleWidthContext.maxWidth),
            height: proposedSize.height
        ))
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        axis == .horizontal ? .partial : child.quick_flexibility(for: axis)
    }
}
