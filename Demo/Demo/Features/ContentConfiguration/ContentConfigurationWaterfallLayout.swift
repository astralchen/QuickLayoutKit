import UIKit
import QuickLayout

// 一次有效测量对应的内容和约束。提供稳定 ID 时，条目移动不会仅因 IndexPath 变化而丢失缓存。
private struct WaterfallMeasurementKey: Hashable {
    let id: AnyHashable
    let revision: Int
    let crossLength: CGFloat
    // 自适应模式为估算长度，固定模式为最终长度；该长度改变后旧 key 不再匹配。
    let estimatedLength: CGFloat
    let horizontal: Bool
    let selfSizing: Bool
    let layoutDirection: Int
    let contentSizeCategory: String
    let displayScale: CGFloat
    // 全局尺寸配置版本；使旧布局属性返回的拟合结果失效。
    let generation: Int
}

// 将测量条件随布局属性传递给 UIKit；复制和相等性比较必须包含自定义状态。
private final class WaterfallAttributes: UICollectionViewLayoutAttributes {
    var measurementKey: WaterfallMeasurementKey?
    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! WaterfallAttributes
        result.measurementKey = measurementKey
        return result
    }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WaterfallAttributes else { return false }
        return measurementKey == other.measurementKey && super.isEqual(object)
    }
}

// 分别控制测量缓存和几何缓存的失效；仅更新固定补充视图时两者均可保留。
private final class WaterfallInvalidationContext: UICollectionViewLayoutInvalidationContext {
    // 本次 preferred attributes 回调返回的主轴长度。nil 表示没有新测量。
    var measurement: (WaterfallMeasurementKey, CGFloat)?
    // 默认 false。为 true 时，仅合并 measurement，不清除其他测量结果。
    var preservesMeasurements = false
    // 默认 true。仅滚动位置或固定开关变化时可设为 false。
    var updatesGeometry = true
}

/// 将条目依次放入当前最短列或行的集合视图布局。
/// 主轴指滚动方向，交叉轴指与滚动方向垂直的方向。各 section 独立排列，按数据源顺序连接。
/// 布局提供内容测量所需的约束与弹性，并通过 UIKit 的 preferred attributes 回调接收主轴长度。
/// NOTE: 本布局不创建测量 cell，也不主动调用内容视图的 sizeThatFits(_:)。
final class ContentConfigurationWaterfallLayout: UICollectionViewLayout {
    /// 一个 section 的完整布局配置；尺寸、间距及补充视图仅由此对象描述。
    struct Section {
        /// 列数（纵向）或行数（横向）。默认值为 2，最小值为 1。
        var laneCount = 2
        /// 同一列或行内的间距。默认值为 10pt。
        var interItemSpacing: CGFloat = 10
        /// 相邻列或行的间距。默认值为 10pt。
        var interLaneSpacing: CGFloat = 10
        /// header 之后、footer 之前的方向性边距。默认值为 .zero。
        var contentInsets: NSDirectionalEdgeInsets = .zero
        /// 交叉轴边距的参考边界。默认值为 .automatic，继承全局 configuration。
        var contentInsetsReference: UIContentInsetsReference = .automatic
        /// 主轴尺寸描述。默认值为 .absolute(50)；.estimated 启用 UIKit 自适应测量。
        /// 支持 absolute、estimated、fractionalWidth 和 fractionalHeight；比例基于可用容器。
        var itemLengthDimension: NSCollectionLayoutDimension = .absolute(50)
        /// 可选的条目尺寸描述提供者。参数为 section 内的 item 索引和原生布局环境。
        var itemLengthDimensionProvider: ((Int, NSCollectionLayoutEnvironment) -> NSCollectionLayoutDimension?)?
        /// 边界补充视图。支持主轴两端各一个元素，使用任意唯一 elementKind。
        /// 纵向使用 top/bottom，横向使用 leading/trailing；交叉轴使用 fractionalWidth/Height(1)。
        /// 主轴长度须为 absolute，extendsBoundary 须为 true；offset 与 contentInsets 须为零。
        /// 不支持的描述忽略并输出 DEBUG 诊断；补充视图自适应及任意锚点不在本布局范围内。
        var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
        /// section 背景。默认值为空；同一 section 内 elementKind 必须唯一。
        /// 支持 background(elementKind:) 的 contentInsets 和 zIndex；视图通过布局的 register 方法注册。
        var decorationItems: [NSCollectionLayoutDecorationItem] = []
    }

    /// 布局全局配置。采用值语义，修改并赋值后立即使布局失效。
    struct Configuration: Equatable {
        /// 所有 section 共用的滚动方向。默认值为 .vertical。
        var scrollDirection: UICollectionView.ScrollDirection = .vertical
        /// 相邻 section 的主轴间距。默认值为 0，不属于背景或固定范围。
        var interSectionSpacing: CGFloat = 0
        /// section 边距参考边界。默认值为 .none，仍始终尊重 adjustedContentInset。
        var contentInsetsReference: UIContentInsetsReference = .none
    }

    /// 与 UICollectionViewCompositionalLayout 的 provider 参数保持一致。
    typealias SectionProvider = (Int, NSCollectionLayoutEnvironment) -> Section?

    /// 按 section 索引提供完整配置；返回 nil 时使用 Section() 的默认值。
    /// 闭包不得重入布局或修改数据源；捕获数据变化后调用 invalidateSectionConfigurations(reason:)。
    private(set) var sectionProvider: SectionProvider?

    /// 布局全局配置。非法间距保留原值；仅方向变化时清除全部测量。
    var configuration = Configuration() {
        didSet {
            if !valid(configuration.interSectionSpacing) { configuration.interSectionSpacing = oldValue.interSectionSpacing }
            guard oldValue != configuration else { return }
            if oldValue.scrollDirection != configuration.scrollDirection { metricsChanged("direction") }
            else { invalidateSectionConfigurations(reason: "configuration") }
        }
    }

    @available(*, unavailable, message: "Use init(section:) or init(sectionProvider:)")
    override init() { fatalError("Use a section initializer") }

    /// 对所有 section 使用相同配置；装饰描述在初始化时复制。
    convenience init(section: Section, configuration: Configuration = Configuration()) {
        let snapshot = section.snapshot()
        self.init(sectionProvider: { _, _ in snapshot }, configuration: configuration)
    }

    /// 使用原生布局环境提供各 section 配置。
    init(sectionProvider: @escaping SectionProvider, configuration: Configuration = Configuration()) {
        self.sectionProvider = sectionProvider
        self.configuration = configuration
        super.init()
        if !valid(self.configuration.interSectionSpacing) { self.configuration.interSectionSpacing = 0 }
    }

    @available(*, unavailable, message: "Use a section initializer")
    required init?(coder: NSCoder) { fatalError("Use a section initializer") }

    /// 提供给 cell 内容配置的测量策略；与布局属性使用相同的 section 指标。
    struct ItemSizing: Equatable {
        /// 内容测量的约束。自适应主轴为 infinity，固定轴为布局计算的有限长度。
        let constraint: CGSize
        /// 水平尺寸弹性。仅横向自适应时为 fullyFlexible，否则为 fixedSize。
        let horizontalFlexibility: Flexibility
        /// 垂直尺寸弹性。仅纵向自适应时为 fullyFlexible，否则为 fixedSize。
        let verticalFlexibility: Flexibility
    }

    /// 数据源条目的测量身份。位置改变后 identifier 应保持稳定。
    struct ItemMetadata {
        let identifier: AnyHashable
        var contentVersion: Int = 0
    }

    /// 测量缓存及滚动锚点的身份提供者。默认使用 IndexPath 和版本 0。
    /// 数据更新时返回新内容版本并重新配置 cell；设置闭包后使现有测量失效。
    var itemMetadataProvider: ((IndexPath) -> ItemMetadata)? {
        didSet { metricsChanged("item-metadata-provider") }
    }

    /// 显式使 section 配置或测量失效后同步执行的回调。默认值为 nil。
    /// 调用方应在后续布局周期检查测量策略，仅在策略改变时更新内容配置。
    /// NOTE: 回调执行时实际尺寸可能尚未改变；避免在回调中重入 Diffable Data Source 的 snapshot 更新。
    var sizingInvalidationHandler: (() -> Void)?

    /// 已接收的有效拟合长度更新次数。初始值为 0；布局失效时不重置。
    /// 仅用于诊断，不表示 UIKit 或内容视图的总测量次数。
    private(set) var acceptedMeasurementCount = 0
    private var generation = 0
    private var lengths: [WaterfallMeasurementKey: CGFloat] = [:]
    private var geometry = Geometry()
    private var geometryNeedsUpdate = true
    private var preparedBoundsSize: CGSize = .zero
    // 保存 UIKit 返回的物理边距，用于检测容器变化；不作为方向性 section 边距使用。
    private var preparedInsets: UIEdgeInsets = .zero
    private var preparedRTL = false
    // 元素为稳定 ID 与旧主轴坐标。优先保存可见条目，供删除后的锚点回退使用。
    private var pendingAnchors: [(AnyHashable, CGFloat)] = []
    private var horizontal: Bool { configuration.scrollDirection == .horizontal }
    private var rtl: Bool { collectionView?.effectiveUserInterfaceLayoutDirection == .rightToLeft }
    private var sections: [Int: Section] = [:]
    private var itemDimensions: [IndexPath: NSCollectionLayoutDimension] = [:]
    private var resolutionSize: CGSize = .zero
    private var resolutionInsets: UIEdgeInsets = .zero
    private var resolutionSafeArea: UIEdgeInsets = .zero
    private var resolutionMargins: UIEdgeInsets = .zero
    private var resolutionTraits: UITraitCollection?
    private var resolutionRTL = false

    /// 返回当前 section 配置的独立副本，不执行内容测量。
    func section(at index: Int) -> Section {
        resolvedSection(index, bounds: collectionView?.bounds ?? .zero).snapshot()
    }

    /// 使所有 section 配置快照失效，在后续查询时重新解析；保留约束及内容版本仍匹配的测量结果。
    /// 仅背景、间距或固定开关变化时，不会要求未改变尺寸策略的 cell 重新测量。
    func invalidateSectionConfigurations(reason: String) {
        rememberAnchors()
        sections.removeAll()
        itemDimensions.removeAll()
        let context = WaterfallInvalidationContext()
        context.preservesMeasurements = true
        invalidateLayout(with: context)
        trace("invalidate reason=\(reason)")
        sizingInvalidationHandler?()
    }

    private func resolvedSection(_ index: Int, bounds: CGRect) -> Section {
        let insets = collectionView?.adjustedContentInset ?? .zero
        let safeArea = collectionView?.safeAreaInsets ?? .zero
        let margins = collectionView?.layoutMargins ?? .zero
        let traits = collectionView?.traitCollection ?? UITraitCollection()
        if resolutionSize != bounds.size || resolutionInsets != insets || resolutionRTL != rtl
            || resolutionSafeArea != safeArea || resolutionMargins != margins || resolutionTraits != traits {
            sections.removeAll()
            itemDimensions.removeAll()
            resolutionSize = bounds.size
            resolutionInsets = insets
            resolutionSafeArea = safeArea
            resolutionMargins = margins
            resolutionTraits = traits
            resolutionRTL = rtl
            geometryNeedsUpdate = true
        }
        if let section = sections[index] { return section }
        let environment = WaterfallEnvironment(size: bounds.size, insets: insets, rtl: rtl, traits: traits)
        var section = (sectionProvider?(index, environment) ?? Section()).snapshot()
        section.laneCount = max(1, section.laneCount)
        section.interItemSpacing = sanitized(section.interItemSpacing, fallback: 10)
        section.interLaneSpacing = sanitized(section.interLaneSpacing, fallback: 10)
        if !valid(section.itemLengthDimension.dimension, allowsZero: false) { section.itemLengthDimension = .absolute(50) }
        if ![section.contentInsets.top, section.contentInsets.leading, section.contentInsets.bottom, section.contentInsets.trailing].allSatisfy({ valid($0) }) {
            section.contentInsets = .zero
        }
        // 重复 kind 无法映射到唯一的 UIKit 装饰视图；保留第一个并记录诊断。
        var kinds = Set<String>()
        section.decorationItems = section.decorationItems.filter {
            let inserted = kinds.insert($0.elementKind).inserted
            if !inserted { trace("duplicate decoration kind=\($0.elementKind) section=\(index)") }
            return inserted
        }
        sections[index] = section
        return section
    }

    // 已解析 section 配置和参考边界的 section 指标；主轴坐标始终按逻辑起始方向递增。
    private struct SectionMetrics {
        let configuration: Section
        let count: Int
        let crossStart: CGFloat
        let crossLength: CGFloat
        let laneLength: CGFloat
        let gap: CGFloat
        let line: CGFloat
        let startInset: CGFloat
        let endInset: CGFloat
        let header: CGFloat
        let footer: CGFloat
    }
    // 已转换为 collection view 物理坐标的布局快照；查询时返回副本，不直接修改缓存属性。
    private struct Geometry {
        var cells: [IndexPath: WaterfallAttributes] = [:]
        var supplementary: [String: [IndexPath: UICollectionViewLayoutAttributes]] = [:]
        var decorations: [String: [IndexPath: UICollectionViewLayoutAttributes]] = [:]
        var sectionRanges: [Int: ClosedRange<CGFloat>] = [:]
        var size: CGSize = .zero
    }

    override class var layoutAttributesClass: AnyClass { WaterfallAttributes.self }
    override class var invalidationContextClass: AnyClass { WaterfallInvalidationContext.self }
    override var collectionViewContentSize: CGSize { geometry.size }

    /// 返回指定条目当前的内容测量策略，不执行内容测量。
    /// 固定模式下两轴均为 fixedSize；自适应模式仅将主轴设为 fullyFlexible。
    /// 容器、方向或布局指标改变后，应重新获取策略并更新受影响的内容配置。
    /// NOTE: 容器尚无可用交叉轴空间时，返回的交叉轴长度为 0；此时不应将其视为最终尺寸。
    func sizingForItem(at indexPath: IndexPath) -> ItemSizing {
        let metrics = sectionMetrics(indexPath.section, bounds: collectionView?.bounds ?? .zero)
        let selfSizing = itemDimension(at: indexPath).isEstimated
        let length = selfSizing ? CGFloat.infinity : initialLength(at: indexPath)
        return ItemSizing(
            constraint: size(main: length, cross: metrics.laneLength),
            horizontalFlexibility: horizontal && selfSizing ? .fullyFlexible : .fixedSize,
            verticalFlexibility: !horizontal && selfSizing ? .fullyFlexible : .fixedSize
        )
    }

    /// 使测量缓存及布局属性失效，并调用 sizingInvalidationHandler。
    /// 用于整体测量环境变化；section 配置变化优先使用 invalidateSectionConfigurations(reason:)；reason 仅用于 DEBUG 日志。
    /// 单个条目内容变化时，也可更新其内容版本并重新配置条目，以保留其他条目的测量结果。
    func invalidateMeasurements(reason: String) { metricsChanged(reason) }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        _ = resolvedSection(0, bounds: collectionView.bounds)
        // 仅滚动原点变化时保留几何快照；固定补充视图的位置在属性查询阶段计算。
        guard geometryNeedsUpdate || preparedBoundsSize != collectionView.bounds.size
            || preparedInsets != collectionView.adjustedContentInset || preparedRTL != rtl else { return }
        geometryNeedsUpdate = false
        preparedBoundsSize = collectionView.bounds.size
        preparedInsets = collectionView.adjustedContentInset
        preparedRTL = rtl
        geometry = makeGeometry(bounds: collectionView.bounds, lengths: lengths)
        let keys = Set(geometry.cells.values.compactMap(\.measurementKey))
        // 数据源更新后移除已删除条目及旧约束、旧内容版本的测量结果。
        lengths = lengths.filter { keys.contains($0.key) }
        // 普通失效需要等新快照生成后再恢复锚点；恢复前清空待处理状态，避免偏移更新导致重复应用。
        if !pendingAnchors.isEmpty {
            let delta = anchorAdjustment(pendingAnchors, next: geometry)
            pendingAnchors.removeAll()
            if delta != 0 {
                var offset = collectionView.contentOffset
                if horizontal { offset.x += delta } else { offset.y += delta }
                collectionView.contentOffset = clamped(offset, contentSize: geometry.size)
            }
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result: [UICollectionViewLayoutAttributes] = geometry.cells.values
            .filter { $0.frame.intersects(rect) }.map { $0.copy() as! UICollectionViewLayoutAttributes }
        // 固定后的 header/footer 可能进入 rect，即使其自然位置不在 rect 内，也必须参与查询。
        for (kind, views) in geometry.supplementary {
            for path in views.keys {
                if let attributes = layoutAttributesForSupplementaryView(ofKind: kind, at: path), attributes.frame.intersects(rect) {
                    result.append(attributes)
                }
            }
        }
        result += geometry.decorations.values.flatMap { $0.values }
            .filter { $0.frame.intersects(rect) }.map { $0.copy() as! UICollectionViewLayoutAttributes }
        return result
    }

    override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        geometry.decorations[elementKind]?[indexPath]?.copy() as? UICollectionViewLayoutAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        geometry.cells[indexPath]?.copy() as? UICollectionViewLayoutAttributes
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let result = geometry.supplementary[elementKind]?[indexPath]?.copy() as? UICollectionViewLayoutAttributes,
              let range = geometry.sectionRanges[indexPath.section], let collectionView else { return nil }
        let boundary = boundaries(resolvedSection(indexPath.section, bounds: collectionView.bounds))
        let isHeader = elementKind == boundary.start?.elementKind
        guard let item = isHeader ? boundary.start : boundary.end, item.pinToVisibleBounds else { return result }
        let insets = collectionView.adjustedContentInset
        let visibleStart = horizontal ? collectionView.bounds.minX + insets.left : collectionView.bounds.minY + insets.top
        let visibleEnd = horizontal ? collectionView.bounds.maxX - insets.right : collectionView.bounds.maxY - insets.bottom
        let extent = main(result.size)
        // 横向 RTL 的 header 固定在物理右侧，footer 固定在物理左侧。
        let pinsAtStart = isHeader != (horizontal && rtl)
        let natural = mainOrigin(result.frame)
        let desired = pinsAtStart ? max(natural, visibleStart) : min(natural, visibleEnd - extent)
        // 将固定位置限制在 section 内，并为另一种补充视图保留空间，避免两者重叠。
        let counterpart = isHeader ? boundary.end : boundary.start
        let counterpartLength = counterpart.flatMap { geometry.supplementary[$0.elementKind]?[indexPath] }.map { main($0.size) } ?? 0
        let lower = range.lowerBound + (pinsAtStart ? 0 : counterpartLength)
        let upper = range.upperBound - extent - (pinsAtStart ? counterpartLength : 0)
        let origin = max(lower, min(desired, max(lower, upper)))
        if horizontal { result.frame.origin.x = origin } else { result.frame.origin.y = origin }
        result.zIndex = max(item.zIndex, isHeader ? 1024 : 1023)
        return result
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size || sections.values.contains { $0.boundarySupplementaryItems.contains { $0.pinToVisibleBounds } }
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds) as! WaterfallInvalidationContext
        context.preservesMeasurements = true
        // 原点变化只更新固定位置；容器尺寸变化才重排条目，并依据新约束重新匹配测量 key。
        context.updatesGeometry = newBounds.size != collectionView?.bounds.size
        if newBounds.size != collectionView?.bounds.size {
            setAnchorAdjustment(context, next: makeGeometry(bounds: newBounds, lengths: lengths))
            trace("invalidate reason=bounds size=\(newBounds.size)")
        }
        return context
    }

    override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
        // 固定模式及过期属性不接受自适应结果。只比较主轴，交叉轴始终由布局控制。
        guard validKey(originalAttributes) != nil else { return false }
        // 向上对齐显示像素后再比较，避免亚像素差异引起持续失效。
        let length = rounded(main(preferredAttributes.size))
        return valid(length, allowsZero: false) && length != main(originalAttributes.size)
    }

    override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes) as! WaterfallInvalidationContext
        context.preservesMeasurements = true
        if let key = validKey(originalAttributes) {
            let length = rounded(main(preferredAttributes.size))
            if valid(length, allowsZero: false) {
                context.measurement = (key, length)
                // 先用候选长度计算锚点偏移；缓存写入统一留到 invalidateLayout(with:)。
                var next = lengths
                next[key] = length
                setAnchorAdjustment(context, next: makeGeometry(bounds: collectionView?.bounds ?? .zero, lengths: next))
            }
        }
        return context
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        let waterfallContext = context as? WaterfallInvalidationContext
        geometryNeedsUpdate = geometryNeedsUpdate || waterfallContext?.updatesGeometry != false
        // preferred attributes 失效只更新一个测量结果；相同结果不重复计入诊断次数。
        if let (key, length) = waterfallContext?.measurement, key.generation == generation,
           geometry.cells.values.contains(where: { $0.measurementKey == key && validKey($0) == key }), lengths[key] != length {
            lengths[key] = length
            acceptedMeasurementCount += 1
            trace("fit id=\(key.id) direction=\(configuration.scrollDirection.rawValue) cross=\(key.crossLength) estimated=\(key.estimatedLength) fitted=\(length) reason=preferred")
        } else if waterfallContext?.preservesMeasurements != true {
            rememberAnchors()
            sections.removeAll()
            itemDimensions.removeAll()
            if context.invalidateDataSourceCounts {
                // 插入、移动及删除后按稳定 ID / 内容版本保留仍有效的结果；prepare 会清理旧 key。
            } else if !context.invalidateEverything, let paths = context.invalidatedItemIndexPaths {
                let invalidIDs = Set(paths.compactMap { geometry.cells[$0]?.measurementKey?.id })
                lengths = lengths.filter { !invalidIDs.contains($0.key.id) }
            } else {
                // 整体失效递增版本，使之前交给 UIKit 的属性无法再提交旧测量。
                generation += 1
                lengths.removeAll()
            }
        }
        super.invalidateLayout(with: context)
    }

    private func metricsChanged(_ reason: String) {
        trace("invalidate reason=\(reason)")
        sections.removeAll()
        itemDimensions.removeAll()
        invalidateLayout()
        sizingInvalidationHandler?()
    }

    // 使用当前数据源和尺寸指标重新构造 key，拒绝复用、内容更新或约束变化之前的拟合结果。
    private func validKey(_ attributes: UICollectionViewLayoutAttributes) -> WaterfallMeasurementKey? {
        guard attributes.representedElementCategory == .cell,
              let collectionView, attributes.indexPath.section < collectionView.numberOfSections,
              attributes.indexPath.item < collectionView.numberOfItems(inSection: attributes.indexPath.section),
              let key = (attributes as? WaterfallAttributes)?.measurementKey, key.selfSizing,
              key == measurementKey(at: attributes.indexPath, crossLength: sectionMetrics(attributes.indexPath.section, bounds: collectionView.bounds).laneLength)
        else { return nil }
        return key
    }

    private func measurementKey(at path: IndexPath, crossLength: CGFloat, bounds: CGRect? = nil) -> WaterfallMeasurementKey {
        let metadata = itemMetadataProvider?(path) ?? ItemMetadata(identifier: path)
        return WaterfallMeasurementKey(
            id: metadata.identifier,
            revision: metadata.contentVersion,
            crossLength: crossLength, estimatedLength: initialLength(at: path, bounds: bounds), horizontal: horizontal,
            selfSizing: itemDimension(at: path, bounds: bounds).isEstimated,
            layoutDirection: rtl ? 1 : 0, contentSizeCategory: collectionView?.traitCollection.preferredContentSizeCategory.rawValue ?? "",
            displayScale: collectionView?.traitCollection.displayScale ?? 1, generation: generation
        )
    }

    private func itemDimension(at path: IndexPath, bounds: CGRect? = nil) -> NSCollectionLayoutDimension {
        let bounds = bounds ?? collectionView?.bounds ?? .zero
        let section = resolvedSection(path.section, bounds: bounds)
        if let dimension = itemDimensions[path] { return dimension }
        let environment = WaterfallEnvironment(size: bounds.size, insets: collectionView?.adjustedContentInset ?? .zero, rtl: rtl, traits: collectionView?.traitCollection ?? UITraitCollection())
        let dimension = section.itemLengthDimensionProvider?(path.item, environment) ?? section.itemLengthDimension
        let result = (valid(dimension.dimension, allowsZero: false) ? dimension : section.itemLengthDimension).copy() as! NSCollectionLayoutDimension
        itemDimensions[path] = result
        return result
    }

    private func initialLength(at path: IndexPath, bounds: CGRect? = nil) -> CGFloat {
        let dimension = itemDimension(at: path, bounds: bounds)
        let bounds = bounds ?? collectionView?.bounds ?? .zero
        let insets = collectionView?.adjustedContentInset ?? .zero
        if dimension.isFractionalWidth { return max(1, bounds.width - insets.left - insets.right) * dimension.dimension }
        if dimension.isFractionalHeight { return max(1, bounds.height - insets.top - insets.bottom) * dimension.dimension }
        return dimension.dimension
    }

    // 支持范围明确限定为主轴两端的完整边界视图，避免把未实现的原生选项静默当作已支持。
    private func boundaries(_ section: Section) -> (start: NSCollectionLayoutBoundarySupplementaryItem?, end: NSCollectionLayoutBoundarySupplementaryItem?) {
        var start: NSCollectionLayoutBoundarySupplementaryItem?
        var end: NSCollectionLayoutBoundarySupplementaryItem?
        var kinds = Set<String>()
        for item in section.boundarySupplementaryItems {
            let isStart = item.alignment == (horizontal ? .leading : .top)
            let isEnd = item.alignment == (horizontal ? .trailing : .bottom)
            let main = horizontal ? item.layoutSize.widthDimension : item.layoutSize.heightDimension
            let cross = horizontal ? item.layoutSize.heightDimension : item.layoutSize.widthDimension
            guard (isStart || isEnd), main.isAbsolute, valid(main.dimension, allowsZero: false),
                  (horizontal ? cross.isFractionalHeight : cross.isFractionalWidth), cross.dimension == 1,
                  item.extendsBoundary, item.offset == .zero, item.contentInsets == .zero,
                  kinds.insert(item.elementKind).inserted, isStart ? start == nil : end == nil else {
                trace("unsupported/duplicate boundary kind=\(item.elementKind)")
                continue
            }
            if isStart { start = item } else { end = item }
        }
        return (start, end)
    }

    private func sectionMetrics(_ section: Int, bounds: CGRect) -> SectionMetrics {
        let configuration = resolvedSection(section, bounds: bounds)
        let count = configuration.laneCount
        let inset = configuration.contentInsets
        let sectionInsetReference = configuration.contentInsetsReference == .automatic ? self.configuration.contentInsetsReference : configuration.contentInsetsReference
        // reference / adjustedContentInset 使用物理边；section 边距在此按方向解析一次。
        let leftInset = rtl ? inset.trailing : inset.leading
        let rightInset = rtl ? inset.leading : inset.trailing
        let gap = configuration.interLaneSpacing
        let line = configuration.interItemSpacing
        let adjusted = collectionView?.adjustedContentInset ?? .zero
        let reference: UIEdgeInsets
        switch sectionInsetReference {
        case .safeArea: reference = collectionView?.safeAreaInsets ?? .zero
        case .layoutMargins: reference = collectionView?.layoutMargins ?? .zero
        case .readableContent:
            if let view = collectionView {
                let frame = view.readableContentGuide.layoutFrame
                reference = UIEdgeInsets(top: max(0, frame.minY - view.bounds.minY), left: max(0, frame.minX - view.bounds.minX), bottom: max(0, view.bounds.maxY - frame.maxY), right: max(0, view.bounds.maxX - frame.maxX))
            } else { reference = .zero }
        default: reference = .zero
        }
        // 坐标范围已经扣除 adjustedContentInset；这里只补足 reference + sectionInset 的差值。
        let crossAvailable = max(0, cross(bounds.size) - (horizontal ? adjusted.top + adjusted.bottom : adjusted.left + adjusted.right))
        let start = horizontal ? max(0, reference.top + inset.top - adjusted.top) : max(0, reference.left + leftInset - adjusted.left)
        let end = horizontal ? max(0, reference.bottom + inset.bottom - adjusted.bottom) : max(0, reference.right + rightInset - adjusted.right)
        let crossStart = (sectionInsetReference == .none || sectionInsetReference == .automatic) ? (horizontal ? inset.top : leftInset) : start
        let crossEnd = (sectionInsetReference == .none || sectionInsetReference == .automatic) ? (horizontal ? inset.bottom : rightInset) : end
        let available = max(0, crossAvailable - crossStart - crossEnd)
        let boundary = boundaries(configuration)
        return SectionMetrics(
            configuration: configuration, count: count, crossStart: crossStart, crossLength: available,
            laneLength: max(0, (available - gap * CGFloat(count - 1)) / CGFloat(count)),
            gap: gap, line: line,
            startInset: horizontal ? inset.leading : inset.top,
            endInset: horizontal ? inset.trailing : inset.bottom,
            header: boundary.start.map { horizontal ? $0.layoutSize.widthDimension.dimension : $0.layoutSize.heightDimension.dimension } ?? 0,
            footer: boundary.end.map { horizontal ? $0.layoutSize.widthDimension.dimension : $0.layoutSize.heightDimension.dimension } ?? 0
        )
    }

    private func makeGeometry(bounds: CGRect, lengths: [WaterfallMeasurementKey: CGFloat]) -> Geometry {
        guard let collectionView else { return Geometry() }
        var result = Geometry()
        var cursor: CGFloat = 0
        for section in 0..<collectionView.numberOfSections {
            let metrics = sectionMetrics(section, bounds: bounds)
            if section > 0 { cursor += configuration.interSectionSpacing }
            let sectionStart = cursor
            let boundary = boundaries(metrics.configuration)
            func supplementary(_ item: NSCollectionLayoutBoundarySupplementaryItem?, length: CGFloat, origin: CGFloat) {
                guard let item, length > 0 else { return }
                let kind = item.elementKind
                let path = IndexPath(item: 0, section: section)
                let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: path)
                attributes.frame = rect(main: origin, cross: metrics.crossStart, length: length, crossLength: metrics.crossLength)
                attributes.zIndex = max(1, item.zIndex)
                result.supplementary[kind, default: [:]][path] = attributes
            }
            supplementary(boundary.start, length: metrics.header, origin: cursor)
            cursor += metrics.header + metrics.startInset
            // 每个 section 从相同起点开始。ends 保存各列/行下一条目的主轴起点。
            var ends = Array(repeating: cursor, count: metrics.count)
            let itemCount = collectionView.numberOfItems(inSection: section)
            if metrics.laneLength > 0 {
                for item in 0..<itemCount {
                    let path = IndexPath(item: item, section: section)
                    // 同长时保留第一个最小值，即逻辑起始列/行；RTL 仅改变物理位置，不改变分配顺序。
                    let lane = ends.indices.min { ends[$0] < ends[$1] } ?? 0
                    let key = measurementKey(at: path, crossLength: metrics.laneLength, bounds: bounds)
                    let length = key.selfSizing ? (lengths[key] ?? key.estimatedLength) : key.estimatedLength
                    let physicalLane = !horizontal && rtl ? metrics.count - 1 - lane : lane
                    let attributes = WaterfallAttributes(forCellWith: path)
                    attributes.measurementKey = key
                    attributes.zIndex = 1
                    attributes.frame = rect(main: ends[lane], cross: metrics.crossStart + CGFloat(physicalLane) * (metrics.laneLength + metrics.gap), length: length, crossLength: metrics.laneLength)
                    result.cells[path] = attributes
                    ends[lane] += length + metrics.line
                }
            }
            // 下一 section 从最远末端继续；最后一项之后不保留 line spacing，空 section 不扣除间距。
            cursor = (ends.max() ?? cursor) - (itemCount > 0 && metrics.laneLength > 0 ? metrics.line : 0) + metrics.endInset
            supplementary(boundary.end, length: metrics.footer, origin: cursor)
            cursor += metrics.footer
            result.sectionRanges[section] = sectionStart...cursor
            // 背景使用自然 section 范围，包含补充视图和边距；不参与条目测量及 contentSize。
            let adjusted = collectionView.adjustedContentInset
            let availableCross = max(0, cross(bounds.size) - (horizontal ? adjusted.top + adjusted.bottom : adjusted.left + adjusted.right))
            if cursor > sectionStart, availableCross > 0 {
                for item in metrics.configuration.decorationItems {
                    let inset = item.contentInsets
                    guard [inset.top, inset.leading, inset.bottom, inset.trailing].allSatisfy({ $0.isFinite }) else { continue }
                    let start = horizontal ? inset.leading : inset.top
                    let end = horizontal ? inset.trailing : inset.bottom
                    let crossStart = horizontal ? inset.top : (rtl ? inset.trailing : inset.leading)
                    let crossEnd = horizontal ? inset.bottom : (rtl ? inset.leading : inset.trailing)
                    let length = max(0, cursor - sectionStart - start - end)
                    let crossLength = max(0, availableCross - crossStart - crossEnd)
                    guard length > 0, crossLength > 0 else { continue }
                    let path = IndexPath(item: 0, section: section)
                    let attributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: item.elementKind, with: path)
                    attributes.frame = rect(main: sectionStart + start, cross: crossStart, length: length, crossLength: crossLength)
                    attributes.zIndex = item.zIndex
                    result.decorations[item.elementKind, default: [:]][path] = attributes
                }
            }
        }
        let adjusted = collectionView.adjustedContentInset
        let availableCross = max(0, cross(bounds.size) - (horizontal ? adjusted.top + adjusted.bottom : adjusted.left + adjusted.right))
        let availableMain = max(0, main(bounds.size) - (horizontal ? adjusted.left + adjusted.right : adjusted.top + adjusted.bottom))
        // 横向 RTL 至少使用可见主轴长度作为镜像范围，使不足一屏的内容仍对齐逻辑起始边。
        let mainLength = max(cursor, horizontal && rtl ? availableMain : 0)
        result.size = size(main: mainLength, cross: availableCross)
        // 横向先沿逻辑方向排列，再统一镜像条目、补充视图和 section 范围；避免重复翻转边距。
        if horizontal && rtl {
            for attributes in result.cells.values { attributes.frame.origin.x = mainLength - attributes.frame.maxX }
            for views in Array(result.supplementary.values) + Array(result.decorations.values) {
                for attributes in views.values { attributes.frame.origin.x = mainLength - attributes.frame.maxX }
            }
            result.sectionRanges = result.sectionRanges.mapValues { (mainLength - $0.upperBound)...(mainLength - $0.lowerBound) }
        }
        return result
    }

    private func visibleAnchors() -> [(AnyHashable, CGFloat)] {
        guard let collectionView else { return [] }
        let inset = collectionView.adjustedContentInset
        let offset = horizontal ? collectionView.contentOffset.x + inset.left : collectionView.contentOffset.y + inset.top
        // 起点保持自然起点；横向 RTL 的起点在物理右侧，仍须锚定以抵消总长度变化。
        guard offset > 0 || (horizontal && rtl) else { return [] }
        let ordered = geometry.cells.values.sorted { $0.indexPath < $1.indexPath }
        // 可见条目按数据源顺序优先；全部可见锚点被删除后，使用仍保留的其他条目回退。
        let visible = ordered.filter { $0.frame.intersects(collectionView.bounds) }
        let others = ordered.filter { !$0.frame.intersects(collectionView.bounds) }
        return (visible + others).compactMap { attributes in
            attributes.measurementKey.map { ($0.id, mainOrigin(attributes.frame)) }
        }
    }

    // 多次失效合并到同一布局周期时，只保存最初的锚点位置。
    private func rememberAnchors() { if pendingAnchors.isEmpty { pendingAnchors = visibleAnchors() } }

    private func anchorAdjustment(_ anchors: [(AnyHashable, CGFloat)], next: Geometry) -> CGFloat {
        for (id, origin) in anchors {
            if let attributes = next.cells.values.first(where: { $0.measurementKey?.id == id }) {
                return mainOrigin(attributes.frame) - origin
            }
        }
        return 0
    }

    private func setAnchorAdjustment(_ context: UICollectionViewLayoutInvalidationContext, next: Geometry) {
        guard let collectionView else { return }
        let delta = anchorAdjustment(visibleAnchors(), next: next)
        var offset = collectionView.contentOffset
        if horizontal { offset.x += delta } else { offset.y += delta }
        offset = clamped(offset, contentSize: next.size)
        // preferred attributes / bounds 失效由 UIKit 应用偏移，避免在失效查询期间直接滚动。
        context.contentOffsetAdjustment = CGPoint(x: offset.x - collectionView.contentOffset.x, y: offset.y - collectionView.contentOffset.y)
    }

    // 内容缩短或尚不足一屏时，偏移仍须位于包含 adjustedContentInset 的合法滚动范围内。
    private func clamped(_ offset: CGPoint, contentSize: CGSize) -> CGPoint {
        guard let collectionView else { return offset }
        let inset = collectionView.adjustedContentInset
        return CGPoint(
            x: max(-inset.left, min(offset.x, max(-inset.left, contentSize.width - collectionView.bounds.width + inset.right))),
            y: max(-inset.top, min(offset.y, max(-inset.top, contentSize.height - collectionView.bounds.height + inset.bottom)))
        )
    }
    // 主轴/交叉轴到物理宽高的转换集中在此；调用方不需要重复判断滚动方向。
    private func main(_ value: CGSize) -> CGFloat { horizontal ? value.width : value.height }
    private func cross(_ value: CGSize) -> CGFloat { horizontal ? value.height : value.width }
    private func mainOrigin(_ value: CGRect) -> CGFloat { horizontal ? value.minX : value.minY }
    private func size(main: CGFloat, cross: CGFloat) -> CGSize { horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main) }
    private func rect(main: CGFloat, cross: CGFloat, length: CGFloat, crossLength: CGFloat) -> CGRect {
        CGRect(origin: horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main), size: size(main: length, cross: crossLength))
    }
    private func rounded(_ length: CGFloat) -> CGFloat {
        let scale = max(1, collectionView?.traitCollection.displayScale ?? 1)
        return ceil(length * scale) / scale
    }
    private func valid(_ value: CGFloat, allowsZero: Bool = true) -> Bool { value.isFinite && (allowsZero ? value >= 0 : value > 0) }
    private func sanitized(_ value: CGFloat?, fallback: CGFloat) -> CGFloat { value.flatMap { valid($0) ? $0 : nil } ?? fallback }
    private func trace(_ message: String) {
        #if DEBUG
        print("[ContentWaterfall] \(message)")
        #endif
    }
}

private extension ContentConfigurationWaterfallLayout.Section {
    /// UIKit 描述对象具有引用语义；复制后调用方的后续修改不会改变已解析配置。
    func snapshot() -> Self {
        var result = self
        result.itemLengthDimension = itemLengthDimension.copy() as! NSCollectionLayoutDimension
        result.boundarySupplementaryItems = boundarySupplementaryItems.map { $0.copy() as! NSCollectionLayoutBoundarySupplementaryItem }
        result.decorationItems = decorationItems.map { $0.copy() as! NSCollectionLayoutDecorationItem }
        return result
    }
}

/// 将 UICollectionView 已解析的安全区边距暴露为 UIKit 原生布局环境。
@MainActor
private final class WaterfallEnvironment: NSObject, NSCollectionLayoutEnvironment {
    let container: NSCollectionLayoutContainer
    let traitCollection: UITraitCollection
    init(size: CGSize, insets: UIEdgeInsets, rtl: Bool, traits: UITraitCollection) {
        container = WaterfallContainer(size: size, insets: insets, rtl: rtl)
        traitCollection = UITraitCollection(traitsFrom: [traits, UITraitCollection(layoutDirection: rtl ? .rightToLeft : .leftToRight)])
    }
}

@MainActor
private final class WaterfallContainer: NSObject, NSCollectionLayoutContainer {
    let contentSize: CGSize
    let effectiveContentSize: CGSize
    let contentInsets: NSDirectionalEdgeInsets
    var effectiveContentInsets: NSDirectionalEdgeInsets { contentInsets }
    init(size: CGSize, insets: UIEdgeInsets, rtl: Bool) {
        contentSize = size
        effectiveContentSize = CGSize(width: max(0, size.width - insets.left - insets.right), height: max(0, size.height - insets.top - insets.bottom))
        contentInsets = NSDirectionalEdgeInsets(top: insets.top, leading: rtl ? insets.right : insets.left, bottom: insets.bottom, trailing: rtl ? insets.left : insets.right)
    }
}
