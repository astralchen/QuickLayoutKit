import CoreGraphics
import QuickLayout

/// `VGrid` 的列或 `HGrid` 的行的尺寸、间距和单元格对齐规则。
public struct GridItem: Sendable {
    /// 一条固定轨道、一条弹性轨道，或在可用空间内重复的自适应轨道。
    public enum Size: Equatable, Sendable {
        /// 使用指定的宽度（VGrid）或高度（HGrid）。
        case fixed(CGFloat)
        /// 在最小值和最大值之间分配剩余空间。
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        /// 在分配到的空间内放入尽可能多的轨道。
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    /// 当前行或列的尺寸规则。
    public var size: Size
    /// 到下一条轨道的间距，默认为 0，末尾不添加间距。
    /// 布局时与 QuickLayout Grid 一样，将负数和非有限值按 0 处理。
    public var spacing: CGFloat
    /// 单元格内的内容对齐方式；`nil` 使用网格的默认对齐方式。
    public var alignment: Alignment?

    /// 创建行或列规则，默认使用最小尺寸为 10 点的弹性轨道。
    public init(_ size: Size = .flexible(), spacing: CGFloat = 0, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}
