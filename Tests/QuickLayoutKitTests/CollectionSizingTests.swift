import Testing
import UIKit
import QuickLayout
import QuickLayoutKitUIKit

@MainActor
extension QuickLayoutKitTests {
    @Test func cellFittingUsesSubclassMeasurementWithoutMeasuringBodyAgain() {
        let cell = SizingOverrideCell(frame: .zero)
        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: 0, section: 0)
        )
        attributes.size = CGSize(width: 180, height: 44)

        let fitted = cell.preferredLayoutAttributesFitting(attributes)

        #expect(fitted.size == CGSize(width: 180, height: 47))
        #expect(cell.measurementCount == 1)
        #expect(cell.measuredView.measurementCount == 1)
    }

    @Test(arguments: [true, false])
    func supplementaryFittingUsesSubclassMeasurementAndCopiesAttributes(isHeader: Bool) {
        let kind = isHeader
            ? UICollectionView.elementKindSectionHeader
            : UICollectionView.elementKindSectionFooter
        let view = SizingOverrideSupplementaryView(frame: .zero)
        let attributes = UICollectionViewLayoutAttributes(
            forSupplementaryViewOfKind: kind,
            with: IndexPath(item: 0, section: 2)
        )
        attributes.frame = CGRect(x: 12, y: 34, width: 180, height: 44)
        attributes.zIndex = 3
        attributes.alpha = 0.7
        let original = attributes.copy() as! UICollectionViewLayoutAttributes

        let fitted = view.preferredLayoutAttributesFitting(attributes)

        #expect(fitted.size == CGSize(width: 180, height: 47))
        #expect(view.measurementCount == 1)
        #expect(view.measuredView.measurementCount == 1)
        #expect(fitted !== attributes)
        #expect(attributes.isEqual(original))
        #expect(fitted.center == original.center)
        #expect(fitted.indexPath == original.indexPath)
        #expect(fitted.representedElementKind == kind)
        #expect(fitted.zIndex == 3)
        #expect(fitted.alpha == 0.7)
    }
}

@MainActor
private final class SizingMeasurementView: UIView {
    var measurementCount = 0

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        measurementCount += 1
        return CGSize(width: 180, height: 37)
    }
}

@MainActor
private final class SizingOverrideCell: QuickLayoutCollectionViewCell {
    let measuredView = SizingMeasurementView()
    var measurementCount = 0

    @LayoutBuilder
    override var body: Layout { measuredView }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        measurementCount += 1
        let measured = super.sizeThatFits(size)
        return CGSize(width: measured.width, height: measured.height + 10)
    }
}

@MainActor
private final class SizingOverrideSupplementaryView: QuickLayoutCollectionReusableView {
    let measuredView = SizingMeasurementView()
    var measurementCount = 0

    @LayoutBuilder
    override var body: Layout { measuredView }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        measurementCount += 1
        let measured = super.sizeThatFits(size)
        return CGSize(width: measured.width, height: measured.height + 10)
    }
}
