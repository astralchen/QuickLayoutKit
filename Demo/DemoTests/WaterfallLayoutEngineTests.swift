import OSLog
import UIKit
import QuickLayout
import Testing
import Darwin
#if WATERFALL_STANDALONE_HOST
@testable import Demo
#else
import QuickLayoutKit
@testable import QuickLayoutKitUIKit
#endif

private let logger = Logger(subsystem: "Demo.Tests", category: "WaterfallLayoutEngineTests")

@MainActor
@Suite(.serialized)
struct WaterfallLayoutEngineTests {
    typealias Layout = UICollectionViewWaterfallLayout

    @Test func laneResolutionAndSendability() async {
        let descriptions: [Layout.LaneSize] = [.fixed(120), .flexible()]
        let detached = await Task.detached { Layout.resolveLanes(descriptions, available: 360, spacing: 10) }.value
        #expect(detached?.map(\.crossLength) == [120, 230])
        func sendable<T: Sendable>(_ value: T) {}
        sendable([Layout.LaneSize.fixed(120), .adaptive(minimum: 160)])
        sendable(Layout.ItemSizing(constraint: .zero, horizontalFlexibility: .fixedSize, verticalFlexibility: .fixedSize))
        #expect(Layout.resolveLanes([], available: 360, spacing: .greatestFiniteMagnitude)?.allSatisfy { $0.crossOrigin.isFinite && $0.crossLength.isFinite } == true)
        #expect(Layout.resolveLanes([.adaptive(minimum: 160)], available: 360, spacing: 10)?.map(\.crossLength) == [175, 175])
        #expect(Layout.resolveLanes([.adaptive(minimum: 160, maximum: 180)], available: 600, spacing: 10)?.map(\.crossOrigin) == [0, 190, 380])
        #expect(Layout.resolveLanes([.fixed(120), .flexible()], available: 360, spacing: 10)?.map(\.crossLength) == [120, 230])
        #expect(Layout.resolveLanes([.fixed(70), .flexible(minimum: 20, maximum: 150), .adaptive(minimum: 35, maximum: 80)], available: 320, spacing: 10)?.map(\.crossLength) == [70, 115, 52.5, 52.5])
        #expect(Layout.resolveLanes([.adaptive(minimum: 160)], available: 159, spacing: 10)?.map(\.crossLength) == [160])
        #expect(Layout.resolveLanes([.flexible(), .flexible()], available: 0, spacing: 10) == nil)
        for invalid: [Layout.LaneSize] in [[], [.fixed(.nan)], [.fixed(-1)], [.adaptive(minimum: 0)], [.flexible(minimum: 100, maximum: 50)]] {
            #expect(Layout.resolveLanes(invalid, available: 360, spacing: 10)?.map(\.crossLength) == [175, 175])
        }
        #expect(Layout.resolveLanes([.adaptive(minimum: .leastNonzeroMagnitude)], available: 360, spacing: 0)?.map(\.crossLength) == [180, 180])
        #expect(Layout.resolveLanes([.adaptive(minimum: 160)], available: 330 - 1.0 / 3, spacing: 10)?.count == 1)
        #expect(Layout.resolveLanes([.adaptive(minimum: 160)], available: 330, spacing: 10)?.count == 2)
    }

    @Test func indexedQueriesAndIncrementalFitsMatchReference() throws {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                let fixture = EngineFixture(counts: [513, 257], lanes: [.fixed(70), .flexible(minimum: 20, maximum: 150), .adaptive(minimum: 35, maximum: 80)], horizontal: horizontal, rtl: rtl)
                var fitted: [Int: [CGFloat: CGFloat]] = [:]
                func reference() -> [IndexPath: CGRect] {
                    var frames: [IndexPath: CGRect] = [:]
                    var cursor: CGFloat = 0
                    let widths: [CGFloat] = [70, 115, 52.5, 52.5]
                    let starts: [CGFloat] = [0, 80, 205, 267.5]
                    for section in fixture.source.ids.indices {
                        if section > 0 { cursor += 13 }
                        var ends = Array(repeating: cursor, count: 4)
                        for item in fixture.source.ids[section].indices {
                            let id = fixture.source.ids[section][item]
                            let lane = ends.indices.min { ends[$0] < ends[$1] }!
                            let length = fitted[id]?[widths[lane]] ?? fixture.source.initial(item)
                            let cross = !horizontal && rtl ? 320 - starts[lane] - widths[lane] : starts[lane]
                            frames[IndexPath(item: item, section: section)] = horizontal
                                ? CGRect(x: ends[lane], y: cross, width: length, height: widths[lane])
                                : CGRect(x: cross, y: ends[lane], width: widths[lane], height: length)
                            ends[lane] += length + 7
                        }
                        cursor = ends.max()! - 7
                    }
                    if horizontal && rtl {
                        frames = frames.mapValues { CGRect(x: max(500, cursor) - $0.maxX, y: $0.minY, width: $0.width, height: $0.height) }
                    }
                    return frames
                }
                func verify() throws {
                    let expected = reference()
                    let extent = expected.values.map { horizontal ? $0.maxX : $0.maxY }.max() ?? 0
                    #expect(fixture.layout.collectionViewContentSize == (horizontal ? CGSize(width: extent, height: 320) : CGSize(width: 320, height: extent)))
                    for (path, frame) in expected {
                        let actual = try #require(fixture.layout.layoutAttributesForItem(at: path)).frame
                        #expect(actual == frame)
                        let sizing = fixture.layout.sizingForItem(at: path)
                        #expect(horizontal ? sizing.constraint.height == frame.height : sizing.constraint.width == frame.width)
                    }
                    for step in 0..<35 {
                        let length = horizontal ? fixture.layout.collectionViewContentSize.width : fixture.layout.collectionViewContentSize.height
                        let origin = max(0, length - 500) * CGFloat(step) / 34
                        let rect = horizontal ? CGRect(x: origin, y: 0, width: 500, height: 320) : CGRect(x: 0, y: origin, width: 320, height: 500)
                        let wanted = Set(expected.filter { $0.value.intersects(rect) }.map(\.key))
                        let found = Set((fixture.layout.layoutAttributesForElements(in: rect) ?? []).filter { $0.representedElementCategory == .cell }.map(\.indexPath))
                        #expect(found == wanted)
                    }
                }
                try verify()
                fixture.layout.resetDiagnostics()
                // Fixed seed, covering head, checkpoint boundaries, middle and tail.
                for item in [0, 127, 128, 255, 500, 512, 64, 254] {
                    let path = IndexPath(item: item, section: 0)
                    let original = try #require(fixture.layout.layoutAttributesForItem(at: path))
                    let cross = horizontal ? original.size.height : original.size.width
                    let length = CGFloat(90 + (item * 71) % 300)
                    fitted[fixture.source.ids[0][item], default: [:]][cross] = length
                    try fixture.fit(path, length: length)
                    fixture.layout.prepare()
                    try verify()
                }
                #expect(fixture.layout.diagnostics.fullRebuilds == 0)
            }
        }
    }

    @Test func candidatesInterleaveAndTailWorkIsBounded() throws {
        let fixture = EngineFixture(counts: [10_000])
        let first = IndexPath(item: 9980, section: 0), second = IndexPath(item: 9990, section: 0)
        let a = try fixture.context(first, length: 301)
        let b = try fixture.context(second, length: 407)
        fixture.layout.resetDiagnostics()
        fixture.source.metadataCalls = 0
        fixture.layout.invalidateLayout(with: a)
        fixture.layout.invalidateLayout(with: b)
        fixture.layout.prepare()
        #expect(fixture.layout.layoutAttributesForItem(at: first)?.size.height == 301)
        #expect(fixture.layout.layoutAttributesForItem(at: second)?.size.height == 407)
        #expect(fixture.layout.diagnostics.fullRebuilds == 0)
        #expect(fixture.layout.diagnostics.repackedItems <= 128)
        #expect(fixture.source.metadataCalls <= 4)
        let stale = try fixture.context(first, length: 355)
        fixture.source.revision += 1
        fixture.layout.invalidateSectionConfigurations(reason: "new-version")
        fixture.layout.prepare()
        let accepted = fixture.layout.acceptedMeasurementCount
        fixture.layout.resetDiagnostics()
        stale.contentOffsetAdjustment = CGPoint(x: 0, y: 99)
        fixture.layout.invalidateLayout(with: stale)
        #expect(stale.contentOffsetAdjustment == .zero)
        fixture.layout.prepare()
        #expect(fixture.layout.acceptedMeasurementCount == accepted)
        #expect(fixture.layout.diagnostics.fullRebuilds == 0)
        let attributes = try #require(fixture.layout.layoutAttributesForItem(at: first))
        fixture.collection.frame.size.width += 40
        let invalid = fixture.layout.invalidationContext(forPreferredLayoutAttributes: attributes, withOriginalAttributes: attributes)
        fixture.layout.prepare()
        fixture.layout.resetDiagnostics()
        fixture.layout.invalidateLayout(with: invalid)
        fixture.layout.prepare()
        #expect(fixture.layout.diagnostics.fullRebuilds == 0)
    }

    @Test func widthVariantsAreBoundedAndNotifyOnce() async throws {
        let fixture = EngineFixture(counts: [10], lanes: [40, 50, 60, 70, 80, 90].map { .fixed(CGFloat($0)) })
        await Task.yield()
        var notifications = 0
        fixture.layout.sizingInvalidationHandler = { notifications += 1 }
        for lane in 0..<6 {
            for item in 0..<6 { try fixture.fit(IndexPath(item: item, section: 0), length: item == lane ? 100 : 400) }
            try fixture.fit(IndexPath(item: 6, section: 0), length: CGFloat(200 + lane))
            #expect(fixture.layout.cachedMeasurementCount(for: 6) <= 4)
            #expect(fixture.layout.sizingForItem(at: IndexPath(item: 6, section: 0)).constraint.width == CGFloat(40 + lane * 10))
        }
        fixture.layout.prepare()
        #expect(fixture.layout.cachedMeasurementCount(for: 6) == 4)
        await Task.yield()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(notifications == 1)
    }

    @Test func deletionFallbackIsLinearAndSparseLaneQueryIsBounded() throws {
        let fixture = EngineFixture(counts: [10_000])
        try fixture.fit(IndexPath(item: 0, section: 0), length: 2_000_000)
        fixture.layout.prepare()
        fixture.layout.resetDiagnostics()
        let rect = CGRect(x: 0, y: 1_999_900, width: 320, height: 500)
        #expect(fixture.layout.layoutAttributesForElements(in: rect)?.count == 1)
        #expect(fixture.layout.diagnostics.queryCandidates <= 2)
        fixture.collection.contentOffset.y = 600_000
        fixture.layout.invalidateSectionConfigurations(reason: "capture-deletion")
        fixture.source.ids[0].removeFirst(9000)
        fixture.collection.reloadData()
        fixture.layout.prepare()
        #expect(fixture.layout.diagnostics.anchorLookups <= 10_100)
        #expect(fixture.layout.cachedMeasurementCount(for: 0) == 0)
        #expect(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 999, section: 0)) != nil)
    }

    @Test func boundsCandidateAndDecorationOverflowStayCorrect() throws {
        var section = Layout.Section()
        section.lanes = [.adaptive(minimum: 100)]
        section.itemLengthDimension = .absolute(50)
        let decoration = NSCollectionLayoutDecorationItem.background(elementKind: "overflow")
        decoration.contentInsets.top = -50
        section.decorationItems = [decoration]
        let source = EngineSource(counts: [8])
        let layout = Layout(section: section)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = source
        collection.reloadData(); layout.prepare()
        #expect(layout.resolvedLaneCount(in: 0) == 3)
        #expect(layout.layoutAttributesForElements(in: CGRect(x: 0, y: -40, width: 100, height: 10))?.contains { $0.representedElementCategory == .decorationView } == true)
        let bounds = CGRect(x: 0, y: 0, width: 430, height: 200)
        let context = layout.invalidationContext(forBoundsChange: bounds)
        layout.invalidateLayout(with: context)
        collection.bounds = bounds
        layout.prepare()
        #expect(layout.resolvedLaneCount(in: 0) == 4)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.size.width == 100)
        withExtendedLifetime(source) {}
    }
}

@MainActor
private final class EngineSource: NSObject, UICollectionViewDataSource {
    var ids: [[Int]]
    var metadataCalls = 0
    var revision = 0
    init(counts: [Int]) {
        var next = 0
        ids = counts.map { count in defer { next += count }; return Array(next..<(next + count)) }
    }
    func initial(_ item: Int) -> CGFloat { CGFloat(40 + (item * 37 + 17) % 140) }
    func numberOfSections(in collectionView: UICollectionView) -> Int { ids.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { ids[section].count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "engine")
        return collectionView.dequeueReusableCell(withReuseIdentifier: "engine", for: indexPath)
    }
}

@MainActor
private final class EngineFixture {
    let source: EngineSource
    let layout: UICollectionViewWaterfallLayout
    let collection: UICollectionView
    let horizontal: Bool
    init(counts: [Int], lanes: [UICollectionViewWaterfallLayout.LaneSize] = [.flexible(), .flexible()], horizontal: Bool = false, rtl: Bool = false, prepare: Bool = true) {
        self.horizontal = horizontal
        let source = EngineSource(counts: counts)
        self.source = source
        var section = UICollectionViewWaterfallLayout.Section()
        section.lanes = lanes
        section.interItemSpacing = 7
        section.itemLengthDimensionProvider = { item, _ in .estimated(source.initial(item)) }
        layout = UICollectionViewWaterfallLayout(section: section, configuration: .init(scrollDirection: horizontal ? .horizontal : .vertical, interSectionSpacing: 13))
        collection = UICollectionView(frame: horizontal ? CGRect(x: 0, y: 0, width: 500, height: 320) : CGRect(x: 0, y: 0, width: 320, height: 500), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        collection.dataSource = source
        layout.itemMetadataProvider = { path in
            source.metadataCalls += 1
            return .init(identifier: source.ids[path.section][path.item], contentVersion: source.revision)
        }
        collection.reloadData()
        if prepare { layout.prepare() }
    }
    func context(_ path: IndexPath, length: CGFloat) throws -> UICollectionViewLayoutInvalidationContext {
        let original = try #require(layout.layoutAttributesForItem(at: path))
        let preferred = original.copy() as! UICollectionViewLayoutAttributes
        if horizontal { preferred.size.width = length } else { preferred.size.height = length }
        return layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original)
    }
    func fit(_ path: IndexPath, length: CGFloat) throws { layout.invalidateLayout(with: try context(path, length: length)) }
}

extension WaterfallLayoutEngineTests {
    /// Run without parallel builds; measures the actual optimized UIKit layout, not a port of its algorithm.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK"] == "1"))
    func scalabilityMatrix() throws {
        var rows: [[String: Any]] = []
        let configurations: [(String, [Layout.LaneSize])] = [
            ("flexible", [.flexible(), .flexible()]),
            ("adaptive", [.adaptive(minimum: 100)]),
            ("mixed", [.fixed(100), .flexible()])
        ]
        for round in 1...3 {
            for count in [1_000, 10_000] {
                for (mode, horizontal, rtl) in [("vertical", false, false), ("horizontal", true, false), ("horizontal-rtl", true, true)] {
                    for (name, lanes) in configurations {
                        for sectionCount in [1, 10] {
                            try autoreleasepool {
                                let fixture = EngineFixture(counts: Array(repeating: count / sectionCount, count: sectionCount), lanes: lanes, horizontal: horizontal, rtl: rtl, prepare: false)
                                let layout = fixture.layout
                                @MainActor func capture(_ scenario: String, iterations: Int, _ body: @MainActor (Int) throws -> Void) rethrows {
                                    layout.resetDiagnostics(); fixture.source.metadataCalls = 0
                                    var samples: [Double] = []
                                    for iteration in 0..<iterations {
                                        let start = CACurrentMediaTime()
                                        try body(iteration)
                                        samples.append((CACurrentMediaTime() - start) * 1000)
                                    }
                                    let sorted = samples.sorted()
                                    let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
                                    let d = layout.diagnostics
                                    rows.append([
                                        "round": round, "items": count, "mode": mode, "configuration": name, "sections": sectionCount,
                                        "lanes": (0..<sectionCount).map { layout.resolvedLaneCount(in: $0) ?? 0 }, "scenario": scenario,
                                        "samples_ms": samples, "p50_ms": sorted[sorted.count / 2], "p95_ms": p95,
                                        "full_rebuilds": d.fullRebuilds, "repacked_items": d.repackedItems, "query_candidates": d.queryCandidates,
                                        "anchor_lookups": d.anchorLookups, "candidate_reuses": d.candidateReuses,
                                        "metadata_calls": fixture.source.metadataCalls, "cached_measurements": layout.cachedMeasurementCount,
                                        "resident_bytes": waterfallResidentBytes()
                                    ])
                                    if scenario == "cached_prepare" || scenario == "stable_scroll" || scenario == "rect_query" || scenario == "fit_prepare" {
                                        #expect(d.fullRebuilds == 0)
                                        #expect(fixture.source.metadataCalls == 0)
                                    }
                                    if scenario == "rect_query" {
                                        #expect(d.queryCandidates <= iterations * 100)
                                        #expect(p95 <= 2)
                                    }
                                    if scenario == "tail_fit" {
                                        #expect(d.fullRebuilds == 0)
                                        #expect(d.repackedItems <= iterations * 192)
                                        #expect(p95 <= 8)
                                    }
                                    if scenario == "eight_fits" { #expect(d.fullRebuilds == 0) }
                                    if scenario == "delete_90_percent" { #expect(d.anchorLookups <= count + 100) }
                                    #expect(layout.cachedMeasurementCount <= count * 4)
                                }
                                capture("cold_prepare", iterations: 1) { _ in layout.prepare() }
                                capture("cached_prepare", iterations: 20) { _ in layout.prepare() }
                                let contentLength = horizontal ? layout.collectionViewContentSize.width : layout.collectionViewContentSize.height
                                capture("stable_scroll", iterations: 20) { i in
                                    var bounds = fixture.collection.bounds
                                    if horizontal { bounds.origin.x = max(0, contentLength - 500) * CGFloat(i) / 19 }
                                    else { bounds.origin.y = max(0, contentLength - 500) * CGFloat(i) / 19 }
                                    if layout.shouldInvalidateLayout(forBoundsChange: bounds) { layout.invalidateLayout(with: layout.invalidationContext(forBoundsChange: bounds)) }
                                    fixture.collection.bounds = bounds
                                    layout.prepare()
                                }
                                capture("rect_query", iterations: 120) { i in
                                    let origin = max(0, contentLength - 500) * CGFloat(i) / 119
                                    let rect = horizontal ? CGRect(x: origin, y: 0, width: 500, height: 320) : CGRect(x: 0, y: origin, width: 320, height: 500)
                                    _ = layout.layoutAttributesForElements(in: rect)
                                }
                                let lastSection = sectionCount - 1, lastCount = count / sectionCount
                                try capture("tail_fit", iterations: 5) { i in
                                    try fixture.fit(IndexPath(item: lastCount - 1 - i * 11, section: lastSection), length: CGFloat(251 + i * 13))
                                    layout.prepare()
                                }
                                capture("fit_prepare", iterations: 20) { _ in layout.prepare() }
                                try capture("eight_fits", iterations: 1) { _ in
                                    for i in 0..<8 { try fixture.fit(IndexPath(item: lastCount / 2 + i, section: lastSection), length: CGFloat(311 + i * 17)) }
                                    layout.prepare()
                                }
                                try capture("head_fit", iterations: 1) { _ in
                                    try fixture.fit(IndexPath(item: 0, section: 0), length: 513)
                                    layout.prepare()
                                }
                                capture("delete_90_percent", iterations: 1) { _ in
                                    layout.invalidateSectionConfigurations(reason: "matrix-delete")
                                    for section in fixture.source.ids.indices { fixture.source.ids[section].removeFirst(lastCount * 9 / 10) }
                                    fixture.collection.reloadData()
                                    layout.prepare()
                                }
                            }
                        }
                    }
                }
            }
        }
        let result: [String: Any] = [
            "run_id": ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK_RUN_ID"] ?? "manual",
            "memory_metric": "sampled process resident bytes (includes UIKit/test host; not allocation peak)",
            "rows": rows
        ]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("waterfall-scalability.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        logger.notice("WATERFALL_SCALABILITY_RESULT \(url.path, privacy: .public)")
    }
}

private func waterfallResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}

extension WaterfallLayoutEngineTests {
    @Test func attributeEqualityPreservesMeasurementIdentityOffActor() async throws {
        let fixture = EngineFixture(counts: [260])
        let path = IndexPath(item: 0, section: 0)
        let original = try #require(fixture.layout.layoutAttributesForItem(at: path))
        let copied = original.copy() as! UICollectionViewLayoutAttributes
        let repeated = try #require(fixture.layout.layoutAttributesForItem(at: path))
        #expect(original.isEqual(copied))
        #expect(original.isEqual(repeated))

        // A full rebuild with unchanged input must preserve custom equality.
        fixture.layout.invalidateSectionConfigurations(reason: "same-input")
        fixture.layout.prepare()
        let rebuilt = try #require(fixture.layout.layoutAttributesForItem(at: path))
        #expect(original.isEqual(rebuilt))

        // Repacking the same block changes geometry, but not an unaffected item's key.
        try fixture.fit(IndexPath(item: 1, section: 0), length: 250)
        fixture.layout.prepare()
        let repacked = try #require(fixture.layout.layoutAttributesForItem(at: path))
        #expect(original.isEqual(repacked))

        fixture.source.revision += 1
        fixture.layout.invalidateSectionConfigurations(reason: "new-version")
        fixture.layout.prepare()
        let revised = try #require(fixture.layout.layoutAttributesForItem(at: path))
        #expect(original.frame == revised.frame)
        #expect(!original.isEqual(revised))
        let differentFrame = revised.copy() as! UICollectionViewLayoutAttributes
        differentFrame.frame.origin.y += 1
        #expect(!revised.isEqual(differentFrame))

        // NSObject equality is nonisolated. No UIKit properties are mutated during this read.
        let result = await Task.detached {
            (original.isEqual(copied), original.isEqual(repeated), original.isEqual(rebuilt),
             original.isEqual(repacked), original.isEqual(revised), revised.isEqual(differentFrame),
             original.isEqual(nil), original.isEqual(NSObject()))
        }.value
        #expect(result.0 && result.1 && result.2 && result.3)
        #expect(!result.4 && !result.5 && !result.6 && !result.7)

        let mixed = EngineFixture(counts: [3], lanes: [.fixed(70), .fixed(140)])
        let movingPath = IndexPath(item: 2, section: 0)
        let beforeMove = try #require(mixed.layout.layoutAttributesForItem(at: movingPath))
        try mixed.fit(IndexPath(item: 0, section: 0), length: 400)
        mixed.layout.prepare()
        let afterMove = try #require(mixed.layout.layoutAttributesForItem(at: movingPath))
        #expect(beforeMove.size.width != afterMove.size.width)
        // Equalize UIKit geometry to isolate the changed measurement constraint in equality.
        afterMove.frame = beforeMove.frame
        #expect(!beforeMove.isEqual(afterMove))
    }

    @Test func subclassRetainsSizingAndAttributeMetadata() throws {
        var section = Layout.Section()
        section.itemLengthDimension = .estimated(80)
        let layout = CustomWaterfallLayout(section: section)
        let source = EngineSource(counts: [5])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 500), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = source
        collection.reloadData()
        layout.prepare()
        #expect(layout.preparationCount > 0)
        let path = IndexPath(item: 0, section: 0)
        let original = try #require(layout.layoutAttributesForItem(at: path))
        #expect(original.zIndex == 42)
        let preferred = original.copy() as! UICollectionViewLayoutAttributes
        preferred.size.height = 123
        #expect(layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
        layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: path)?.size.height == 123)
        #expect(layout.layoutAttributesForElements(in: collection.bounds)?.allSatisfy { $0.zIndex == 42 } == true)
        withExtendedLifetime(source) {}
    }
}

@MainActor
private final class CustomWaterfallLayout: UICollectionViewWaterfallLayout {
    private(set) var preparationCount = 0
    override func prepare() {
        super.prepare()
        preparationCount += 1
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.layoutAttributesForItem(at: indexPath)
        attributes?.zIndex = 42
        return attributes
    }
}
