import OSLog
import UIKit
import Testing
#if WATERFALL_STANDALONE_HOST
@testable import Demo
#else
import QuickLayoutKit
@testable import QuickLayoutKitUIKit
#endif

private let logger = Logger(subsystem: "Demo.Tests", category: "WaterfallLayoutPerformanceTests")

/// Opt-in baseline against the real UIKit layout. See Scripts/run-waterfall-benchmark.sh.
/// Cells are not mounted: this measures layout work, not text fitting or rendering/FPS.
@MainActor
@Suite(.serialized)
struct WaterfallLayoutPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK"] == "1"))
    func layoutBaseline() throws {
        var records: [[String: Any]] = []
        func record(_ scenario: String, count: Int, mode: String, milliseconds: [Double], calls: Int) {
            let sorted = milliseconds.sorted()
            let row: [String: Any] = [
                "scenario": scenario, "items": count, "mode": mode,
                "samples": sorted.count, "median_ms": sorted[sorted.count / 2],
                "p95_ms": sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)],
                "total_ms": sorted.reduce(0, +), "metadata_calls": calls
            ]
            records.append(row)
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            logger.notice("WATERFALL_BENCHMARK \(String(decoding: data, as: UTF8.self), privacy: .public)")
        }
        func elapsed(_ operation: () -> Void) -> Double {
            let start = ProcessInfo.processInfo.systemUptime
            // A synchronous benchmark does not return to the run loop between frames.
            // Drain temporary UIKit objects as a normal frame would, avoiding cumulative pressure.
            autoreleasepool(invoking: operation)
            return (ProcessInfo.processInfo.systemUptime - start) * 1000
        }

        for count in [1_000, 10_000] {
            for mode in ["vertical", "horizontal", "horizontal-rtl"] {
                try autoreleasepool {
                    let source = BenchmarkSource(count: count)
                    var section = UICollectionViewWaterfallLayout.Section()
                    section.lanes = Array(repeating: .flexible(), count: 2)
                    section.itemLengthDimension = .estimated(120)
                    let direction: UICollectionView.ScrollDirection = mode == "vertical" ? .vertical : .horizontal
                    let layout = UICollectionViewWaterfallLayout(section: section, configuration: .init(scrollDirection: direction))
                    let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
                    collection.contentInsetAdjustmentBehavior = .never
                    collection.semanticContentAttribute = mode == "horizontal-rtl" ? .forceRightToLeft : .forceLeftToRight
                    collection.dataSource = source
                    layout.itemMetadataProvider = { path in
                        source.metadataCalls += 1
                        return .init(identifier: source.ids[path.item])
                    }
                    collection.reloadData()
                    source.metadataCalls = 0
                    let cold = elapsed { layout.prepare() }
                    record("cold_prepare", count: count, mode: mode, milliseconds: [cold], calls: source.metadataCalls)
                    #expect(layout.layoutAttributesForItem(at: IndexPath(item: count - 1, section: 0)) != nil)

                    source.metadataCalls = 0
                    var warm: [Double] = []
                    for _ in 0..<20 { warm.append(elapsed { layout.prepare() }) }
                    record("cached_prepare", count: count, mode: mode, milliseconds: warm, calls: source.metadataCalls)
                    #expect(source.metadataCalls == 0)

                    source.metadataCalls = 0
                    var queries: [Double] = []
                    for step in 0..<120 {
                        let extent = direction == .vertical ? layout.collectionViewContentSize.height - collection.bounds.height : layout.collectionViewContentSize.width - collection.bounds.width
                        let offset = max(0, extent) * CGFloat(step) / 119
                        let rect = CGRect(origin: direction == .vertical ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0), size: collection.bounds.size)
                        var attributes: [UICollectionViewLayoutAttributes] = []
                        queries.append(elapsed { attributes = layout.layoutAttributesForElements(in: rect) ?? [] })
                        #expect(!attributes.isEmpty)
                        #expect(attributes.allSatisfy { $0.frame.intersects(rect) })
                    }
                    record("rect_query", count: count, mode: mode, milliseconds: queries, calls: source.metadataCalls)

                    let anchorPath = IndexPath(item: count * 3 / 4, section: 0)
                    let anchorFrame = try #require(layout.layoutAttributesForItem(at: anchorPath)).frame
                    collection.contentOffset = direction == .vertical ? CGPoint(x: 0, y: anchorFrame.minY) : CGPoint(x: anchorFrame.minX, y: 0)
                    layout.prepare()
                    var callbacks: [Double] = [], commits: [Double] = []
                    var callbackCalls = 0, commitCalls = 0
                    for index in 0..<5 {
                        let path = IndexPath(item: count * 3 / 4 + index, section: 0)
                        let original = try #require(layout.layoutAttributesForItem(at: path))
                        let preferred = original.copy() as! UICollectionViewLayoutAttributes
                        if direction == .vertical { preferred.size.height = CGFloat(180 + index * 7) }
                        else { preferred.size.width = CGFloat(180 + index * 7) }
                        #expect(layout.shouldInvalidateLayout(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
                        source.metadataCalls = 0
                        callbacks.append(elapsed {
                            let context = layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original)
                            layout.invalidateLayout(with: context)
                        })
                        callbackCalls += source.metadataCalls
                        source.metadataCalls = 0
                        commits.append(elapsed { layout.prepare() })
                        commitCalls += source.metadataCalls
                        let updated = try #require(layout.layoutAttributesForItem(at: path))
                        #expect(direction == .vertical ? updated.size.height == preferred.size.height : updated.size.width == preferred.size.width)
                    }
                    record("fit_callback_and_invalidate", count: count, mode: mode, milliseconds: callbacks, calls: callbackCalls)
                    record("fit_prepare", count: count, mode: mode, milliseconds: commits, calls: commitCalls)

                    source.metadataCalls = 0
                    let batch = elapsed {
                        for index in 0..<8 {
                            let path = IndexPath(item: count * 3 / 4 + 10 + index, section: 0)
                            let original = layout.layoutAttributesForItem(at: path)!
                            let preferred = original.copy() as! UICollectionViewLayoutAttributes
                            if direction == .vertical { preferred.size.height = CGFloat(210 + index) }
                            else { preferred.size.width = CGFloat(210 + index) }
                            layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
                        }
                        layout.prepare()
                    }
                    record("eight_fits_one_prepare", count: count, mode: mode, milliseconds: [batch], calls: source.metadataCalls)
                    #expect(layout.acceptedMeasurementCount == 13)

                    if mode == "vertical" {
                        // Delete 90% including all visible anchors, retaining stable IDs in the tail.
                        // invalidateSectionConfigurations captures anchors without clearing fitted lengths.
                        source.metadataCalls = 0
                        let deletion = elapsed {
                            layout.invalidateSectionConfigurations(reason: "benchmark-delete")
                            source.ids.removeFirst(count * 9 / 10)
                            collection.reloadData()
                            layout.prepare()
                        }
                        record("delete_90_percent", count: count, mode: mode, milliseconds: [deletion], calls: source.metadataCalls)
                        #expect(layout.layoutAttributesForItem(at: IndexPath(item: source.ids.count - 1, section: 0)) != nil)
                    }
                    withExtendedLifetime(source) {}
                }
            }

            // Reproduce the Demo's linear metadata lookup separately from the O(1) layout fixture.
            autoreleasepool {
                let source = BenchmarkSource(count: count)
                let rows = source.ids.map { (id: $0, revision: 0) }
                var section = UICollectionViewWaterfallLayout.Section()
                section.itemLengthDimension = .estimated(120)
                let layout = UICollectionViewWaterfallLayout(section: section)
                let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
                collection.contentInsetAdjustmentBehavior = .never
                collection.dataSource = source
                layout.itemMetadataProvider = { path in
                    source.metadataCalls += 1
                    let id = source.ids[path.item]
                    let row = rows.first { $0.id == id }!
                    return .init(identifier: row.id, contentVersion: row.revision)
                }
                collection.reloadData()
                source.metadataCalls = 0
                let time = elapsed { layout.prepare() }
                record("cold_prepare_linear_metadata", count: count, mode: "vertical", milliseconds: [time], calls: source.metadataCalls)
                // Paired lookup-only samples avoid comparing separate cold layouts under different load.
                let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                let order = (0..<count).map { ($0 * 7919) % count }
                var linearTimes: [Double] = [], indexedTimes: [Double] = []
                for _ in 0..<5 {
                    var linearSum = 0, indexedSum = 0
                    linearTimes.append(elapsed {
                        for id in order { linearSum += rows.first(where: { $0.id == id })!.id }
                    })
                    indexedTimes.append(elapsed {
                        for id in order { indexedSum += byID[id]!.id }
                    })
                    #expect(linearSum == count * (count - 1) / 2)
                    #expect(indexedSum == linearSum)
                }
                record("metadata_linear_lookup_pass", count: count, mode: "vertical", milliseconds: linearTimes, calls: count * 5)
                record("metadata_indexed_lookup_pass", count: count, mode: "vertical", milliseconds: indexedTimes, calls: count * 5)
                withExtendedLifetime(source) {}
            }
        }
        let result: [String: Any] = [
            "device": UIDevice.current.model, "os": UIDevice.current.systemVersion,
            "run_id": ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK_RUN_ID"] ?? "manual",
            "scope": "Real layout in UIKit simulator; manual fitting callbacks; no mounted content cells or rendering",
            "records": records
        ]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("waterfall-benchmark.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        logger.notice("WATERFALL_BENCHMARK_RESULT \(url.path, privacy: .public)")
    }
}

@MainActor
private final class BenchmarkSource: NSObject, UICollectionViewDataSource {
    var ids: [Int]
    var metadataCalls = 0
    init(count: Int) { ids = Array(0..<count) }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { ids.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "benchmark")
        return collectionView.dequeueReusableCell(withReuseIdentifier: "benchmark", for: indexPath)
    }
}

extension WaterfallLayoutPerformanceTests {
    /// Separate fresh fixtures keep the original baseline sequence unchanged.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK"] == "1"))
    func headUpdateBaseline() throws {
        var rows: [[String: Any]] = []
        for round in 1...3 {
            for count in [1_000, 10_000] {
                try autoreleasepool {
                    let source = BenchmarkSource(count: count)
                    var section = UICollectionViewWaterfallLayout.Section()
                    section.itemLengthDimension = .estimated(120)
                    let layout = UICollectionViewWaterfallLayout(section: section)
                    let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
                    collection.contentInsetAdjustmentBehavior = .never
                    collection.dataSource = source
                    layout.itemMetadataProvider = { path in
                        source.metadataCalls += 1
                        return .init(identifier: source.ids[path.item])
                    }
                    collection.reloadData(); layout.prepare()
                    let original = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
                    let preferred = original.copy() as! UICollectionViewLayoutAttributes
                    preferred.size.height = 513
                    source.metadataCalls = 0
                    let start = CACurrentMediaTime()
                    layout.invalidateLayout(with: layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original))
                    layout.prepare()
                    let milliseconds = (CACurrentMediaTime() - start) * 1000
                    #expect(layout.layoutAttributesForItem(at: original.indexPath)?.size.height == 513)
                    rows.append(["round": round, "items": count, "scenario": "head_fit", "milliseconds": milliseconds, "metadata_calls": source.metadataCalls])
                    withExtendedLifetime(source) {}
                }
            }
        }
        let result: [String: Any] = ["run_id": ProcessInfo.processInfo.environment["WATERFALL_BENCHMARK_RUN_ID"] ?? "manual", "rows": rows]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("waterfall-head.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
