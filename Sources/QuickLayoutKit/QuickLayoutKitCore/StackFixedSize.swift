import QuickLayout

public extension StackElement {

    /// 按指定轴采用栈的理想尺寸，并协调交叉轴上可伸展子元素的尺寸。
    ///
    /// 直接对 HStack 固定垂直轴（或对 VStack 固定水平轴）时，先使用上游的
    /// `idealLayout` 测量自然尺寸，再向子元素提出最大的交叉轴尺寸建议。
    /// 固定尺寸子元素仍保持自己的尺寸。仅固定主轴时保留原有布局策略。
    ///
    /// 此重载要求接收者的静态类型为 `StackElement`。先调用 `padding` 等包装
    /// 修饰符，或擦除为 `Element` / `Layout` 后，会使用上游的通用重载。
    /// 要为等高栈添加外边距，请使用 `HStack { … }.fixedSize(axis: .vertical).padding(…)`。
    ///
    /// - Parameter axis: 使用理想尺寸的轴；默认同时固定水平和垂直轴。
    /// - Returns: 采用理想尺寸的布局元素。
    func fixedSize(axis: AxisSet = [.horizontal, .vertical]) -> Element & Layout {
        let fixesCrossAxis = mainAxis == .horizontal
            ? axis.contains(.vertical)
            : axis.contains(.horizontal)
        return FixedSizeElement(
            child: fixesCrossAxis ? idealLayout(true) : self,
            horizontal: axis.contains(.horizontal),
            vertical: axis.contains(.vertical)
        )
    }
}
