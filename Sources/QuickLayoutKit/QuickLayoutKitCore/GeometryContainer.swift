import CoreGraphics
import QuickLayout

/// 四角的方向性内缩。该值类型本身可在 iOS 15 上保存；系统查询受 availability 限制。
public struct RectangleCornerInsets: Hashable, Sendable {
    /// 顶部前缘角占用的水平与垂直内缩量，单位为点。
    public var topLeading: CGSize
    /// 顶部后缘角占用的水平与垂直内缩量，单位为点。
    public var topTrailing: CGSize
    /// 底部前缘角占用的水平与垂直内缩量，单位为点。
    public var bottomLeading: CGSize
    /// 底部后缘角占用的水平与垂直内缩量，单位为点。
    public var bottomTrailing: CGSize

    /// 创建四角的方向性内缩值。
    ///
    /// - Parameters:
    ///   - topLeading: 顶部前缘内缩，默认 `.zero`。
    ///   - topTrailing: 顶部后缘内缩，默认 `.zero`。
    ///   - bottomLeading: 底部前缘内缩，默认 `.zero`。
    ///   - bottomTrailing: 底部后缘内缩，默认 `.zero`。
    public init(topLeading: CGSize = .zero, topTrailing: CGSize = .zero,
                bottomLeading: CGSize = .zero, bottomTrailing: CGSize = .zero) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    /// 按四个角的宽高分量计算哈希。
    public func hash(into hasher: inout Hasher) {
        for corner in [topLeading, topTrailing, bottomLeading, bottomTrailing] {
            hasher.combine(corner.width); hasher.combine(corner.height)
        }
    }
}

/// 矩形四角的方向性半径，单位为点。
public struct RectangleCornerRadii: Equatable, Sendable {
    /// 顶部前缘的圆角半径，单位为点。
    public var topLeading: CGFloat
    /// 底部前缘的圆角半径，单位为点。
    public var bottomLeading: CGFloat
    /// 底部后缘的圆角半径，单位为点。
    public var bottomTrailing: CGFloat
    /// 顶部后缘的圆角半径，单位为点。
    public var topTrailing: CGFloat

    /// 创建方向性圆角半径。
    ///
    /// - Parameters:
    ///   - topLeading: 顶部前缘半径，默认零。
    ///   - bottomLeading: 底部前缘半径，默认零。
    ///   - bottomTrailing: 底部后缘半径，默认零。
    ///   - topTrailing: 顶部后缘半径，默认零。
    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0,
                bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }
}

/// 为 QuickLayout 原生容器声明可查询的几何信息，不改变容器绘制或布局。
///
/// `nil` 表示继续向外寻找该项信息。UIKit 无法公开提供的 SwiftUI 系统容器信息，
/// 可以由宿主显式传入，不能通过设备型号或安全区猜测。
public struct GeometryContainerValues: Equatable, Sendable {
    /// 容器内容区域的方向性边距；`nil` 表示继续查询外层来源。
    public var contentMargins: EdgeInsets?
    /// 容器四角的方向性内缩；`nil` 表示继续查询外层声明。
    public var cornerInsets: RectangleCornerInsets?
    /// 容器四角的方向性半径；`nil` 表示继续查询外层声明或可用 UIKit 来源。
    public var cornerRadii: RectangleCornerRadii?

    /// 创建只用于几何查询的容器元数据。
    ///
    /// - Parameters:
    ///   - contentMargins: 内容边距，默认 `nil`。
    ///   - cornerInsets: 角内缩，默认 `nil`。
    ///   - cornerRadii: 角半径，默认 `nil`。
    ///
    /// 各项独立查找来源，设置值不会修改视图布局或图层圆角。
    public init(contentMargins: EdgeInsets? = nil, cornerInsets: RectangleCornerInsets? = nil,
                cornerRadii: RectangleCornerRadii? = nil) {
        self.contentMargins = contentMargins
        self.cornerInsets = cornerInsets
        self.cornerRadii = cornerRadii
    }

    /// 逐项比较元数据，包括可选边距的四个分量。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        geometryInsetsEqual(lhs.contentMargins, rhs.contentMargins) && lhs.cornerInsets == rhs.cornerInsets && lhs.cornerRadii == rhs.cornerRadii
    }
}

/// 逐边比较可选方向性边距，区分缺失与零边距。
func geometryInsetsEqual(_ lhs: EdgeInsets?, _ rhs: EdgeInsets?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let a), .some(let b)):
        a.top == b.top && a.leading == b.leading && a.bottom == b.bottom && a.trailing == b.trailing
    default: false
    }
}

/// 内容边距所参考的容器。
@available(iOS 27.1, *)
public struct ContentMarginGuide: Sendable {
    /// 创建容器边距查询标记，仅由公开预设提供实例。
    private init() {}
    /// 查询最近可用容器内容区域的边距参考。
    public static var container: Self { .init() }
}

/// 将物理边距转为 QuickLayout 当前布局方向的边距。
func geometryInsets(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat,
                    direction: LayoutDirection) -> EdgeInsets {
    EdgeInsets(top: top, leading: direction == .rightToLeft ? right : left,
               bottom: bottom, trailing: direction == .rightToLeft ? left : right)
}
