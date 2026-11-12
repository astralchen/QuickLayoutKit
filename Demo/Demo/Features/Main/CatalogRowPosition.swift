import UIKit

/// 目录行相对于可读视口的纵向位置。不同语言的换行数可能不同。
struct CatalogRowPosition<ID: Equatable> {
    let id: ID
    let offset: CGFloat
    let height: CGFloat

    func offset(for newHeight: CGFloat) -> CGFloat {
        guard newHeight > 0, offset <= -newHeight else { return offset }
        // 原偏移会让整行消失时，保留原先露出的行尾，同时使首行保持部分或全部可见。
        let visibleTail = min(newHeight, max(1, height + offset))
        return visibleTail - newHeight
    }

    func isSameReadingPosition(as other: Self) -> Bool {
        id == other.id && abs(offset - other.offset) <= 0.5
    }
}
