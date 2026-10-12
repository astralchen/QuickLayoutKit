import Foundation
import QuickLayout
import UIKit

/// 用于测量和放置一组元素的类型。
///
/// 遵循该协议的类型实现与 SwiftUI `Layout` 相同的两阶段布局模型：先返回容器尺寸，
/// 再将每个子元素放置在结果边界内。
public protocol LayoutAlgorithm {

    /// 布局在测量阶段和放置阶段之间共享的缓存类型。
    associatedtype Cache = Void

    /// 自定义布局接收的子元素集合类型。
    typealias Subviews = LayoutSubviews

    /// 创建由测量阶段和放置阶段共享的缓存。
    ///
    /// - Parameter subviews: 布局中的子元素代理集合。
    /// - Returns: 新创建的布局缓存。
    func makeCache(subviews: Subviews) -> Cache

    /// 在新的布局过程中刷新现有缓存。
    ///
    /// - Parameters:
    ///   - cache: 要更新的现有布局缓存。
    ///   - subviews: 当前布局中的子元素代理集合。
    func updateCache(_ cache: inout Cache, subviews: Subviews)

    /// 返回组合元素在指定尺寸建议下的尺寸。
    ///
    /// - Parameters:
    ///   - proposal: 父布局提出的尺寸建议。
    ///   - subviews: 要测量的子元素代理集合。
    ///   - cache: 当前布局缓存。
    /// - Returns: 组合元素在建议约束下所需的尺寸。
    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize

    /// 为每个子元素指定位置和尺寸建议。
    ///
    /// - Parameters:
    ///   - bounds: 用于放置子元素的容器边界。
    ///   - proposal: 父布局提出的尺寸建议。
    ///   - subviews: 要放置的子元素代理集合。
    ///   - cache: 当前布局缓存。
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    )
}

public extension LayoutAlgorithm where Cache == Void {

    /// 为无需缓存的布局提供空缓存的默认实现。
    ///
    /// - Parameter subviews: 当前子元素集合；默认实现不使用该参数。
    func makeCache(subviews: Subviews) {}
}

public extension LayoutAlgorithm {

    /// 默认保留现有缓存；需要随子元素变化更新缓存时应自行实现。
    ///
    /// - Parameters:
    ///   - cache: 保持不变的现有缓存。
    ///   - subviews: 当前子元素集合。
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    /// 使用该布局算法构建 QuickLayout 元素。
    ///
    /// - Parameter content: 生成布局子元素的构建器。
    /// - Returns: 使用该算法测量和放置内容的布局元素。
    func callAsFunction(
        @FastArrayBuilder<Element> content: () -> [Element]
    ) -> some Element & Layout {
        LayoutAlgorithmElement(
            algorithm: self,
            children: content()
        )
    }
}

// MARK: - 子元素代理

/// 自定义布局中子元素代理的随机访问集合。
public struct LayoutSubviews: RandomAccessCollection {

    /// 集合索引的类型。
    public typealias Index = Int

    /// 集合元素的类型。
    public typealias Element = LayoutSubview

    /// 按声明顺序保存的子元素代理。
    private let subviews: [LayoutSubview]

    /// 为每个子元素创建独立放置存储，本次测量内共享代理状态。
    init(children: [QuickLayout.Element]) {
        subviews = children.map { child in
            LayoutSubview(storage: LayoutSubviewStorage(element: child))
        }
    }

    /// 集合第一个元素的位置。
    public var startIndex: Int { subviews.startIndex }

    /// 集合末尾之后的位置。
    public var endIndex: Int { subviews.endIndex }

    /// 访问指定位置的子元素代理。
    ///
    /// - Parameter position: 要访问的集合位置。
    public subscript(position: Int) -> LayoutSubview {
        subviews[position]
    }

    /// 清除上一次放置记录，确保新一轮放置不沿用过期坐标。
    func resetPlacements() {
        subviews.forEach { $0.storage.placement = nil }
    }
}

/// `LayoutAlgorithm` 用于测量和放置单个子元素的代理。
public struct LayoutSubview: Equatable {

    /// 代理共享的元素与放置状态，复制代理仍引用同一存储。
    fileprivate let storage: LayoutSubviewStorage

    /// 子元素的 QuickLayout 布局优先级。
    public var priority: Double {
        Double(storage.element.quick_layoutPriority())
    }

    /// 返回子元素中与指定布局键关联的自定义值。
    ///
    /// - Parameter key: 要读取的布局值键类型。
    public subscript<Key: LayoutValueKey>(key: Key.Type) -> Key.Value {
        storage.element._layoutValue(for: key)
    }

    /// 请求子元素为指定尺寸建议选择合适的尺寸。
    ///
    /// - Parameter proposal: 向子元素提出的尺寸建议。
    /// - Returns: 子元素选择的尺寸。
    public func sizeThatFits(_ proposal: ProposedSize) -> CGSize {
        let dimensions = dimensions(in: proposal)
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    /// 请求子元素返回指定尺寸建议下的尺寸和对齐参考线。
    ///
    /// - Parameter proposal: 向子元素提出的尺寸建议。
    /// - Returns: 子元素的尺寸和对齐参考线。
    public func dimensions(in proposal: ProposedSize) -> ElementDimensions {
        storage.element.quick_layoutThatFits(proposal.quickLayoutProposal).dimensions
    }

    /// 将子元素放置在布局容器中的指定点。
    ///
    /// 锚点使用单位坐标，其中 `(0, 0)` 表示子元素左上角，`(1, 1)` 表示右下角。
    ///
    /// - Parameters:
    ///   - position: 锚点在布局容器坐标空间中的位置。
    ///   - anchor: 用于定位子元素的单位锚点。
    ///   - proposal: 放置子元素时使用的尺寸建议。
    public func place(
        at position: CGPoint,
        anchor: UnitPoint = UnitPoint(x: 0, y: 0),
        proposal: ProposedSize = .unspecified
    ) {
        storage.placement = LayoutSubviewPlacement(
            position: sanitize(position),
            anchor: UnitPoint(
                x: sanitize(anchor.x),
                y: sanitize(anchor.y)
            ),
            proposal: proposal
        )
    }

    /// 比较两个代理是否引用同一份子元素存储。
    public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
        lhs.storage === rhs.storage
    }
}

// MARK: - 测量与放置存储

/// 将值类型代理连接到同一元素及可变放置记录的引用存储。
private final class LayoutSubviewStorage {
    /// 需要测量并放置的原始元素。
    let element: Element
    /// 本轮最后一次声明的放置信息；尚未放置时为 `nil`。
    var placement: LayoutSubviewPlacement?

    /// 保存原始元素，放置记录初始为空。
    init(element: Element) {
        self.element = element
    }
}

/// 放置阶段记录的位置、单位锚点和测量建议。
private struct LayoutSubviewPlacement {
    /// 锚点在容器中的物理位置。
    let position: CGPoint
    /// 子元素内部用于对齐位置的单位坐标。
    let anchor: UnitPoint
    /// 最终测量子元素时使用的建议尺寸。
    let proposal: ProposedSize
}

/// 跨同一布局元素的多次测量复用缓存，并串行保护访问。
private final class LayoutAlgorithmCacheBox<Cache> {
    /// 保护缓存构建、更新及使用过程的递归锁。
    private let lock = NSRecursiveLock()
    /// 延迟创建的算法缓存；首次访问前为 `nil`。
    private var cache: Cache?

    /// 在锁内首次构建或更新缓存，再执行依赖该缓存的测量与放置操作。
    func withCache<Result>(
        make: () -> Cache,
        update: (inout Cache) -> Void,
        operation: (inout Cache) -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }

        if cache == nil {
            cache = make()
        } else {
            update(&cache!)
        }
        return operation(&cache!)
    }
}

// MARK: - QuickLayout 适配

/// 将自定义两阶段布局算法适配为 QuickLayout 元素。
private struct LayoutAlgorithmElement<Algorithm: LayoutAlgorithm>: Layout {

    /// 负责容器测量和子元素放置的布局算法。
    let algorithm: Algorithm
    /// 按声明顺序保存的原始子元素。
    let children: [Element]
    /// 在该元素的多次测量之间保留缓存的引用容器。
    let cacheBox: LayoutAlgorithmCacheBox<Algorithm.Cache>

    /// 保存算法与子元素，并创建尚未初始化的缓存容器。
    init(algorithm: Algorithm, children: [Element]) {
        self.algorithm = algorithm
        self.children = children
        cacheBox = LayoutAlgorithmCacheBox()
    }

    /// 在同一次缓存访问中测量容器、清空放置记录并生成最终节点树。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let proposal = ProposedSize(quickLayoutProposal: proposedSize)
        let subviews = LayoutSubviews(children: children)

        return cacheBox.withCache(
            make: { algorithm.makeCache(subviews: subviews) },
            update: { algorithm.updateCache(&$0, subviews: subviews) }
        ) { cache in
            let size = sanitize(
                algorithm.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                )
            )

            subviews.resetPlacements()
            algorithm.placeSubviews(
                in: CGRect(origin: .zero, size: size),
                proposal: proposal,
                subviews: subviews,
                cache: &cache
            )

            return layoutNode(size: size, subviews: subviews)
        }
    }

    /// 采用所有子元素中伸缩能力最强的弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        children.reduce(.fixedSize) { result, child in
            max(result, child.quick_flexibility(for: axis))
        }
    }

    /// 采用子元素中的最高布局优先级，空集合返回零。
    func quick_layoutPriority() -> CGFloat {
        children.map { $0.quick_layoutPriority() }.max() ?? 0
    }

    /// 按显示层级稳定排序后提取视图，使 UIKit 顺序与布局顺序一致。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        orderedSubviews(LayoutSubviews(children: children)).forEach { subview in
            subview.storage.element.quick_extractViewsIntoArray(&views)
        }
    }

    /// 将放置记录转换为节点；未显式放置的元素使用原点和理想尺寸建议。
    private func layoutNode(size: CGSize, subviews: LayoutSubviews) -> LayoutNode {
        let layers: [Element] = orderedSubviews(subviews).map { subview in
            let placement = subview.storage.placement ?? LayoutSubviewPlacement(
                position: .zero,
                anchor: UnitPoint(x: 0, y: 0),
                proposal: .unspecified
            )
            let childLayout = subview.storage.element.quick_layoutThatFits(
                placement.proposal.quickLayoutProposal
            )
            let origin = CGPoint(
                x: placement.position.x - placement.anchor.x * childLayout.size.width,
                y: placement.position.y - placement.anchor.y * childLayout.size.height
            )
            return positioned(
                childLayout,
                at: origin,
                in: size
            )
        }

        guard !layers.isEmpty else {
            return FixedFrameElement(
                child: EmptyElement(),
                width: size.width,
                height: size.height,
                alignment: .topLeading
            ).quick_layoutThatFits(size)
        }

        return ZStackElement(children: layers, alignment: .topLeading)
            .quick_layoutThatFits(size)
    }

    /// 按显示层级升序排列，层级相同时保留原声明顺序。
    private func orderedSubviews(_ subviews: LayoutSubviews) -> [LayoutSubview] {
        subviews.enumerated()
            .sorted { lhs, rhs in
                let lhsZIndex = lhs.element[_ZIndexLayoutValueKey.self]
                let rhsZIndex = rhs.element[_ZIndexLayoutValueKey.self]
                return lhsZIndex == rhsZIndex
                    ? lhs.offset < rhs.offset
                    : lhsZIndex < rhsZIndex
            }
            .map(\.element)
    }
}

/// 包装已经测量的节点，供定位组合复用。
private struct PrecomputedLayoutElement: Layout {
    /// 已完成测量的布局节点，供包装层直接复用。
    let layout: LayoutNode

    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }
    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 将物理位置转换为方向性偏移，避免 RTL 对物理坐标再次镜像。
private func positioned(
    _ layout: LayoutNode,
    at origin: CGPoint,
    in containerSize: CGSize
) -> Element {
    let horizontalOffset: CGFloat
    if LayoutContext.layoutDirection == .rightToLeft {
        let leadingOrigin = containerSize.width - layout.size.width
        horizontalOffset = leadingOrigin - origin.x
    } else {
        horizontalOffset = origin.x
    }

    let offsetChild = OffsetElement(
        child: PrecomputedLayoutElement(layout: layout),
        offset: CGPoint(x: horizontalOffset, y: origin.y)
    )
        // 避免外层固定框架解析顶部前缘对齐时，子元素的对齐参考线改变此处的物理位置。
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }

    let positionedChild = FixedFrameElement(
        child: offsetChild,
        width: containerSize.width,
        height: containerSize.height,
        alignment: .topLeading
    )
    return positionedChild
        // 按父元素的布局方向解析包装层参考线，避免局部布局方向覆盖向外泄漏物理补偿。
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }
}

/// 将非有限数值归零。
private func sanitize(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

/// 逐坐标清除非有限位置值。
private func sanitize(_ point: CGPoint) -> CGPoint {
    CGPoint(x: sanitize(point.x), y: sanitize(point.y))
}

/// 将非有限尺寸归零，并限制宽高为非负数。
private func sanitize(_ size: CGSize) -> CGSize {
    CGSize(
        width: max(0, sanitize(size.width)),
        height: max(0, sanitize(size.height))
    )
}
