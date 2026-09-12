#!/bin/bash
# Usage: bash Scripts/check-waterfall-concurrency.sh PREBUILT_SIMULATOR_PRODUCTS [ARCH]
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_PRODUCTS="${1:?Pass matching simulator products containing QuickLayout modules}"
TASK_ARCH="${2:-$(uname -m)}"
TASK_TEMP="$(mktemp -d /private/tmp/waterfall-concurrency.XXXXXX)"
trap 'rm -rf "$TASK_TEMP"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TASK_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
cat > "$TASK_TEMP/SendableProbe.swift" <<'SWIFT'
import UIKit
import QuickLayout

actor LaneConsumer {
    func resolve(_ lanes: [UICollectionViewWaterfallLayout.LaneSize]) -> [UICollectionViewWaterfallLayout.ResolvedLane]? {
        UICollectionViewWaterfallLayout.resolveLanes(lanes, available: 360, spacing: 10)
    }
    func accept(_ sizing: UICollectionViewWaterfallLayout.ItemSizing) {}
}
@MainActor func transferLaneValues() async {
    let consumer = LaneConsumer()
    let lanes: [UICollectionViewWaterfallLayout.LaneSize] = [.fixed(100), .adaptive(minimum: 100)]
    _ = await consumer.resolve(lanes)
    await consumer.accept(.init(constraint: .zero, horizontalFlexibility: .fixedSize, verticalFlexibility: .fixedSize))
}
SWIFT
xcrun swiftc -emit-module -parse-as-library -swift-version 6 -strict-concurrency=complete -default-isolation MainActor \
    -module-name WaterfallIsolationProbe -emit-module-path "$TASK_TEMP/WaterfallIsolationProbe.swiftmodule" \
    -target "$TASK_ARCH-apple-ios15.0-simulator" -sdk "$TASK_SDK" -I "$TASK_PRODUCTS" \
    -module-cache-path "$TASK_TEMP/cache" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutDiagnostics.swift" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift" \
    "$TASK_TEMP/SendableProbe.swift"
cat > "$TASK_TEMP/IsolationProbe.swift" <<'SWIFT'
nonisolated func illegalSectionMutation() {
    var section = UICollectionViewWaterfallLayout.Section()
    section.lanes = [.fixed(100)]
}
SWIFT
if xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=complete -default-isolation MainActor \
    -target "$TASK_ARCH-apple-ios15.0-simulator" -sdk "$TASK_SDK" -I "$TASK_PRODUCTS" \
    -module-cache-path "$TASK_TEMP/cache" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutDiagnostics.swift" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift" \
    "$TASK_TEMP/IsolationProbe.swift" > "$TASK_TEMP/isolation.log" 2>&1; then
    echo 'Expected off-actor Section construction to be rejected' >&2
    exit 1
fi
if ! rg -q 'main actor-isolated.*(initializer|property|method)' "$TASK_TEMP/isolation.log"; then
    cat "$TASK_TEMP/isolation.log" >&2
    exit 1
fi
echo 'Swift 6 strict concurrency: value transfer passed; off-actor Section construction rejected.'
# Compile a separate client without @testable: validates the framework's public boundary.
xcrun swiftc -emit-module -parse-as-library -swift-version 6 -strict-concurrency=complete -DDEBUG \
    -module-name WaterfallPublicAPI -emit-module-path "$TASK_TEMP/WaterfallPublicAPI.swiftmodule" \
    -target "$TASK_ARCH-apple-ios15.0-simulator" -sdk "$TASK_SDK" -I "$TASK_PRODUCTS" \
    -module-cache-path "$TASK_TEMP/cache" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/QuickLayoutDiagnostics.swift" \
    "$TASK_ROOT/Sources/QuickLayoutKit/QuickLayoutKitUIKit/UICollectionViewWaterfallLayout.swift"
cat > "$TASK_TEMP/PublicClient.swift" <<'SWIFT'
import UIKit
import QuickLayout
import WaterfallPublicAPI

nonisolated func compareAttributes(_ lhs: UICollectionViewLayoutAttributes,
                                  _ rhs: UICollectionViewLayoutAttributes) -> Bool {
    lhs.isEqual(rhs)
}

@MainActor final class ClientWaterfallLayout: UICollectionViewWaterfallLayout {
    override func prepare() { super.prepare() }
    override var collectionViewContentSize: CGSize { super.collectionViewContentSize }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        super.layoutAttributesForElements(in: rect)
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath)
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)
    }
}

@MainActor func makePublicLayout() -> UICollectionViewWaterfallLayout {
    var section = UICollectionViewWaterfallLayout.Section()
    section.lanes = [.fixed(100), .flexible(), .adaptive(minimum: 80)]
    section.itemLengthDimension = .estimated(120)
    section.itemLengthDimensionProvider = { _, _ in .estimated(160) }
    let configuration = UICollectionViewWaterfallLayout.Configuration(
        scrollDirection: .vertical, interSectionSpacing: 12, contentInsetsReference: .none)
    let layout = ClientWaterfallLayout(section: section, configuration: configuration)
    layout.itemMetadataProvider = { path in .init(identifier: path, contentVersion: 1) }
    layout.sizingInvalidationHandler = {}
    _ = layout.resolvedLaneCount(in: 0)
    _ = layout.sizingForItem(at: IndexPath(item: 0, section: 0))
    _ = layout.section(at: 0)
    _ = UICollectionViewWaterfallLayout.ItemSizing(
        constraint: .zero, horizontalFlexibility: .fixedSize, verticalFlexibility: .fullyFlexible)
    _ = UICollectionViewWaterfallLayout(sectionProvider: { _, _ in section })
    layout.invalidateSectionConfigurations(reason: "client")
    layout.invalidateMeasurements(reason: "client")
    return layout
}
SWIFT
xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=complete \
    -target "$TASK_ARCH-apple-ios15.0-simulator" -sdk "$TASK_SDK" -I "$TASK_PRODUCTS" -I "$TASK_TEMP" \
    -module-cache-path "$TASK_TEMP/cache" "$TASK_TEMP/PublicClient.swift"
echo 'Public API: external Swift 6 client passed at the iOS 15 deployment target.'
