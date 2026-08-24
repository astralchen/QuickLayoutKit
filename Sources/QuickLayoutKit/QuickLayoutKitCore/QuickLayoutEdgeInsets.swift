import CoreGraphics
import QuickLayout

extension QuickLayout.EdgeInsets {

    /// 水平方向上的最大边距。
    ///
    /// 该值是接收者前缘边距与后缘边距中的较大值。
    public var maximumHorizontalInset: CGFloat {
        max(leading, trailing)
    }

    /// 垂直方向上的最大边距。
    ///
    /// 该值是接收者顶部边距与底部边距中的较大值。
    public var maximumVerticalInset: CGFloat {
        max(top, bottom)
    }
}
