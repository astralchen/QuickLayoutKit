import UIKit
import QuickLayout
import OSLog

// 一次有效测量对应的内容和约束。提供稳定标识时，条目移动不会仅因 IndexPath 变化而丢失缓存。
nonisolated private struct WaterfallMeasurementKey: Hashable {
    let id: AnyHashable
    let revision: Int
    var crossLength: CGFloat
    // 自适应模式为估算长度，固定模式为最终长度；该长度改变后旧测量键不再匹配。
    let estimatedLength: CGFloat
    let horizontal: Bool
    let selfSizing: Bool
    let layoutDirection: Int
    let contentSizeCategory: String
    let displayScale: CGFloat
    // 全局尺寸配置版本；使旧布局属性返回的拟合结果失效。
    let generation: Int
}

// 完整测量键仅在主执行器（MainActor）比较；非隔离的 NSObject 相等性入口只比较此不可变标识。
nonisolated private final class WaterfallMeasurementIdentity: Sendable {}

// 为兼容 iOS 15，此容器使用 NSLock 保护所有读写，以保证 @unchecked Sendable 声明的安全性；
// 保存的只有不可变 Sendable 标识，不包含 UIKit 状态或 AnyHashable 测量数据。
nonisolated private final class WaterfallIdentityStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WaterfallMeasurementIdentity?

    func load() -> WaterfallMeasurementIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func store(_ value: WaterfallMeasurementIdentity?) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}

// 将测量条件随布局属性传递给 UIKit；复制和相等性比较必须包含自定义状态。
private final class WaterfallAttributes: UICollectionViewLayoutAttributes {
    private(set) var measurementKey: WaterfallMeasurementKey?
    nonisolated private let identityStorage = WaterfallIdentityStorage()

    func setMeasurement(_ key: WaterfallMeasurementKey, identity: WaterfallMeasurementIdentity) {
        measurementKey = key
        identityStorage.store(identity)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! WaterfallAttributes
        result.measurementKey = measurementKey
        result.identityStorage.store(identityStorage.load())
        return result
    }
    nonisolated override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WaterfallAttributes else { return false }
        return identityStorage.load() === other.identityStorage.load() && super.isEqual(other)
    }
}

/// 将条目依次放入当前最短列或行的集合视图布局。
/// 主轴指滚动方向，交叉轴指与滚动方向垂直的方向。各分区独立排列，按数据源顺序连接。
/// 布局提供内容测量所需的约束与弹性，并通过 UIKit 的首选布局属性回调接收主轴长度。
/// 注意：本布局不创建测量单元格，也不主动调用内容视图的 sizeThatFits(_:)。
@MainActor
open class UICollectionViewWaterfallLayout: UICollectionViewLayout {
    nonisolated private static let logger = Logger(subsystem: "QuickLayoutKit", category: "WaterfallLayout")

    /// 一个分区的完整布局配置；尺寸、间距及补充视图仅由此对象描述。
    @MainActor
    public struct Section {
        public init() {}
        /// 交叉轴尺寸描述；默认两条等宽列或行，adaptive 可展开为多条。
        public var lanes: [LaneSize] = [.flexible(), .flexible()]
        /// 同一列或行内的间距。默认值为 10pt。
        public var interItemSpacing: CGFloat = 10
        /// 相邻列或行的间距。默认值为 10pt。
        public var interLaneSpacing: CGFloat = 10
        /// 分区头部之后、尾部之前的方向性边距。默认值为 .zero。
        public var contentInsets: NSDirectionalEdgeInsets = .zero
        /// 交叉轴边距的参考边界。默认值为 .automatic，继承全局 configuration。
        public var contentInsetsReference: UIContentInsetsReference = .automatic
        /// 主轴尺寸描述。默认值为 .absolute(50)；.estimated 启用 UIKit 自适应测量。
        /// 支持 absolute、estimated、fractionalWidth 和 fractionalHeight；比例基于可用容器。
        public var itemLengthDimension: NSCollectionLayoutDimension = .absolute(50)
        /// 可选的条目尺寸描述提供者。参数为分区内的条目索引和原生布局环境。
        public var itemLengthDimensionProvider: (@MainActor (Int, NSCollectionLayoutEnvironment) -> NSCollectionLayoutDimension?)?
        /// 边界补充视图。支持主轴两端各一个元素，使用任意唯一 elementKind。
        /// 纵向使用 top/bottom，横向使用 leading/trailing；交叉轴使用 fractionalWidth/Height(1)。
        /// 主轴长度须为 absolute，extendsBoundary 须为 true；offset 与 contentInsets 须为零。
        /// 不支持的描述忽略并输出 DEBUG 诊断；补充视图自适应及任意锚点不在本布局范围内。
        public var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
        /// 分区背景。默认值为空；同一分区内 elementKind 必须唯一。
        /// 支持 background(elementKind:) 的 contentInsets 和 zIndex；视图通过布局的 register 方法注册。
        public var decorationItems: [NSCollectionLayoutDecorationItem] = []
    }

    /// 布局全局配置。采用值语义，修改并赋值后立即使布局失效。
    public struct Configuration: Equatable {
        public init(scrollDirection: UICollectionView.ScrollDirection = .vertical,
                    interSectionSpacing: CGFloat = 0,
                    contentInsetsReference: UIContentInsetsReference = .none) {
            self.scrollDirection = scrollDirection
            self.interSectionSpacing = interSectionSpacing
            self.contentInsetsReference = contentInsetsReference
        }
        /// 所有分区共用的滚动方向。默认值为 .vertical。
        public var scrollDirection: UICollectionView.ScrollDirection = .vertical
        /// 相邻分区的主轴间距。默认值为 0，不属于背景或固定范围。
        public var interSectionSpacing: CGFloat = 0
        /// 分区边距参考边界。默认值为 .none，仍始终尊重 adjustedContentInset。
        public var contentInsetsReference: UIContentInsetsReference = .none
    }

    /// 与 UICollectionViewCompositionalLayout 的 provider 参数保持一致。
    public typealias SectionProvider = @MainActor (Int, NSCollectionLayoutEnvironment) -> Section?

    /// 按分区索引提供完整配置；返回 nil 时使用 Section() 的默认值。
    /// 闭包不得重入布局或修改数据源；捕获数据变化后调用 invalidateSectionConfigurations(reason:)。
    public private(set) var sectionProvider: SectionProvider?

    /// 布局全局配置。非法间距保留原值；仅方向变化时清除全部测量。
    public var configuration = Configuration() {
        didSet {
            if !valid(configuration.interSectionSpacing) { configuration.interSectionSpacing = oldValue.interSectionSpacing }
            guard oldValue != configuration else { return }
            if oldValue.scrollDirection != configuration.scrollDirection { metricsChanged("direction") }
            else { invalidateSectionConfigurations(reason: "configuration") }
        }
    }

    @available(*, unavailable, message: "Use init(section:) or init(sectionProvider:)")
    public override init() { fatalError("Use a section initializer") }

    /// 对所有分区使用相同配置；装饰描述在初始化时复制。
    public convenience init(section: Section, configuration: Configuration = Configuration()) {
        let snapshot = section.snapshot()
        self.init(sectionProvider: { _, _ in snapshot }, configuration: configuration)
    }

    /// 使用原生布局环境提供各分区配置。
    public init(sectionProvider: @escaping SectionProvider, configuration: Configuration = Configuration()) {
        self.sectionProvider = sectionProvider
        self.configuration = configuration
        super.init()
        if !valid(self.configuration.interSectionSpacing) { self.configuration.interSectionSpacing = 0 }
    }

    @available(*, unavailable, message: "Use a section initializer")
    public required init?(coder: NSCoder) { fatalError("Use a section initializer") }

    /// 提供给单元格内容配置的测量策略；与布局属性使用相同的分区指标。
    nonisolated public struct ItemSizing: Equatable, Sendable {
        public init(constraint: CGSize, horizontalFlexibility: Flexibility, verticalFlexibility: Flexibility) {
            self.constraint = constraint
            self.horizontalFlexibility = horizontalFlexibility
            self.verticalFlexibility = verticalFlexibility
        }
        /// 内容测量的约束。自适应主轴为 infinity，固定轴为布局计算的有限长度。
        public let constraint: CGSize
        /// 水平尺寸弹性。仅横向自适应时为 fullyFlexible，否则为 fixedSize。
        public let horizontalFlexibility: Flexibility
        /// 垂直尺寸弹性。仅纵向自适应时为 fullyFlexible，否则为 fixedSize。
        public let verticalFlexibility: Flexibility
    }

    /// 数据源条目的测量身份。位置改变后 identifier 应保持稳定。
    public struct ItemMetadata {
        public init(identifier: AnyHashable, contentVersion: Int = 0) {
            self.identifier = identifier
            self.contentVersion = contentVersion
        }
        public let identifier: AnyHashable
        public var contentVersion: Int = 0
    }

    /// 测量缓存及滚动锚点的身份提供者。默认使用 IndexPath 和版本 0。
    /// 数据更新时返回新内容版本并重新配置单元格；设置闭包后使现有测量失效。identifier 必须在集合中唯一。
    public var itemMetadataProvider: (@MainActor (IndexPath) -> ItemMetadata)? {
        didSet { metricsChanged("item-metadata-provider") }
    }

    /// 尺寸策略失效或条目换列后合并到下一主循环执行的回调。默认值为 nil。
    /// 调用方应在后续布局周期检查测量策略，仅在策略改变时更新内容配置。
    /// 注意：回调执行时实际尺寸可能尚未改变；避免在回调中重入可差分数据源的快照更新。
    public var sizingInvalidationHandler: (@MainActor () -> Void)?

    nonisolated public enum LaneSize: Equatable, Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    nonisolated struct ResolvedLane: Equatable, Sendable {
        let crossOrigin: CGFloat
        let crossLength: CGFloat
    }

    /// 不依赖可变布局状态的交叉轴尺寸解析器。返回 nil 表示容器尚不可用。
    nonisolated static func resolveLanes(_ descriptions: [LaneSize], available: CGFloat, spacing: CGFloat) -> [ResolvedLane]? {
        guard available.isFinite, available > 0 else { return nil }
        let gap = spacing.isFinite && spacing >= 0 ? spacing : 10
        func resolve(_ sizes: [LaneSize]) -> [ResolvedLane]? {
            guard !sizes.isEmpty else { return nil }
            var fixed: CGFloat = 0
            var flexible = 0
            for size in sizes {
                switch size {
                case .fixed(let length):
                    guard length.isFinite, length > 0 else { return nil }
                    fixed += length
                case .flexible(let minimum, let maximum), .adaptive(let minimum, let maximum):
                    guard minimum.isFinite, minimum > 0, maximum >= minimum,
                          maximum.isFinite || maximum == .infinity else { return nil }
                    flexible += 1
                }
            }
            guard fixed.isFinite else { return nil }
            let share = max(0, available - fixed - gap * CGFloat(sizes.count - 1)) / CGFloat(max(1, flexible))
            var result: [ResolvedLane] = []
            var cursor: CGFloat = 0
            for size in sizes {
                let count: Int
                let length: CGFloat
                switch size {
                case .fixed(let value): count = 1; length = value
                case .flexible(let minimum, let maximum):
                    count = 1; length = max(minimum, min(maximum, share))
                case .adaptive(let minimum, let maximum):
                    let number = max(1, floor((share + gap) / (minimum + gap)))
                    // 单个尺寸描述展开超过一百万条列或行时，无法形成可用的界面布局。
                    // 同时限制整数转换和内存分配，覆盖最小尺寸为极小有限值的情况。
                    guard number.isFinite, number <= 1_000_000 else { return nil }
                    count = Int(number)
                    length = max(minimum, min(maximum, (share - CGFloat(count - 1) * gap) / CGFloat(count)))
                }
                guard result.count <= 1_000_000 - count, (cursor + CGFloat(count) * (length + gap)).isFinite else { return nil }
                for _ in 0..<count {
                    result.append(ResolvedLane(crossOrigin: cursor, crossLength: length))
                    cursor += length + gap
                }
            }
            return result
        }
        if let result = resolve(descriptions) { return result }
        #if DEBUG
        logger.warning("Invalid lanes; falling back to two flexible lanes")
        #endif
        if let fallback = resolve([.flexible(), .flexible()]) { return fallback }
        // 有限的间距也可能导致坐标溢出；此时回退为默认间距。
        let length = max(10, (available - 10) / 2)
        return [ResolvedLane(crossOrigin: 0, crossLength: length), ResolvedLane(crossOrigin: length + 10, crossLength: length)]
    }

    nonisolated struct Diagnostics: Sendable {
        var fullRebuilds = 0
        var repackedItems = 0
        var queryCandidates = 0
        var anchorLookups = 0
        var candidateReuses = 0
    }
    private(set) var diagnostics = Diagnostics()
    func resetDiagnostics() { diagnostics = Diagnostics() }
    private(set) var acceptedMeasurementCount = 0
    var cachedMeasurementCount: Int { measurements.values.reduce(0) { $0 + $1.count } }
    func cachedMeasurementCount(for identifier: AnyHashable) -> Int { measurements[identifier]?.count ?? 0 }

    private static let blockSize = 128
    private struct SectionMetrics {
        let configuration: Section
        let lanes: [ResolvedLane]
        let uniformLaneLength: CGFloat?
        let crossStart: CGFloat
        let crossLength: CGFloat
        let line: CGFloat
        let boundary: (start: NSCollectionLayoutBoundarySupplementaryItem?, end: NSCollectionLayoutBoundarySupplementaryItem?)
        let startInset: CGFloat
        let endInset: CGFloat
        let header: CGFloat
        let footer: CGFloat
    }
    private struct Record {
        let key: WaterfallMeasurementKey
        let identity: WaterfallMeasurementIdentity
        let lane: Int
        let origin: CGFloat
        let length: CGFloat
    }
    /// 连续候选布局共享不可变几何块的数据；仅为发生变化的块分配新数据。
    private final class Block {
        let records: [Record]
        let before: [CGFloat]
        let after: [CGFloat]
        let laneItems: [[Int]]
        init(records: [Record], before: [CGFloat], after: [CGFloat], laneItems: [[Int]]) {
            self.records = records; self.before = before; self.after = after; self.laneItems = laneItems
        }
    }
    private struct PlacedBlock {
        let data: Block
        var shift: CGFloat = 0
    }
    private struct SectionGeometry {
        let metrics: SectionMetrics
        let inputs: [WaterfallMeasurementKey]
        var blocks: [PlacedBlock]
        // 每条列或行仅索引包含自身条目记录的块，也适用于条目分布极稀疏的情况。
        var laneBlocks: [[Int]]
        var length: CGFloat
    }
    private struct Geometry {
        var sections: [SectionGeometry] = []
        var starts: [CGFloat] = []
        var idPaths: [AnyHashable: IndexPath] = [:]
        var size: CGSize = .zero
        var boundsSize: CGSize = .zero
        var horizontal = false
        var rtl = false
        var minimumMain: CGFloat = 0
        var crossLength: CGFloat = 0
        var spacing: CGFloat = 0
        var hasPinnedBoundaries = false
    }
    private struct Candidate {
        let geometry: Geometry
        let baseVersion: Int
        let sizingChanged: Bool
    }
    private final class InvalidationContext: UICollectionViewLayoutInvalidationContext {
        var measurement: (WaterfallMeasurementKey, CGFloat)?
        var path: IndexPath?
        var candidate: Candidate?
        var preservesMeasurements = false
        var updatesGeometry = true
        var targetOffset: CGPoint?
    }
    private struct Measurement {
        let key: WaterfallMeasurementKey
        let length: CGFloat
        var use: UInt64
    }
    private struct Anchors {
        let geometry: Geometry
        let visible: [(AnyHashable, CGFloat)]
    }

    private var generation = 0
    private var version = 0
    private var measurements: [AnyHashable: [Measurement]] = [:]
    private var measurementClock: UInt64 = 0
    private var geometry = Geometry()
    private var geometryNeedsUpdate = true
    private var pendingBounds: Candidate?
    private var pendingAnchors: Anchors?
    private var pendingOffsetTarget: CGPoint?
    private var lastOffsetObserved: CGPoint?
    private var notificationPending = false
    private var preparing = false
    private var sections: [Int: Section] = [:]
    private var laneResolutions: [Int: (sizes: [LaneSize], available: CGFloat, gap: CGFloat, lanes: [ResolvedLane])] = [:]
    private var resolutionSize: CGSize = .zero
    private var resolutionInsets: UIEdgeInsets = .zero
    private var resolutionSafeArea: UIEdgeInsets = .zero
    private var resolutionMargins: UIEdgeInsets = .zero
    private var resolutionTraits: UITraitCollection?
    private var resolutionRTL = false
    private var horizontal: Bool { configuration.scrollDirection == .horizontal }
    private var rtl: Bool { collectionView?.effectiveUserInterfaceLayoutDirection == .rightToLeft }

    public override class var layoutAttributesClass: AnyClass { WaterfallAttributes.self }
    public override class var invalidationContextClass: AnyClass { InvalidationContext.self }
    open override var collectionViewContentSize: CGSize { geometry.size }

    public func section(at index: Int) -> Section {
        resolvedSection(index, bounds: collectionView?.bounds ?? .zero).snapshot()
    }
    public func resolvedLaneCount(in section: Int) -> Int? {
        guard let collectionView, section >= 0, section < collectionView.numberOfSections else { return nil }
        refreshEnvironment(collectionView.bounds)
        if !geometryNeedsUpdate, geometry.sections.indices.contains(section) {
            let count = geometry.sections[section].metrics.lanes.count
            return count == 0 ? nil : count
        }
        let count = sectionMetrics(section, bounds: collectionView.bounds).lanes.count
        return count == 0 ? nil : count
    }
    /// 读取已提交的列或行分配结果。交叉轴长度为零表示几何尚未就绪。
    public func sizingForItem(at indexPath: IndexPath) -> ItemSizing {
        if let collectionView { refreshEnvironment(collectionView.bounds) }
        guard !geometryNeedsUpdate, let record = record(at: indexPath, in: geometry) else {
            return ItemSizing(constraint: .zero, horizontalFlexibility: .fixedSize, verticalFlexibility: .fixedSize)
        }
        let key = record.key
        return ItemSizing(
            constraint: size(main: key.selfSizing ? .infinity : key.estimatedLength, cross: key.crossLength),
            horizontalFlexibility: key.horizontal && key.selfSizing ? .fullyFlexible : .fixedSize,
            verticalFlexibility: !key.horizontal && key.selfSizing ? .fullyFlexible : .fixedSize)
    }
    public func invalidateMeasurements(reason: String) { metricsChanged(reason) }
    public func invalidateSectionConfigurations(reason: String) {
        rememberAnchors()
        sections.removeAll()
        let context = InvalidationContext()
        context.preservesMeasurements = true
        invalidateLayout(with: context)
        notifySizingChange()
        traceInvalidation(reason: reason)
    }
    private func metricsChanged(_ reason: String) {
        invalidateLayout()
        notifySizingChange()
        traceInvalidation(reason: reason)
    }
    private func notifySizingChange() {
        guard !notificationPending else { return }
        notificationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notificationPending = false
            self.sizingInvalidationHandler?()
        }
    }
    private func refreshEnvironment(_ bounds: CGRect) {
        let insets = collectionView?.adjustedContentInset ?? .zero
        let safeArea = collectionView?.safeAreaInsets ?? .zero
        let margins = collectionView?.layoutMargins ?? .zero
        let traits = collectionView?.traitCollection ?? UITraitCollection()
        let direction = rtl
        guard resolutionSize != bounds.size || resolutionInsets != insets || resolutionRTL != direction
                || resolutionSafeArea != safeArea || resolutionMargins != margins || resolutionTraits != traits else { return }
        sections.removeAll()
        version += 1
        resolutionSize = bounds.size; resolutionInsets = insets; resolutionSafeArea = safeArea
        resolutionMargins = margins; resolutionTraits = traits; resolutionRTL = direction
        geometryNeedsUpdate = true
    }
    private func resolvedSection(_ index: Int, bounds: CGRect) -> Section {
        refreshEnvironment(bounds)
        if let section = sections[index] { return section }
        let environment = WaterfallEnvironment(size: bounds.size, insets: resolutionInsets, rtl: resolutionRTL, traits: resolutionTraits ?? UITraitCollection())
        var section = (sectionProvider?(index, environment) ?? Section()).snapshot()
        section.interItemSpacing = sanitized(section.interItemSpacing, fallback: 10)
        section.interLaneSpacing = sanitized(section.interLaneSpacing, fallback: 10)
        if !valid(section.itemLengthDimension.dimension, allowsZero: false) { section.itemLengthDimension = .absolute(50) }
        if ![section.contentInsets.top, section.contentInsets.leading, section.contentInsets.bottom, section.contentInsets.trailing].allSatisfy({ valid($0) }) {
            section.contentInsets = .zero
        }
        var kinds = Set<String>()
        section.decorationItems = section.decorationItems.filter { kinds.insert($0.elementKind).inserted }
        sections[index] = section
        return section
    }

    open override func prepare() {
        super.prepare()
        guard let collectionView, !preparing else { return }
        preparing = true
        defer { preparing = false; pendingOffsetTarget = nil; lastOffsetObserved = nil }
        refreshEnvironment(collectionView.bounds)
        if let candidate = pendingBounds, candidate.baseVersion == version, candidate.geometry.boundsSize == collectionView.bounds.size {
            geometry = candidate.geometry
            geometryNeedsUpdate = false
            pendingBounds = nil
            diagnostics.candidateReuses += 1
            version += 1
            pruneMeasurements()
            updateDecorationIndex()
            notifySizingChange()
        } else if geometryNeedsUpdate {
            pendingBounds = nil
            geometry = makeGeometry(bounds: collectionView.bounds)
            geometryNeedsUpdate = false
            version += 1
            pruneMeasurements()
            updateDecorationIndex()
            notifySizingChange()
        }
        if let anchors = pendingAnchors {
            pendingAnchors = nil
            let delta = anchorAdjustment(anchors, next: geometry, allowFallback: true)
            var offset = collectionView.contentOffset
            if geometry.horizontal { offset.x += delta } else { offset.y += delta }
            let next = clamped(offset, contentSize: geometry.size)
            if next != collectionView.contentOffset { collectionView.contentOffset = next }
        }
    }

    private func record(at path: IndexPath, in snapshot: Geometry) -> Record? {
        guard path.section >= 0, path.item >= 0, snapshot.sections.indices.contains(path.section) else { return nil }
        let section = snapshot.sections[path.section]
        guard path.item < section.inputs.count, section.blocks.indices.contains(path.item / Self.blockSize) else { return nil }
        let placed = section.blocks[path.item / Self.blockSize]
        let value = placed.data.records[path.item % Self.blockSize]
        return Record(key: value.key, identity: value.identity, lane: value.lane, origin: value.origin + placed.shift, length: value.length)
    }
    private func frame(for record: Record, section index: Int, in snapshot: Geometry) -> CGRect {
        let metrics = snapshot.sections[index].metrics
        let lane = metrics.lanes[record.lane]
        let crossOrigin = metrics.crossStart + (!snapshot.horizontal && snapshot.rtl
            ? metrics.crossLength - lane.crossOrigin - lane.crossLength : lane.crossOrigin)
        let origin = snapshot.starts[index] + record.origin
        let physical = snapshot.horizontal && snapshot.rtl ? snapshot.size.width - origin - record.length : origin
        return snapshot.horizontal
            ? CGRect(x: physical, y: crossOrigin, width: record.length, height: lane.crossLength)
            : CGRect(x: crossOrigin, y: physical, width: lane.crossLength, height: record.length)
    }
    open override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let record = record(at: indexPath, in: geometry) else { return nil }
        let attributes = WaterfallAttributes(forCellWith: indexPath)
        attributes.setMeasurement(record.key, identity: record.identity)
        attributes.frame = frame(for: record, section: indexPath.section, in: geometry)
        attributes.zIndex = 1
        return attributes
    }
    private func lowerBound(_ count: Int, _ predicate: (Int) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if predicate(middle) { high = middle } else { low = middle + 1 }
        }
        return low
    }
    private func logicalRange(_ rect: CGRect, in snapshot: Geometry) -> (CGFloat, CGFloat) {
        if snapshot.horizontal {
            return snapshot.rtl ? (snapshot.size.width - rect.maxX, snapshot.size.width - rect.minX) : (rect.minX, rect.maxX)
        }
        return (rect.minY, rect.maxY)
    }
    private func intersectingSections(_ rect: CGRect, in snapshot: Geometry) -> Range<Int> {
        let (start, end) = logicalRange(rect, in: snapshot)
        let first = lowerBound(snapshot.sections.count) { snapshot.starts[$0] + snapshot.sections[$0].length >= start }
        let last = lowerBound(snapshot.sections.count) { snapshot.starts[$0] > end }
        return first..<max(first, last)
    }
    private func paths(in rect: CGRect, snapshot: Geometry, countCandidates: Bool) -> [IndexPath] {
        var result: [IndexPath] = []
        let (globalStart, globalEnd) = logicalRange(rect, in: snapshot)
        for index in intersectingSections(rect, in: snapshot) {
            let section = snapshot.sections[index]
            let start = globalStart - snapshot.starts[index], end = globalEnd - snapshot.starts[index]
            for lane in section.laneBlocks.indices {
                let resolved = section.metrics.lanes[lane]
                let crossStart = section.metrics.crossStart + (!snapshot.horizontal && snapshot.rtl
                    ? section.metrics.crossLength - resolved.crossOrigin - resolved.crossLength : resolved.crossOrigin)
                let queryStart = snapshot.horizontal ? rect.minY : rect.minX
                let queryEnd = snapshot.horizontal ? rect.maxY : rect.maxX
                guard crossStart <= queryEnd, crossStart + resolved.crossLength >= queryStart else { continue }
                let blocks = section.laneBlocks[lane]
                var offset = lowerBound(blocks.count) {
                    let placed = section.blocks[blocks[$0]]
                    let record = placed.data.records[placed.data.laneItems[lane].last!]
                    return record.origin + placed.shift + record.length >= start
                }
                while offset < blocks.count {
                    let blockIndex = blocks[offset]
                    let placed = section.blocks[blockIndex]
                    let items = placed.data.laneItems[lane]
                    if placed.data.records[items[0]].origin + placed.shift > end { break }
                    var item = lowerBound(items.count) {
                        let record = placed.data.records[items[$0]]
                        return record.origin + placed.shift + record.length >= start
                    }
                    while item < items.count {
                        let localIndex = items[item]
                        let value = placed.data.records[localIndex]
                        if value.origin + placed.shift > end { break }
                        if countCandidates { diagnostics.queryCandidates += 1 }
                        let shifted = Record(key: value.key, identity: value.identity, lane: value.lane, origin: value.origin + placed.shift, length: value.length)
                        if frame(for: shifted, section: index, in: snapshot).intersects(rect) {
                            result.append(IndexPath(item: blockIndex * Self.blockSize + localIndex, section: index))
                        }
                        item += 1
                    }
                    offset += 1
                }
            }
        }
        return result
    }
    open override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result = paths(in: rect, snapshot: geometry, countCandidates: true).compactMap { layoutAttributesForItem(at: $0) }
        // 边界补充视图的自然位置和固定位置均受分区范围约束；背景可以延伸到分区之外。
        for section in intersectingSections(rect, in: geometry) {
            let metrics = geometry.sections[section].metrics
            let path = IndexPath(item: 0, section: section)
            for item in [metrics.boundary.start, metrics.boundary.end].compactMap({ $0 }) {
                if let attributes = layoutAttributesForSupplementaryView(ofKind: item.elementKind, at: path), attributes.frame.intersects(rect) {
                    result.append(attributes)
                }
            }
        }
        // 装饰视图的区间使用独立索引，包含 contentInsets 为负值时向外延伸的范围。
        for entry in decorationCandidates(in: rect) {
            if let attributes = layoutAttributesForDecorationView(ofKind: entry.1, at: IndexPath(item: 0, section: entry.0)), attributes.frame.intersects(rect) {
                result.append(attributes)
            }
        }
        return result
    }

    private func physicalRect(origin: CGFloat, cross: CGFloat, length: CGFloat, crossLength: CGFloat) -> CGRect {
        let origin = geometry.horizontal && geometry.rtl ? geometry.size.width - origin - length : origin
        return geometry.horizontal ? CGRect(x: origin, y: cross, width: length, height: crossLength)
            : CGRect(x: cross, y: origin, width: crossLength, height: length)
    }
    open override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item == 0, geometry.sections.indices.contains(indexPath.section), let collectionView else { return nil }
        let section = geometry.sections[indexPath.section]
        let metrics = section.metrics
        let isHeader = elementKind == metrics.boundary.start?.elementKind
        guard let item = isHeader ? metrics.boundary.start : metrics.boundary.end, item.elementKind == elementKind else { return nil }
        let length = isHeader ? metrics.header : metrics.footer
        let start = geometry.starts[indexPath.section]
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: indexPath)
        attributes.frame = physicalRect(origin: start + (isHeader ? 0 : section.length - length), cross: metrics.crossStart, length: length, crossLength: metrics.crossLength)
        attributes.zIndex = max(1, item.zIndex)
        guard item.pinToVisibleBounds else { return attributes }
        let inset = collectionView.adjustedContentInset
        let visibleStart = horizontal ? collectionView.bounds.minX + inset.left : collectionView.bounds.minY + inset.top
        let visibleEnd = horizontal ? collectionView.bounds.maxX - inset.right : collectionView.bounds.maxY - inset.bottom
        let pinsAtStart = isHeader != (geometry.horizontal && geometry.rtl)
        let counterpart = isHeader ? metrics.footer : metrics.header
        let rangeStart = geometry.horizontal && geometry.rtl ? geometry.size.width - start - section.length : start
        let lower = rangeStart + (pinsAtStart ? 0 : counterpart)
        let upper = rangeStart + section.length - length - (pinsAtStart ? counterpart : 0)
        let natural = mainOrigin(attributes.frame)
        let desired = pinsAtStart ? max(natural, visibleStart) : min(natural, visibleEnd - length)
        let origin = max(lower, min(desired, max(lower, upper)))
        if geometry.horizontal { attributes.frame.origin.x = origin } else { attributes.frame.origin.y = origin }
        attributes.zIndex = max(item.zIndex, isHeader ? 1024 : 1023)
        return attributes
    }
    private func decorationFrame(_ item: NSCollectionLayoutDecorationItem, section index: Int) -> CGRect? {
        let inset = item.contentInsets
        guard [inset.top, inset.leading, inset.bottom, inset.trailing].allSatisfy(\.isFinite) else { return nil }
        let section = geometry.sections[index]
        guard section.length > 0, geometry.crossLength > 0 else { return nil }
        let start = geometry.horizontal ? inset.leading : inset.top
        let end = geometry.horizontal ? inset.trailing : inset.bottom
        let crossStart = geometry.horizontal ? inset.top : (geometry.rtl ? inset.trailing : inset.leading)
        let crossEnd = geometry.horizontal ? inset.bottom : (geometry.rtl ? inset.leading : inset.trailing)
        let length = max(0, section.length - start - end)
        let crossLength = max(0, geometry.crossLength - crossStart - crossEnd)
        guard length > 0, crossLength > 0 else { return nil }
        return physicalRect(origin: geometry.starts[index] + start, cross: crossStart, length: length, crossLength: crossLength)
    }
    open override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item == 0, geometry.sections.indices.contains(indexPath.section),
              let item = geometry.sections[indexPath.section].metrics.configuration.decorationItems.first(where: { $0.elementKind == elementKind }),
              let frame = decorationFrame(item, section: indexPath.section) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: elementKind, with: indexPath)
        attributes.frame = frame
        attributes.zIndex = item.zIndex
        return attributes
    }
    private var decorationIntervals: [(start: CGFloat, end: CGFloat, section: Int, kind: String)] = []
    private var decorationPrefixEnds: [CGFloat] = []
    private func updateDecorationIndex() {
        decorationIntervals = geometry.sections.indices.flatMap { index in
            geometry.sections[index].metrics.configuration.decorationItems.compactMap { item in
                decorationFrame(item, section: index).map { frame in
                    (start: mainOrigin(frame), end: mainOrigin(frame) + main(frame.size), section: index, kind: item.elementKind)
                }
            }
        }.sorted { $0.start < $1.start }
        var end: CGFloat = -.infinity
        decorationPrefixEnds = decorationIntervals.map { end = max(end, $0.end); return end }
    }
    private func decorationCandidates(in rect: CGRect) -> [(Int, String)] {
        let start = mainOrigin(rect), end = start + main(rect.size)
        let first = lowerBound(decorationPrefixEnds.count) { decorationPrefixEnds[$0] >= start }
        var result: [(Int, String)] = []
        for index in first..<decorationIntervals.count {
            let entry = decorationIntervals[index]
            if entry.start > end { break }
            if entry.end >= start { result.append((entry.section, entry.kind)) }
        }
        return result
    }

    open override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size || geometry.hasPinnedBoundaries
    }
    open override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds) as! InvalidationContext
        context.preservesMeasurements = true
        context.updatesGeometry = newBounds.size != collectionView?.bounds.size
        if context.updatesGeometry {
            let next = makeGeometry(bounds: newBounds)
            context.candidate = Candidate(geometry: next, baseVersion: version, sizingChanged: true)
            setAnchorAdjustment(context, next: next)
        }
        return context
    }
    open override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
        guard validKey(originalAttributes) != nil else { return false }
        let length = rounded(main(preferredAttributes.size))
        return valid(length, allowsZero: false) && length != main(originalAttributes.size)
    }
    open override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes) as! InvalidationContext
        context.preservesMeasurements = true
        context.updatesGeometry = false
        if let key = validKey(originalAttributes) {
            let length = rounded(main(preferredAttributes.size))
            if valid(length, allowsZero: false) {
                context.measurement = (key, length)
                context.path = originalAttributes.indexPath
                let candidate = repacked(at: originalAttributes.indexPath, measurement: (key, length))
                context.candidate = candidate
                setAnchorAdjustment(context, next: candidate.geometry)
            }
        }
        return context
    }
    open override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        let custom = context as? InvalidationContext
        if custom?.measurement != nil, let collectionView { refreshEnvironment(collectionView.bounds) }
        if let (key, length) = custom?.measurement, let path = custom?.path,
           let current = record(at: path, in: geometry), current.key == key,
           !geometryNeedsUpdate, key.generation == generation {
            let metadata = itemMetadataProvider?(path) ?? ItemMetadata(identifier: path)
            if metadata.identifier == key.id, metadata.contentVersion == key.revision {
                let candidate: Candidate
                if let cached = custom?.candidate, cached.baseVersion == version { candidate = cached; diagnostics.candidateReuses += 1 }
                else { candidate = repacked(at: path, measurement: (key, length)); if let custom { setAnchorAdjustment(custom, next: candidate.geometry) } }
                if cachedLength(key, touch: false) != length { acceptedMeasurementCount += 1 }
                geometry = candidate.geometry
                version += 1
                storeMeasurement(key, length: length)
                if candidate.sizingChanged { notifySizingChange() }
                updateDecorationIndex()
                pendingOffsetTarget = custom?.targetOffset
                lastOffsetObserved = collectionView?.contentOffset
            } else {
                context.contentOffsetAdjustment = .zero
            }
        } else if custom?.measurement != nil {
            // 过期回调不得改变几何或对应的滚动锚点。
            context.contentOffsetAdjustment = .zero
        } else if let custom, let candidate = custom.candidate, custom.measurement == nil, candidate.baseVersion == version {
            pendingBounds = candidate
            geometryNeedsUpdate = true
            pendingOffsetTarget = custom.targetOffset
            lastOffsetObserved = collectionView?.contentOffset
        } else if custom?.updatesGeometry != false {
            if custom?.candidate != nil { context.contentOffsetAdjustment = .zero }
            rememberAnchors()
            pendingBounds = nil
            geometryNeedsUpdate = true
            version += 1
            sections.removeAll()
            if custom?.preservesMeasurements != true {
                if context.invalidateDataSourceCounts {
                    // 数据源更新时按稳定标识保留测量结果。
                } else if !context.invalidateEverything, let paths = context.invalidatedItemIndexPaths {
                    for path in paths { if let key = record(at: path, in: geometry)?.key { measurements.removeValue(forKey: key.id) } }
                } else {
                    generation += 1
                    measurements.removeAll()
                }
            }
        }
        super.invalidateLayout(with: context)
    }
    private func validKey(_ attributes: UICollectionViewLayoutAttributes) -> WaterfallMeasurementKey? {
        guard let collectionView else { return nil }
        refreshEnvironment(collectionView.bounds)
        let path = attributes.indexPath
        guard !geometryNeedsUpdate, attributes.representedElementCategory == .cell,
              path.section >= 0, path.item >= 0, path.section < collectionView.numberOfSections,
              path.item < collectionView.numberOfItems(inSection: path.section),
              let key = (attributes as? WaterfallAttributes)?.measurementKey, key.selfSizing,
              record(at: path, in: geometry)?.key == key else { return nil }
        let metadata = itemMetadataProvider?(path) ?? ItemMetadata(identifier: path)
        return metadata.identifier == key.id && metadata.contentVersion == key.revision ? key : nil
    }
    private func cachedLength(_ key: WaterfallMeasurementKey, touch: Bool = true) -> CGFloat? {
        guard var entries = measurements[key.id], let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        if touch { measurementClock &+= 1; entries[index].use = measurementClock; measurements[key.id] = entries }
        return entries[index].length
    }
    private func storeMeasurement(_ key: WaterfallMeasurementKey, length: CGFloat) {
        var entries = measurements[key.id] ?? []
        entries.removeAll { $0.key == key }
        measurementClock &+= 1
        entries.append(Measurement(key: key, length: length, use: measurementClock))
        if entries.count > 4 {
            let active = geometry.idPaths[key.id].flatMap { record(at: $0, in: geometry)?.key }
            let victim = entries.indices.filter { entries[$0].key != active }.min { entries[$0].use < entries[$1].use }!
            entries.remove(at: victim)
        }
        measurements[key.id] = entries
    }
    private func pruneMeasurements() {
        laneResolutions = laneResolutions.filter { geometry.sections.indices.contains($0.key) }
        let sectionWidths = geometry.sections.map { Set($0.metrics.lanes.map(\.crossLength)) }
        for id in Array(measurements.keys) {
            guard let path = geometry.idPaths[id], let record = record(at: path, in: geometry) else {
                measurements.removeValue(forKey: id); continue
            }
            let widths = sectionWidths[path.section]
            measurements[id] = measurements[id]?.filter { entry in
                var normalized = entry.key
                normalized.crossLength = record.key.crossLength
                return normalized == record.key && widths.contains(entry.key.crossLength)
            }
            if measurements[id]?.isEmpty == true { measurements.removeValue(forKey: id) }
        }
    }
    private func makeBlock(inputs: [WaterfallMeasurementKey], start: Int, ends: [CGFloat], metrics: SectionMetrics,
                           measurement: (WaterfallMeasurementKey, CGFloat)? = nil, previousBlock: Block? = nil) -> Block {
        var next = ends
        var records: [Record] = []
        var laneItems = Array(repeating: [Int](), count: next.count)
        for item in start..<min(start + Self.blockSize, inputs.count) {
            var lane = 0
            if next.count == 2 { lane = next[1] < next[0] ? 1 : 0 }
            else { for index in next.indices.dropFirst() { if next[index] < next[lane] { lane = index } } }
            var key = inputs[item]
            key.crossLength = metrics.uniformLaneLength ?? metrics.lanes[lane].crossLength
            let length = key.selfSizing ? (measurement?.0 == key ? measurement!.1 : cachedLength(key) ?? key.estimatedLength) : key.estimatedLength
            laneItems[lane].append(records.count)
            let identity: WaterfallMeasurementIdentity
            if let previousBlock {
                // 增量重排复用同一份输入；只有换列后的交叉轴约束可能改变测量键。
                let previous = previousBlock.records[records.count]
                identity = previous.key.crossLength == key.crossLength ? previous.identity : WaterfallMeasurementIdentity()
            } else if let path = geometry.idPaths[key.id], let previous = record(at: path, in: geometry), previous.key == key {
                identity = previous.identity
            } else {
                identity = WaterfallMeasurementIdentity()
            }
            records.append(Record(key: key, identity: identity, lane: lane, origin: next[lane], length: length))
            next[lane] += length + metrics.line
        }
        diagnostics.repackedItems += records.count
        return Block(records: records, before: ends, after: next, laneItems: laneItems)
    }
    private func refreshStarts(_ snapshot: inout Geometry) {
        var cursor: CGFloat = 0
        snapshot.starts = snapshot.sections.indices.map { index in
            if index > 0 { cursor += snapshot.spacing }
            let start = cursor
            cursor += snapshot.sections[index].length
            return start
        }
        let main = max(cursor, snapshot.minimumMain)
        snapshot.size = snapshot.horizontal ? CGSize(width: main, height: snapshot.crossLength) : CGSize(width: snapshot.crossLength, height: main)
    }
    private func makeGeometry(bounds: CGRect) -> Geometry {
        guard let collectionView else { return Geometry() }
        refreshEnvironment(bounds)
        diagnostics.fullRebuilds += 1
        var result = Geometry()
        result.horizontal = horizontal; result.rtl = rtl; result.boundsSize = bounds.size
        result.spacing = configuration.interSectionSpacing
        result.crossLength = max(0, cross(bounds.size) - (horizontal ? resolutionInsets.top + resolutionInsets.bottom : resolutionInsets.left + resolutionInsets.right))
        result.minimumMain = horizontal && rtl ? max(0, bounds.width - resolutionInsets.left - resolutionInsets.right) : 0
        let traits = resolutionTraits ?? UITraitCollection()
        let environment = WaterfallEnvironment(size: bounds.size, insets: resolutionInsets, rtl: rtl, traits: traits)
        for index in 0..<collectionView.numberOfSections {
            let metrics = sectionMetrics(index, bounds: bounds)
            if metrics.boundary.start?.pinToVisibleBounds == true || metrics.boundary.end?.pinToVisibleBounds == true { result.hasPinnedBoundaries = true }
            let count = collectionView.numberOfItems(inSection: index)
            var inputs: [WaterfallMeasurementKey] = []
            inputs.reserveCapacity(count)
            for item in 0..<count {
                let path = IndexPath(item: item, section: index)
                let metadata = itemMetadataProvider?(path) ?? ItemMetadata(identifier: path)
                let supplied = metrics.configuration.itemLengthDimensionProvider?(item, environment) ?? metrics.configuration.itemLengthDimension
                let dimension = valid(supplied.dimension, allowsZero: false) ? supplied : metrics.configuration.itemLengthDimension
                var length = dimension.dimension
                if dimension.isFractionalWidth { length *= max(1, bounds.width - resolutionInsets.left - resolutionInsets.right) }
                if dimension.isFractionalHeight { length *= max(1, bounds.height - resolutionInsets.top - resolutionInsets.bottom) }
                if !valid(length, allowsZero: false) { length = 50 }
                inputs.append(WaterfallMeasurementKey(id: metadata.identifier, revision: metadata.contentVersion, crossLength: 0,
                    estimatedLength: length, horizontal: result.horizontal, selfSizing: dimension.isEstimated, layoutDirection: result.rtl ? 1 : 0,
                    contentSizeCategory: traits.preferredContentSizeCategory.rawValue, displayScale: traits.displayScale, generation: generation))
                result.idPaths[metadata.identifier] = path
            }
            var ends = Array(repeating: metrics.header + metrics.startInset, count: metrics.lanes.count)
            var blocks: [PlacedBlock] = []
            var laneBlocks = Array(repeating: [Int](), count: ends.count)
            if !ends.isEmpty {
                for start in stride(from: 0, to: count, by: Self.blockSize) {
                    let block = makeBlock(inputs: inputs, start: start, ends: ends, metrics: metrics)
                    for lane in laneBlocks.indices where !block.laneItems[lane].isEmpty { laneBlocks[lane].append(blocks.count) }
                    blocks.append(PlacedBlock(data: block))
                    ends = block.after
                }
            }
            let length = (ends.max() ?? metrics.header + metrics.startInset) - (!blocks.isEmpty ? metrics.line : 0) + metrics.endInset + metrics.footer
            result.sections.append(SectionGeometry(metrics: metrics, inputs: inputs, blocks: blocks, laneBlocks: laneBlocks, length: length))
        }
        refreshStarts(&result)
        return result
    }
    private func repacked(at path: IndexPath, measurement: (WaterfallMeasurementKey, CGFloat)) -> Candidate {
        var result = geometry
        var section = result.sections[path.section]
        let start = path.item / Self.blockSize
        var ends = section.blocks[start].data.before.map { $0 + section.blocks[start].shift }
        var sizingChanged = false
        for blockIndex in start..<section.blocks.count {
            let old = section.blocks[blockIndex]
            if blockIndex > start {
                let difference = ends[0] - old.data.before[0] - old.shift
                if ends.indices.allSatisfy({ ends[$0] == old.data.before[$0] + old.shift + difference }) {
                    for index in blockIndex..<section.blocks.count { section.blocks[index].shift += difference }
                    break
                }
            }
            let next = makeBlock(inputs: section.inputs, start: blockIndex * Self.blockSize, ends: ends, metrics: section.metrics,
                                 measurement: measurement, previousBlock: old.data)
            if zip(old.data.records, next.records).contains(where: { $0.key.crossLength != $1.key.crossLength }) { sizingChanged = true }
            for lane in section.laneBlocks.indices {
                let had = !old.data.laneItems[lane].isEmpty, has = !next.laneItems[lane].isEmpty
                if had != has {
                    let position = lowerBound(section.laneBlocks[lane].count) { section.laneBlocks[lane][$0] >= blockIndex }
                    if has { section.laneBlocks[lane].insert(blockIndex, at: position) }
                    else { section.laneBlocks[lane].remove(at: position) }
                }
            }
            section.blocks[blockIndex] = PlacedBlock(data: next)
            ends = next.after
        }
        let last = section.blocks.last!
        section.length = (last.data.after.max() ?? 0) + last.shift - section.metrics.line + section.metrics.endInset + section.metrics.footer
        result.sections[path.section] = section
        refreshStarts(&result)
        return Candidate(geometry: result, baseVersion: version, sizingChanged: sizingChanged)
    }

    private func visibleAnchors() -> Anchors? {
        guard let collectionView else { return nil }
        let offset = effectiveOffset()
        let inset = collectionView.adjustedContentInset
        let origin = geometry.horizontal ? offset.x + inset.left : offset.y + inset.top
        guard origin > 0 || (geometry.horizontal && geometry.rtl) else { return nil }
        let rect = CGRect(origin: offset, size: collectionView.bounds.size)
        let visible = paths(in: rect, snapshot: geometry, countCandidates: false).sorted().compactMap { path -> (AnyHashable, CGFloat)? in
            guard let record = record(at: path, in: geometry) else { return nil }
            return (record.key.id, mainOrigin(frame(for: record, section: path.section, in: geometry)))
        }
        return Anchors(geometry: geometry, visible: visible)
    }
    private func rememberAnchors() { if pendingAnchors == nil { pendingAnchors = visibleAnchors() } }
    private func anchorAdjustment(_ anchors: Anchors?, next: Geometry, allowFallback: Bool) -> CGFloat {
        guard let anchors else { return 0 }
        for (id, origin) in anchors.visible {
            diagnostics.anchorLookups += 1
            if let path = next.idPaths[id], let record = record(at: path, in: next) {
                return mainOrigin(frame(for: record, section: path.section, in: next)) - origin
            }
        }
        guard allowFallback else { return 0 }
        for index in anchors.geometry.sections.indices {
            let old = anchors.geometry.sections[index]
            for item in old.inputs.indices {
                let id = old.inputs[item].id
                diagnostics.anchorLookups += 1
                if let path = next.idPaths[id], let record = record(at: path, in: next),
                   let previous = self.record(at: IndexPath(item: item, section: index), in: anchors.geometry) {
                    return mainOrigin(frame(for: record, section: path.section, in: next)) - mainOrigin(frame(for: previous, section: index, in: anchors.geometry))
                }
            }
        }
        return 0
    }
    private func effectiveOffset() -> CGPoint {
        guard let collectionView else { return .zero }
        if lastOffsetObserved == collectionView.contentOffset, let target = pendingOffsetTarget { return target }
        return collectionView.contentOffset
    }
    private func setAnchorAdjustment(_ context: InvalidationContext, next: Geometry) {
        guard let collectionView else { return }
        let offset = effectiveOffset()
        let delta = anchorAdjustment(visibleAnchors(), next: next, allowFallback: false)
        var desired = offset
        if next.horizontal { desired.x += delta } else { desired.y += delta }
        desired = clamped(desired, contentSize: next.size)
        context.contentOffsetAdjustment = CGPoint(x: desired.x - offset.x, y: desired.y - offset.y)
        context.targetOffset = desired
        _ = collectionView
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
                warnUnsupportedBoundary(kind: item.elementKind)
                continue
            }
            if isStart { start = item } else { end = item }
        }
        return (start, end)
    }

    private func sectionMetrics(_ section: Int, bounds: CGRect) -> SectionMetrics {
        let configuration = resolvedSection(section, bounds: bounds)
        let inset = configuration.contentInsets
        let sectionInsetReference = configuration.contentInsetsReference == .automatic ? self.configuration.contentInsetsReference : configuration.contentInsetsReference
        // 边距参考值与 adjustedContentInset 使用物理方向；分区边距在此按布局方向解析一次。
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
        // 坐标范围已经扣除 adjustedContentInset；这里只补足参考边距与分区边距之和的差值。
        let crossAvailable = max(0, cross(bounds.size) - (horizontal ? adjusted.top + adjusted.bottom : adjusted.left + adjusted.right))
        let start = horizontal ? max(0, reference.top + inset.top - adjusted.top) : max(0, reference.left + leftInset - adjusted.left)
        let end = horizontal ? max(0, reference.bottom + inset.bottom - adjusted.bottom) : max(0, reference.right + rightInset - adjusted.right)
        let crossStart = (sectionInsetReference == .none || sectionInsetReference == .automatic) ? (horizontal ? inset.top : leftInset) : start
        let crossEnd = (sectionInsetReference == .none || sectionInsetReference == .automatic) ? (horizontal ? inset.bottom : rightInset) : end
        let available = max(0, crossAvailable - crossStart - crossEnd)
        let boundary = boundaries(configuration)
        let lanes: [ResolvedLane]
        if let cached = laneResolutions[section], cached.sizes == configuration.lanes, cached.available == available, cached.gap == gap {
            lanes = cached.lanes
        } else {
            lanes = Self.resolveLanes(configuration.lanes, available: available, spacing: gap) ?? []
            laneResolutions[section] = (configuration.lanes, available, gap, lanes)
        }
        return SectionMetrics(
            configuration: configuration, lanes: lanes,
            uniformLaneLength: lanes.allSatisfy { $0.crossLength == lanes.first?.crossLength } ? lanes.first?.crossLength : nil,
            crossStart: crossStart, crossLength: available,
            line: line, boundary: boundary,
            startInset: horizontal ? inset.leading : inset.top,
            endInset: horizontal ? inset.trailing : inset.bottom,
            header: boundary.start.map { horizontal ? $0.layoutSize.widthDimension.dimension : $0.layoutSize.heightDimension.dimension } ?? 0,
            footer: boundary.end.map { horizontal ? $0.layoutSize.widthDimension.dimension : $0.layoutSize.heightDimension.dimension } ?? 0
        )
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
    private func traceInvalidation(reason: @autoclosure () -> String) {
        #if DEBUG
        guard QuickLayoutDiagnostics.isEnabled else { return }
        let value = reason()
        Self.logger.debug("Invalidating layout; reason: \(value)")
        #endif
    }
    private func warnUnsupportedBoundary(kind: @autoclosure () -> String) {
        #if DEBUG
        let value = kind()
        Self.logger.warning("Ignoring unsupported or duplicate boundary; kind: \(value, privacy: .public)")
        #endif
    }
}

private extension UICollectionViewWaterfallLayout.Section {
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
