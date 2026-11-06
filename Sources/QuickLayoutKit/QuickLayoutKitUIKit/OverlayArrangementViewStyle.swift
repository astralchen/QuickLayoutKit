import QuickLayout
import QuickLayoutKitCore
import UIKit

enum OverlayHorizontalEdgeKey: LayoutValueKey {
    static let defaultValue: HorizontalEdge? = nil
}
enum OverlayVerticalEdgeKey: LayoutValueKey {
    static let defaultValue: VerticalEdge? = nil
}

public extension Element {
    /// 内容沿水平分隔区分栏时占据的边缘。浮层状态继续按自身布局定位。
    func overlayArrangementEdge(_ edge: HorizontalEdge?) -> Layout {
        layoutValue(key: OverlayHorizontalEdgeKey.self, value: edge)
    }

    /// 内容沿垂直方向分隔时占据的边缘。
    func overlayArrangementEdge(_ edge: VerticalEdge?) -> Layout {
        layoutValue(key: OverlayVerticalEdgeKey.self, value: edge)
    }
}

/// 默认将主内容叠在辅助内容上；遇到活动的硬件分隔区域时按允许的轴分开。
public struct OverlayArrangementViewStyle: ArrangementViewStyle {
    private var allowedAxes: AxisSet = [.horizontal, .vertical]
    public init() {}

    public func axes(_ axes: AxisSet) -> Self {
        var copy = self
        copy.allowedAxes = axes
        return copy
    }

    public func makeBody(configuration: Configuration) -> some Layout {
        ResizableElement(child: ArrangementHost.make(panes: configuration, style: .overlay, axes: allowedAxes),
                         axis: [.horizontal, .vertical])
    }
}

public extension ArrangementViewStyle where Self == OverlayArrangementViewStyle {
    static var overlay: Self { Self() }
}
