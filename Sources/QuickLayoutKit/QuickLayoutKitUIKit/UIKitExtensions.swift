import UIKit
import QuickLayout

extension UIView {

    /// 使用 QuickLayout 边距表示的视图安全区域边距。
    ///
    /// 前缘值和后缘值反映视图当前有效的用户界面布局方向。
    ///
    /// 应在视图完成布局后查询该值，例如在 `viewDidLayoutSubviews()` 中查询。
    public var quickLayoutSafeAreaInsets: QuickLayout.EdgeInsets {
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft

        return .init(
            top: safeAreaInsets.top,
            leading: isRTL ? safeAreaInsets.right : safeAreaInsets.left,
            bottom: safeAreaInsets.bottom,
            trailing: isRTL ? safeAreaInsets.left : safeAreaInsets.right
        )
    }

    /// 使用 QuickLayout 边距表示的视图方向性布局边距。
    public var quickLayoutDirectionalLayoutMargins: QuickLayout.EdgeInsets {
        .init(
            top: directionalLayoutMargins.top,
            leading: directionalLayoutMargins.leading,
            bottom: directionalLayoutMargins.bottom,
            trailing: directionalLayoutMargins.trailing
        )
    }

    /// 将视图物理布局边距转换为方向性 QuickLayout 边距后的值。
    public var quickLayoutLayoutMargins: QuickLayout.EdgeInsets {
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft

        return .init(
            top: layoutMargins.top,
            leading: isRTL ? layoutMargins.right : layoutMargins.left,
            bottom: layoutMargins.bottom,
            trailing: isRTL ? layoutMargins.left : layoutMargins.right
        )
    }

    /// 将内容与可读内容参考线对齐所需的边距。
    public var quickLayoutReadableContentInsets: QuickLayout.EdgeInsets {
        layoutIfNeeded()

        let readableFrame = readableContentGuide.layoutFrame
        guard !readableFrame.isEmpty else {
            return .init()
        }

        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let left = max(0, readableFrame.minX - bounds.minX)
        let right = max(0, bounds.maxX - readableFrame.maxX)

        return .init(
            top: max(0, readableFrame.minY - bounds.minY),
            leading: isRTL ? right : left,
            bottom: max(0, bounds.maxY - readableFrame.maxY),
            trailing: isRTL ? left : right
        )
    }

    /// 安全区域边距与方向性布局边距逐边取较大值后的结果。
    public var quickLayoutContentInsets: QuickLayout.EdgeInsets {
        let safeArea = quickLayoutSafeAreaInsets
        let margins = quickLayoutDirectionalLayoutMargins

        return .init(
            top: max(safeArea.top, margins.top),
            leading: max(safeArea.leading, margins.leading),
            bottom: max(safeArea.bottom, margins.bottom),
            trailing: max(safeArea.trailing, margins.trailing)
        )
    }
}

/// 将一组视图映射为布局元素并创建 QuickLayout 表达式。
///
/// 需要在布局构建器中为集合内每个视图生成一个元素时，使用此函数。
///
/// - Parameters:
///   - list: 要遍历的视图集合。
///   - map: 根据视图返回布局元素的闭包。
/// - Returns: 按原有顺序包含映射元素的快速表达式。
public func ForEach<T>(_ list: [T], map: (T) -> Element) -> FastExpression where T: UIView {
    BlockExpression(expressions: list.map { ValueExpression<Element>(value: map($0)) })
}


extension UICollectionViewCell {

    /// 返回单元格在指定轴上的尺寸弹性。
    ///
    /// 子类可以重写该方法，说明单元格的宽度或高度是由集合视图布局固定、受部分约束，
    /// 还是完全由内容决定。
    ///
    /// - Parameter axis: 要查询的轴。
    /// - Returns: 单元格在指定轴上的尺寸弹性。
    @objc open func quickLayoutFlexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    /// 根据建议长度和尺寸弹性返回布局限制。
    ///
    /// 测量由 QuickLayout 计算最终尺寸的集合视图单元格时使用该值。固定尺寸使用建议值；
    /// 部分弹性尺寸至少使用最小值；完全弹性尺寸使用无约束限制。
    ///
    /// - Parameters:
    ///   - proposed: 父布局建议的长度。
    ///   - minimum: 部分弹性情况下使用的最小长度。
    ///   - flexibility: 被测量轴的尺寸弹性。
    /// - Returns: 布局测量时使用的长度限制。
    public func quickLayoutSizeLimit(
        proposed: CGFloat,
        minimum: CGFloat = 0,
        flexibility: Flexibility
    ) -> CGFloat {

        switch flexibility {
        case .fixedSize:
            return proposed

        case .partial:
            return max(minimum, proposed)

        case .fullyFlexible:
            return .infinity
        }
    }
}

extension UICollectionViewCell {

    /// 返回指定建议尺寸对应的布局限制。
    ///
    /// 返回值会分别应用单元格的水平和垂直尺寸弹性。
    ///
    /// - Parameter size: 父布局建议的尺寸。
    /// - Returns: 布局测量时使用的尺寸限制。
    public func quickLayoutSizeLimit(
        proposed size: CGSize
    ) -> CGSize {
        CGSize(
            width: quickLayoutSizeLimit(
                proposed: size.width,
                flexibility: quickLayoutFlexibility(for: .horizontal)
            ),
            height: quickLayoutSizeLimit(
                proposed: size.height,
                flexibility: quickLayoutFlexibility(for: .vertical)
            )
        )
    }
}
