import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 每个轴可独立设置绝对尺寸、比例尺寸和理想内容尺寸。
struct ArrangementRange: Equatable, Sendable {
    var min: CGFloat?
    var ideal: CGFloat?
    var max: CGFloat?
}

struct ArrangementRanges: Equatable, Sendable {
    var horizontal: ArrangementRange
    var vertical: ArrangementRange

    subscript(_ axis: Axis) -> ArrangementRange { axis == .horizontal ? horizontal : vertical }
}

enum SizeKey: LayoutValueKey {
    static let defaultValue = ArrangementRanges(horizontal: .init(), vertical: .init())
}
enum RatioKey: LayoutValueKey {
    static let defaultValue = ArrangementRanges(horizontal: .init(), vertical: .init())
}
enum FixedKey: LayoutValueKey {
    static let defaultValue: AxisSet = []
}

public extension Element {
    /// 指定主、辅内容之一在两个轴上的首选比例。
    func splitArrangementLayoutRatio(_ ratio: CGFloat?) -> Layout {
        splitArrangementLayoutRatio(idealHorizontal: ratio, idealVertical: ratio)
    }

    /// 分别指定水平与垂直排列使用的比例范围。
    func splitArrangementLayoutRatio(
        minHorizontal: CGFloat? = nil, idealHorizontal: CGFloat? = nil, maxHorizontal: CGFloat? = nil,
        minVertical: CGFloat? = nil, idealVertical: CGFloat? = nil, maxVertical: CGFloat? = nil
    ) -> Layout {
        layoutValue(key: RatioKey.self, value: ArrangementRanges(
            horizontal: .init(min: minHorizontal, ideal: idealHorizontal, max: maxHorizontal),
            vertical: .init(min: minVertical, ideal: idealVertical, max: maxVertical)
        ))
    }

    /// 指定当前内容在分割排列中的绝对尺寸范围，单位为点。
    func splitArrangementLayoutSize(
        minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil
    ) -> Layout {
        layoutValue(key: SizeKey.self, value: ArrangementRanges(
            horizontal: .init(min: minWidth, ideal: idealWidth, max: maxWidth),
            vertical: .init(min: minHeight, ideal: idealHeight, max: maxHeight)
        ))
    }

    /// 指示布局优先采用内容本身的理想尺寸。
    func splitArrangementFixedLayoutSize(horizontal: Bool = true, vertical: Bool = true) -> Layout {
        var axes: AxisSet = []
        if horizontal { axes.insert(.horizontal) }
        if vertical { axes.insert(.vertical) }
        return layoutValue(key: FixedKey.self, value: axes)
    }
}

extension Element {
    func arrangementRange(axis: Axis, available: CGFloat, proposal: CGSize) -> ArrangementRange {
        let absolute = _layoutValue(for: SizeKey.self)[axis]
        let ratio = _layoutValue(for: RatioKey.self)[axis]
        func points(_ fraction: CGFloat?) -> CGFloat? {
            fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) * available : nil }
        }
        func length(_ value: CGFloat?) -> CGFloat? {
            value.flatMap { $0.isFinite ? max(0, $0) : nil }
        }
        let lower = max(length(absolute.min) ?? 0, points(ratio.min) ?? 0)
        let upper = min(length(absolute.max) ?? available, points(ratio.max) ?? available)
        var ideal = length(absolute.ideal) ?? points(ratio.ideal)
        if _layoutValue(for: FixedKey.self).contains(axis == .horizontal ? .horizontal : .vertical) {
            let size = axis == .horizontal ? CGSize(width: .infinity, height: proposal.height)
                : CGSize(width: proposal.width, height: .infinity)
            let measured = quick_layoutThatFits(size).size
            ideal = length(axis == .horizontal ? measured.width : measured.height) ?? ideal
        }
        return ArrangementRange(min: lower, ideal: ideal, max: max(lower, upper))
    }
}
