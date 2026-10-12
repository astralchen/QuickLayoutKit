import Foundation
import QuickLayout
import UIKit

/// 绑定到一个 UIKit 视图或纯布局元素的稳定几何锚点。
///
/// 锚点只保存标识和纯值解析函数，不持有视图。纯布局使用 `init(_:)` 创建后，
/// 通过 `Element.geometryAnchor(_:)` 绑定；视图可以直接调用 `UIView.geometryAnchor(_:)`。
public struct Anchor<Value: Sendable>: Sendable {
    /// 锚点的稳定身份；相等性和哈希均以此标识为依据。
    let id: UUID
    /// 从冻结的来源快照生成目标值的解析描述。
    let source: Source

    /// 创建尚未绑定来源的锚点。
    ///
    /// - Parameter source: 需要从来源矩形或坐标中解析的值。
    ///
    /// 使用 `geometryAnchor(_:)` 将该锚点绑定到布局元素后，才能在相应快照中解析。
    public init(_ source: Source) {
        id = UUID()
        self.source = source
    }

    /// 描述如何将来源几何快照转换为指定类型的值。
    public struct Source: Sendable {
        /// 仅依赖冻结快照的解析闭包，不访问实时 UIKit 状态。
        let resolve: @Sendable (GeometryAnchorSnapshot) -> Value
    }
}

extension Anchor: Equatable where Value: Equatable {
    /// 比较锚点身份，不比较来源视图或当前几何值。
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension Anchor: Hashable where Value: Hashable {
    /// 将锚点身份加入哈希器，与身份相等规则保持一致。
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension Anchor.Source where Value == CGRect {
    /// 将来源的完整边界转换到查询者局部坐标空间的矩形来源。
    static var bounds: Self { Self { $0.bounds.applying($0.transform) } }
    /// 创建自定义矩形来源。
    ///
    /// - Parameter rect: 来源视图或元素局部空间中的矩形。
    /// - Returns: 在解析时转换到查询者局部空间的矩形来源。
    static func rect(_ rect: CGRect) -> Self { Self { rect.applying($0.transform) } }
}

public extension Anchor.Source where Value == CGPoint {
    /// 创建自定义点来源。
    ///
    /// - Parameter point: 来源局部空间中的物理坐标。
    /// - Returns: 在解析时转换到查询者局部空间的点来源。
    static func point(_ point: CGPoint) -> Self { Self { point.applying($0.transform) } }
    /// 根据来源边界内的单位坐标创建点来源。
    ///
    /// - Parameter point: 相对于来源宽高的单位坐标；RTL 下水平坐标按 `1 - x` 镜像。
    /// - Returns: 可解析为查询者局部坐标的点来源；不限制单位坐标范围。
    static func unitPoint(_ point: UnitPoint) -> Self {
        Self { snapshot in
            let x = snapshot.direction == .rightToLeft ? 1 - point.x : point.x
            return CGPoint(x: snapshot.bounds.minX + snapshot.bounds.width * x,
                           y: snapshot.bounds.minY + snapshot.bounds.height * point.y)
                .applying(snapshot.transform)
        }
    }
    /// 解析来源顶部前缘的点来源；前后缘随来源布局方向解析。
    static var topLeading: Self { .unitPoint(.topLeading) }
    /// 解析来源顶部中点的点来源；前后缘随来源布局方向解析。
    static var top: Self { .unitPoint(.top) }
    /// 解析来源顶部后缘的点来源；前后缘随来源布局方向解析。
    static var topTrailing: Self { .unitPoint(.topTrailing) }
    /// 解析来源前缘中点的点来源；前后缘随来源布局方向解析。
    static var leading: Self { .unitPoint(.leading) }
    /// 解析来源中心的点来源；前后缘随来源布局方向解析。
    static var center: Self { .unitPoint(.center) }
    /// 解析来源后缘中点的点来源；前后缘随来源布局方向解析。
    static var trailing: Self { .unitPoint(.trailing) }
    /// 解析来源底部前缘的点来源；前后缘随来源布局方向解析。
    static var bottomLeading: Self { .unitPoint(.bottomLeading) }
    /// 解析来源底部中点的点来源；前后缘随来源布局方向解析。
    static var bottom: Self { .unitPoint(.bottom) }
    /// 解析来源底部后缘的点来源；前后缘随来源布局方向解析。
    static var bottomTrailing: Self { .unitPoint(.bottomTrailing) }
}

public extension Anchor.Source {
    /// 将多个来源组合为按输入顺序解析的数组来源。
    ///
    /// - Parameter sources: 共用同一来源快照的解析描述。
    init<T>(_ sources: [Anchor<T>.Source]) where Value == [T] {
        self.init { snapshot in sources.map { $0.resolve(snapshot) } }
    }
    /// 将可选来源包装为可选值来源。
    ///
    /// - Parameter source: 原始来源；`nil` 表示解析结果也为 `nil`。
    init<T>(_ source: Anchor<T>.Source?) where Value == T? {
        self.init { snapshot in source?.resolve(snapshot) }
    }
}

/// 锚点解析使用的来源边界、二维变换及方向快照。
struct GeometryAnchorSnapshot: Equatable, Sendable {
    /// 冻结时来源视图的局部边界。
    let bounds: CGRect
    /// 从来源局部坐标到查询者局部坐标的二维变换。
    let transform: CGAffineTransform
    /// 冻结时来源使用的有效布局方向，用于单位点镜像。
    let direction: LayoutDirection
}

@MainActor
public extension UIView {
    /// 创建并绑定以当前视图为来源的几何锚点。
    ///
    /// - Parameter source: 从视图边界或局部坐标生成值的来源描述。
    /// - Returns: 具有独立身份的锚点；锚点注册表仅弱引用当前视图。
    ///
    /// 几何快照生成时，来源必须与观察者处于同一有效根视图树中。
    func geometryAnchor<Value>(_ source: Anchor<Value>.Source) -> Anchor<Value> {
        let anchor = Anchor(source)
        GeometryAnchorStore.bind(anchor.id, to: self)
        return anchor
    }
}

/// 在主线程维护锚点身份到来源视图的弱引用绑定。
@MainActor
enum GeometryAnchorStore {
    /// 已绑定来源的弱引用索引，绑定和采样时清除已释放的视图。
    private static var sources: [UUID: GeometryWeakView] = [:]

    /// 清理失效弱引用，并将锚点身份绑定到当前视图。
    static func bind(_ id: UUID, to view: UIView) {
        sources = sources.filter { $0.value.view != nil }
        sources[id] = GeometryWeakView(view)
    }

    /// 仅在绑定仍指向该视图时解除关联，避免删除后续重新绑定的来源。
    static func unbind(_ id: UUID, from view: UIView) {
        if sources[id]?.view === view { sources.removeValue(forKey: id) }
    }

    /// 冻结同一根视图树中的有效来源；来源方向取自身有效方向，保留的 `direction` 参数不参与计算。
    static func snapshot(relativeTo view: UIView, direction: LayoutDirection) -> [UUID: GeometryAnchorSnapshot] {
        let root = geometryRoot(view)
        var result: [UUID: GeometryAnchorSnapshot] = [:]
        sources = sources.filter { $0.value.view != nil }
        for (id, reference) in sources {
            guard let source = reference.view, geometryRoot(source) === root,
                  source.superview != nil || source is UIWindow || source !== view else { continue }
            let sourceDirection = (source as? GeometryScopeView)?.layoutDirection ??
                (source.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            result[id] = GeometryAnchorSnapshot(bounds: source.bounds,
                transform: geometryTransform(from: source, to: view), direction: sourceDirection)
        }
        return result
    }
}

/// 弱引用几何来源，避免锚点注册表延长视图生命周期。
@MainActor
final class GeometryWeakView {
    /// 可能已被释放的几何来源视图。
    weak var view: UIView?
    /// 保存视图的弱引用。
    init(_ view: UIView) { self.view = view }
}

/// 沿父视图链查找根节点，用于隔离不同窗口或未连接的视图树。
@MainActor
func geometryRoot(_ view: UIView) -> UIView {
    var root = view
    while let parent = root.superview { root = parent }
    return root
}

/// 通过三个点冻结二维变换，避免旋转后仅转换外接矩形造成的重复扩张。
@MainActor
func geometryTransform(from source: UIView, to target: UIView?) -> CGAffineTransform {
    let origin = source.convert(CGPoint.zero, to: target)
    let x = source.convert(CGPoint(x: 1, y: 0), to: target)
    let y = source.convert(CGPoint(x: 0, y: 1), to: target)
    return CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
                             c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
}
