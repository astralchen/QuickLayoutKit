import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 在主轴上为两个内容分配独立空间。默认在宽扁区域横排，在高窄区域竖排。
public struct SplitArrangementViewStyle: ArrangementViewStyle {
    private var allowedAxes: AxisSet = [.horizontal, .vertical]

    public init() {}

    public func axes(_ axes: AxisSet) -> Self {
        var copy = self
        copy.allowedAxes = axes
        return copy
    }

    public func makeBody(configuration: Configuration) -> some Layout {
        ResizableElement(child: ArrangementHost.make(panes: configuration, style: .split, axes: allowedAxes),
                         axis: [.horizontal, .vertical])
    }
}

public extension ArrangementViewStyle where Self == SplitArrangementViewStyle {
    static var split: Self { Self() }
}
