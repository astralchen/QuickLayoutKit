import UIKit

/// Demo 页面在历史插入、删除或视口变化时保存的阅读位置。
/// 页面负责将业务 ID 重新映射为 indexPath；本值只记录公开布局几何。
struct CollectionReadingAnchor: Equatable {
    let indexPath: IndexPath
    let offsetFromViewportTop: CGFloat
    let offsetFromViewportLeading: CGFloat
}

extension UICollectionView {
    func captureReadingAnchor() -> CollectionReadingAnchor? {
        layoutIfNeeded()
        let viewport = bounds.inset(by: adjustedContentInset)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let attributes = indexPathsForVisibleItems
            .compactMap { layoutAttributesForItem(at: $0) }
            .filter { $0.frame.intersects(viewport) }
            .min { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 0.5 {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return rtl ? lhs.frame.maxX > rhs.frame.maxX : lhs.frame.minX < rhs.frame.minX
            }
        guard let attributes else { return nil }
        return CollectionReadingAnchor(
            indexPath: attributes.indexPath,
            offsetFromViewportTop: attributes.frame.minY - viewport.minY,
            offsetFromViewportLeading: rtl
                ? viewport.maxX - attributes.frame.maxX
                : attributes.frame.minX - viewport.minX
        )
    }

    @discardableResult
    func restoreReadingAnchor(_ anchor: CollectionReadingAnchor) -> Bool {
        let index = anchor.indexPath
        guard index.section >= 0, index.section < numberOfSections,
              index.item >= 0, index.item < numberOfItems(inSection: index.section) else { return false }
        layoutIfNeeded()
        guard let attributes = layoutAttributesForItem(at: index) else { return false }
        let inset = adjustedContentInset
        let x = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? attributes.frame.maxX + anchor.offsetFromViewportLeading - bounds.width + inset.right
            : attributes.frame.minX - anchor.offsetFromViewportLeading - inset.left
        let y = attributes.frame.minY - anchor.offsetFromViewportTop - inset.top
        setContentOffset(CGPoint(
            x: min(max(x, -inset.left), max(-inset.left, contentSize.width - bounds.width + inset.right)),
            y: min(max(y, -inset.top), max(-inset.top, contentSize.height - bounds.height + inset.bottom))
        ), animated: false)
        return true
    }
}
