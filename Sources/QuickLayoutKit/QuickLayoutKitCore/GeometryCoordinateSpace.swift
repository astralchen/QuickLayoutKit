import Foundation
import QuickLayout

/// 几何查询使用的坐标空间。保留原有三个预设的源码兼容性。
public enum GeometryCoordinateSpace: Sendable, Hashable {
    /// 以被观察元素为原点的局部坐标空间。
    case local
    /// 通过 UIKit 向 `nil` 目标转换得到的全局坐标空间。
    case global
    /// 最近滚动视图祖先的内容坐标空间。
    case scrollView
    /// 由可哈希名称标识的布局作用域；同名时最近有效声明优先。
    case named(GeometrySpaceName)
    /// 最近满足指定滚动轴的滚动视图祖先坐标空间。
    case scrollViewAxis(Axis)
}

/// 类型擦除后的不可变名称；只允许从 `Hashable & Sendable` 值创建。
public struct GeometrySpaceName: Hashable, @unchecked Sendable {
    /// 保留名称相等性与哈希语义的类型擦除值。
    private let value: AnyHashable
    /// 使用可跨并发域传递的可哈希值创建空间名称。
    ///
    /// - Parameter value: 用于匹配坐标空间声明的名称。
    public init(_ value: some Hashable & Sendable) { self.value = AnyHashable(value) }
}

/// 可以传给几何查询的二维坐标空间。
public protocol CoordinateSpaceProtocol: Sendable {
    /// 几何查询使用的底层坐标空间标识。
    var coordinateSpace: GeometryCoordinateSpace { get }
}

extension GeometryCoordinateSpace: CoordinateSpaceProtocol {
    /// 当前枚举值对应的坐标空间标识。
    public var coordinateSpace: GeometryCoordinateSpace { self }
}

/// 用于表达元素局部空间的具体坐标空间类型。
public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
    /// 创建局部坐标空间。
    public init() {}
    /// 返回 `.local` 坐标空间标识。
    public var coordinateSpace: GeometryCoordinateSpace { .local }
}

/// 用于表达 UIKit 全局空间的具体坐标空间类型。
public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
    /// 创建全局坐标空间。
    public init() {}
    /// 返回 `.global` 坐标空间标识。
    public var coordinateSpace: GeometryCoordinateSpace { .global }
}

/// 表达命名作用域或滚动视图空间的可哈希查询描述。
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Hashable {
    /// 当前命名或滚动空间对应的底层标识。
    public let coordinateSpace: GeometryCoordinateSpace
    /// 保存经过工厂方法选择的坐标空间标识。
    private init(_ space: GeometryCoordinateSpace) { coordinateSpace = space }

    /// 按名称创建空间查询描述。
    ///
    /// - Parameter name: 与 `coordinateSpace(_:)` 声明匹配的名称。
    /// - Returns: 指向该名称的坐标空间；此操作不会建立布局作用域。
    public static func named(_ name: some Hashable & Sendable) -> Self {
        Self(.named(GeometrySpaceName(name)))
    }
    /// 最近滚动视图祖先的坐标空间。
    public static var scrollView: Self { Self(.scrollView) }
    /// 创建指定滚动轴的空间查询。
    ///
    /// - Parameter axis: 需要匹配的滚动轴。
    /// - Returns: 最近匹配该轴的滚动视图坐标空间描述。
    public static func scrollView(axis: Axis) -> Self { Self(.scrollViewAxis(axis)) }
}

public extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    /// 用于类型推断的局部坐标空间预设。
    static var local: Self { .init() }
}
public extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    /// 用于类型推断的全局坐标空间预设。
    static var global: Self { .init() }
}
public extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// 创建由可哈希名称标识的坐标空间查询；不会建立布局作用域。
    ///
    /// - Parameter name: 与空间声明匹配的名称。
    /// - Returns: 命名坐标空间描述。
    static func named(_ name: some Hashable & Sendable) -> Self { .named(name) }
    /// 用于类型推断的最近滚动视图坐标空间。
    static var scrollView: Self { .scrollView }
    /// 创建匹配指定轴的最近滚动视图坐标空间查询。
    ///
    /// - Parameter axis: 查询的滚动轴。
    /// - Returns: 该轴对应的滚动空间描述。
    static func scrollView(axis: Axis) -> Self { .scrollView(axis: axis) }
}

/// 保留区域相对于布局方向的镜像规则。
public enum LayoutDirectionBehavior: Sendable, Hashable {
    /// 保持区域的物理坐标及边距，不随布局方向镜像。
    case fixed
    /// 仅在当前方向等于指定方向时水平镜像区域并交换前后边距。
    case mirrors(in: LayoutDirection)
    /// 在 RTL 布局方向下执行水平镜像的默认规则。
    public static var mirrors: Self { .mirrors(in: .rightToLeft) }

    /// 判断当前布局方向是否满足该镜像规则。
    func shouldMirror(_ direction: LayoutDirection) -> Bool {
        if case .mirrors(let target) = self { return direction == target }
        return false
    }
}
