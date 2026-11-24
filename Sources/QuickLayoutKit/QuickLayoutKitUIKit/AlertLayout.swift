import UIKit

enum AlertLayout {
    static func availableRegion(_ bounds: CGRect, divisions: [CGRect], occlusions: [CGRect],
                                insets: UIEdgeInsets, anchor: CGPoint?, rtl: Bool) -> CGRect {
        let regions = SheetRegionGeometry.regions(in: bounds, divisions: divisions)
            .map { $0.inset(by: insets) }
            .filter { !$0.isEmpty }
        let usable = occlusions.reduce(regions) { regions, occlusion in
            regions.flatMap { region -> [CGRect] in
                let covered = region.intersection(occlusion)
                guard !covered.isNull, !covered.isEmpty else { return [region] }
                return [
                    CGRect(x: region.minX, y: region.minY, width: region.width, height: covered.minY - region.minY),
                    CGRect(x: region.minX, y: covered.maxY, width: region.width, height: region.maxY - covered.maxY),
                    CGRect(x: region.minX, y: region.minY, width: covered.minX - region.minX, height: region.height),
                    CGRect(x: covered.maxX, y: region.minY, width: region.maxX - covered.maxX, height: region.height),
                ].filter { !$0.isEmpty }
            }
        }
        return usable.max { first, second in
            if let anchor, first.contains(anchor) != second.contains(anchor) { return second.contains(anchor) }
            let firstArea = first.width * first.height
            let secondArea = second.width * second.height
            if firstArea != secondArea { return firstArea < secondArea }
            if first.midY != second.midY { return first.midY < second.midY }
            return rtl ? first.midX < second.midX : first.midX > second.midX
        } ?? .zero
    }
}
