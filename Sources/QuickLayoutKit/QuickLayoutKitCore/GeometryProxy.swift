import QuickLayout
import UIKit

/// 布局应用后的不可变二维几何快照；查询方法不读取 UIView 或实时布局状态。
public struct GeometryProxy: Sendable, Equatable {
    // MARK: - 几何快照

    /// 布局应用时冻结的元素边界尺寸，单位为点。
    public let size: CGSize
    /// 冻结的安全区域方向性边距，前后缘按该快照的布局方向解释。
    public let safeAreaInsets: EdgeInsets
    /// 冻结时的观察者布局方向，供边距和区域镜像使用。
    private let direction: LayoutDirection
    /// 当前元素边界在各个已解析空间中的矩形。
    private var frames: [GeometryCoordinateSpace: CGRect] = [:]
    /// 各个已解析空间的边界在观察者局部空间中的矩形。
    private var spaceBounds: [GeometryCoordinateSpace: CGRect] = [:]
    /// 同一有效视图树中锚点来源的冻结几何，以稳定身份索引。
    private var anchors: [UUID: GeometryAnchorSnapshot] = [:]
    /// 相对于所选容器内容区域仍需避让的方向性边距。
    private var contentInsets: EdgeInsets = .zero
    /// 容器角内缩区域与当前元素相交的尺寸。
    private var corners = RectangleCornerInsets()
    /// 用于同心圆角计算的容器矩形和原始半径；无法解析时为 `nil`。
    private var cornerSource: GeometryCornerSnapshot?
    /// 冻结的系统保留区域，包括活动和非活动区域。
    var regionSnapshots: [GeometryReservedSnapshot] = []

    /// 比较全部已存储的几何值，供观察器判断是否需要发送新快照。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.direction == rhs.direction && lhs.frames == rhs.frames &&
        lhs.spaceBounds == rhs.spaceBounds && lhs.anchors == rhs.anchors && lhs.corners == rhs.corners &&
        lhs.cornerSource == rhs.cornerSource && lhs.regionSnapshots == rhs.regionSnapshots &&
        geometryInsetsEqual(lhs.safeAreaInsets, rhs.safeAreaInsets) && geometryInsetsEqual(lhs.contentInsets, rhs.contentInsets)
    }

    // MARK: - 坐标空间与锚点

    /// 返回元素边界在指定坐标空间中的矩形。
    ///
    /// 此方法读取已冻结的几何信息，不查询实时视图状态。
    ///
    /// - Parameter coordinateSpace: 需要查询的坐标空间。
    /// - Returns: 目标空间中的矩形；目标不存在时使用全局矩形，
    ///   全局矩形也不存在时使用以零为原点、大小为 `size` 的矩形。
    @_disfavoredOverload
    public func frame(in coordinateSpace: GeometryCoordinateSpace) -> CGRect {
        frames[coordinateSpace] ?? frames[.global] ?? CGRect(origin: .zero, size: size)
    }

    /// 返回元素边界在指定空间中的冻结矩形。
    ///
    /// - Parameter coordinateSpace: 局部、全局、命名或滚动空间描述。
    /// - Returns: 已解析的目标矩形；找不到目标时回退到全局矩形，再回退到零原点的元素尺寸。
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect {
        frames[coordinateSpace.coordinateSpace] ?? frames[.global] ?? CGRect(origin: .zero, size: size)
    }

    /// 返回指定命名或滚动空间在当前局部空间中的边界。
    ///
    /// - Parameter coordinateSpace: 需要查询边界的坐标空间。
    /// - Returns: 已冻结的局部边界；该空间未被解析时返回 `nil`，不回退到全局空间。
    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
        spaceBounds[coordinateSpace.coordinateSpace]
    }

    /// 返回锚点在当前几何快照中的解析值。
    ///
    /// - Parameter anchor: 需要解析的几何锚点。
    /// - Returns: 转换到观察者局部空间的值；采样时来源未绑定、已失效或不在同一根视图树中时为 `nil`。
    ///
    /// 快照生成后不再读取来源视图。来源随后发生变化或卸载，不会修改已有快照的解析结果。
    public func resolve<Value>(_ anchor: Anchor<Value>) -> Value? {
        anchors[anchor.id].map(anchor.source.resolve)
    }

    /// 解析已存在于此快照中的锚点。
    ///
    /// - Parameter anchor: 需要读取的几何锚点。
    /// - Returns: 转换到观察者局部空间的值。
    /// - Important: 锚点不在快照中时触发前置条件失败。来源可能失效时使用 `resolve(_:)`。
    public subscript<Value>(anchor: Anchor<Value>) -> Value {
        guard let snapshot = anchors[anchor.id] else {
            preconditionFailure("Anchor 来源不在当前有效布局树中；可使用 resolve(_:) 处理失效来源。")
        }
        return anchor.source.resolve(snapshot)
    }

    // MARK: - 容器几何

    /// 已知容器角内缩与当前元素重叠的部分，不从设备型号或安全区推测。
    @available(iOS 26.0, *)
    public var containerCornerInsets: RectangleCornerInsets { corners }

    /// 相对于当前元素完整局部矩形的容器同心圆角；无法解析来源时为 `nil`。
    @available(iOS 27.0, *)
    public var concentricCornerRadii: RectangleCornerRadii? {
        concentricCornerRadii(in: CGRect(origin: .zero, size: size))
    }

    /// 对当前局部空间中的矩形计算原生容器同心圆角。
    ///
    /// 使用两条相邻边中较大的内缩距离，并限制到矩形短边的一半。
    /// 不可解析容器形状时返回 `nil`；不模拟 SwiftUI 的任意 Shape 几何。
    ///
    /// - Parameter frame: 当前局部坐标空间中需要计算圆角的矩形。
    /// - Returns: 四角的方向性半径；没有可用容器半径来源时为 `nil`。
    @available(iOS 27.0, *)
    public func concentricCornerRadii(in frame: CGRect) -> RectangleCornerRadii? {
        guard let source = cornerSource else { return nil }
        let container = source.frame
        let limit = max(0, min(frame.width, frame.height) / 2)
        func radius(_ value: CGFloat, _ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
            min(limit, max(0, value - max(0, max(dx, dy))))
        }
        let left = frame.minX - container.minX, right = container.maxX - frame.maxX
        let top = frame.minY - container.minY, bottom = container.maxY - frame.maxY
        let leading = direction == .rightToLeft ? right : left
        let trailing = direction == .rightToLeft ? left : right
        return RectangleCornerRadii(
            topLeading: radius(source.radii.topLeading, leading, top),
            bottomLeading: radius(source.radii.bottomLeading, leading, bottom),
            bottomTrailing: radius(source.radii.bottomTrailing, trailing, bottom),
            topTrailing: radius(source.radii.topTrailing, trailing, top))
    }

    /// 返回相对于容器内容区域仍需避让的边距。
    ///
    /// - Parameters:
    ///   - guide: 内容区域参考；当前仅提供 `.container`。
    ///   - edges: 需要查询的边缘，默认为全部边缘。
    /// - Returns: 快照中对应边缘的非负方向性边距，未选择的边缘为零。
    ///
    /// 优先使用最近显式声明的容器内容边距；没有声明时使用直接父视图的
    /// `layoutMarginsGuide`，没有父视图时为零。
    @available(iOS 27.1, *)
    public func contentMargins(for guide: ContentMarginGuide, edges: EdgeSet = .all) -> EdgeInsets {
        EdgeInsets(top: edges.contains(.top) ? contentInsets.top : 0,
                   leading: edges.contains(.leading) ? contentInsets.leading : 0,
                   bottom: edges.contains(.bottom) ? contentInsets.bottom : 0,
                   trailing: edges.contains(.trailing) ? contentInsets.trailing : 0)
    }

    /// 返回快照中符合条件的系统保留区域。
    ///
    /// - Parameters:
    ///   - kind: 需要查询的遮挡或分隔区域类别。
    ///   - options: 查询选项，默认仅包含活动区域。
    ///   - layoutDirectionBehavior: 水平镜像规则，默认在 RTL 下镜像。
    /// - Returns: 包含避让边距的区域矩形及元数据；没有匹配区域时返回空数组。
    ///
    /// `frame` 已包含 `margins`。镜像以当前元素宽度为基准，并同时交换前后边距。
    @available(iOS 27.1, *)
    public func reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [],
                                layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion] {
        regionSnapshots.compactMap { region in
            guard region.division == (kind == .division), region.active || options.contains(.includeInactive) else { return nil }
            var frame = region.frame
            var margins = region.margins
            if layoutDirectionBehavior.shouldMirror(direction) {
                frame.origin.x = size.width - frame.maxX
                swap(&margins.leading, &margins.trailing)
            }
            return ReservedRegion(id: .init(value: region.id), kind: kind, frame: frame,
                                  margins: margins, isActive: region.active)
        }
    }

    // MARK: - 快照构建

    /// 在主线程冻结视图几何，仅使用从视图树继承的显式作用域。
    @MainActor
    package init(observing view: UIView, layoutDirection: LayoutDirection) {
        self.init(observing: view, layoutDirection: layoutDirection, scopes: [])
    }

    /// 冻结视图树、命名空间、锚点与容器信息；完成后查询不再访问 UIKit。
    @MainActor
    init(observing view: UIView, layoutDirection: LayoutDirection, scopes: [GeometryScope]) {
        size = view.bounds.size
        direction = layoutDirection
        let insets = view.safeAreaInsets
        safeAreaInsets = geometryInsets(top: insets.top, left: insets.left, bottom: insets.bottom,
                                        right: insets.right, direction: direction)
        let normalization = CGAffineTransform(translationX: -view.bounds.minX, y: -view.bounds.minY)
        frames[.local] = CGRect(origin: .zero, size: size)
        frames[.global] = view.convert(view.bounds, to: nil)
        func local(_ rect: CGRect, from source: UIView) -> CGRect {
            source.convert(rect, to: view).applying(normalization)
        }
        func register(_ space: GeometryCoordinateSpace, _ source: UIView) {
            frames[space] = view.convert(view.bounds, to: source)
            spaceBounds[space] = local(source.bounds, from: source)
        }
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                if frames[.scrollView] == nil { register(.scrollView, scroll) }
                for axis in [Axis.horizontal, .vertical] where frames[.scrollViewAxis(axis)] == nil {
                    let matches: Bool
                    if let declared = scroll as? any GeometryScrollAxisProviding {
                        matches = declared.geometryScrollAxis == axis
                    } else if axis == .horizontal {
                        matches = scroll.alwaysBounceHorizontal || scroll.contentSize.width + scroll.adjustedContentInset.left + scroll.adjustedContentInset.right > scroll.bounds.width
                    } else {
                        matches = scroll.alwaysBounceVertical || scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height
                    }
                    if matches { register(.scrollViewAxis(axis), scroll) }
                }
            }
            ancestor = current.superview
        }
        // 由外到内覆盖，最近同名作用域生效。标记是元素兄弟视图，不能只遍历 UIKit 祖先。
        var combinedScopes = GeometryInheritedScopes.scopes(for: view)
        for scope in scopes where !combinedScopes.contains(where: { $0 === scope }) { combinedScopes.append(scope) }
        let activeScopes = combinedScopes.filter { $0.view.superview != nil && geometryRoot($0.view) === geometryRoot(view) }
        for scope in activeScopes {
            if let name = scope.view.name { register(name, scope.view) }
        }
        anchors = GeometryAnchorStore.snapshot(relativeTo: view, direction: direction).mapValues {
            GeometryAnchorSnapshot(bounds: $0.bounds, transform: $0.transform.concatenating(normalization), direction: $0.direction)
        }
        let contentScope = activeScopes.last { $0.view.container?.contentMargins != nil }
        if let source = contentScope, let margins = source.view.container?.contentMargins {
            let rtl = source.view.layoutDirection == .rightToLeft
            let rect = source.view.bounds.inset(by: UIEdgeInsets(top: margins.top,
                left: rtl ? margins.trailing : margins.leading, bottom: margins.bottom,
                right: rtl ? margins.leading : margins.trailing))
            contentInsets = remainingInsets(local(rect, from: source.view), size: size, direction: direction)
        } else if let host = view.superview {
            contentInsets = remainingInsets(local(host.layoutMarginsGuide.layoutFrame, from: host), size: size, direction: direction)
        }
        if let source = activeScopes.last(where: { $0.view.container?.cornerInsets != nil }),
           let insets = source.view.container?.cornerInsets {
            let mapped: RectangleCornerInsets
            if source.view.layoutDirection != direction {
                mapped = RectangleCornerInsets(topLeading: insets.topTrailing, topTrailing: insets.topLeading,
                    bottomLeading: insets.bottomTrailing, bottomTrailing: insets.bottomLeading)
            } else { mapped = insets }
            corners = overlappingCorners(mapped, container: local(source.view.bounds, from: source.view), size: size, direction: direction)
        }
        if let source = activeScopes.last(where: { $0.view.container?.cornerRadii != nil }), let radii = source.view.container?.cornerRadii {
            let mapped: RectangleCornerRadii
            if source.view.layoutDirection != direction {
                mapped = RectangleCornerRadii(topLeading: radii.topTrailing, bottomLeading: radii.bottomTrailing,
                    bottomTrailing: radii.bottomLeading, topTrailing: radii.topLeading)
            } else { mapped = radii }
            cornerSource = GeometryCornerSnapshot(frame: local(source.view.bounds, from: source.view), radii: mapped)
        } else if #available(iOS 26.0, *) {
            var candidate = view.superview
            while let source = candidate {
                let tl = source.effectiveRadius(corner: .topLeft), tr = source.effectiveRadius(corner: .topRight)
                let bl = source.effectiveRadius(corner: .bottomLeft), br = source.effectiveRadius(corner: .bottomRight)
                if max(tl, tr, bl, br) > 0 {
                    let rtl = direction == .rightToLeft
                    cornerSource = GeometryCornerSnapshot(frame: local(source.bounds, from: source), radii: .init(
                        topLeading: rtl ? tr : tl, bottomLeading: rtl ? br : bl,
                        bottomTrailing: rtl ? bl : br, topTrailing: rtl ? tl : tr))
                    break
                }
                candidate = source.superview
            }
        }
        if #available(iOS 27.1, *), let window = view.window {
            let ids = GeometryWindowMonitor.forWindow(window).regionIdentifiers
            for kind in [UIView.ReservedRegion.Kind.occlusion, .division] {
                regionSnapshots += view.reservedRegions(kind: kind, options: .includeInactive).map { region in
                    GeometryReservedSnapshot(id: ids.id(for: region.id), division: kind == .division,
                        frame: region.frame.applying(normalization),
                        margins: EdgeInsets(top: region.margins.top, leading: region.margins.left,
                                           bottom: region.margins.bottom, trailing: region.margins.right), active: region.isActive)
                }
            }
        }
    }
}

/// 同心圆角查询使用的容器边界和半径快照。
private struct GeometryCornerSnapshot: Equatable, Sendable {
    /// 容器边界在观察者局部空间中的矩形。
    let frame: CGRect
    /// 映射到观察者布局方向后的容器半径。
    let radii: RectangleCornerRadii
}

/// 计算内容矩形之外仍需避让的非负边距，并映射为方向性边距。
private func remainingInsets(_ content: CGRect, size: CGSize, direction: LayoutDirection) -> EdgeInsets {
    geometryInsets(top: max(0, content.minY), left: max(0, content.minX),
                   bottom: max(0, size.height - content.maxY), right: max(0, size.width - content.maxX), direction: direction)
}

/// 计算各角内缩矩形与元素局部边界的交集，无交集的角返回零。
private func overlappingCorners(_ insets: RectangleCornerInsets, container: CGRect, size: CGSize,
                                direction: LayoutDirection) -> RectangleCornerInsets {
    let bounds = CGRect(origin: .zero, size: size)
    func overlap(_ inset: CGSize, left: Bool, top: Bool) -> CGSize {
        let rect = CGRect(x: left ? container.minX : container.maxX - inset.width,
                          y: top ? container.minY : container.maxY - inset.height,
                          width: max(0, inset.width), height: max(0, inset.height)).intersection(bounds)
        return rect.isNull ? .zero : rect.size
    }
    let leading = direction != .rightToLeft
    return RectangleCornerInsets(topLeading: overlap(insets.topLeading, left: leading, top: true),
        topTrailing: overlap(insets.topTrailing, left: !leading, top: true),
        bottomLeading: overlap(insets.bottomLeading, left: leading, top: false),
        bottomTrailing: overlap(insets.bottomTrailing, left: !leading, top: false))
}
