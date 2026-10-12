import UIKit
import QuickLayout

/// 由硬件或系统保留的区域。`frame` 已经包含 `margins`，不要重复扩大。
@available(iOS 27.1, *)
public struct ReservedRegion: Hashable, Sendable, Identifiable {
    /// 由所在窗口维持映射的区域稳定标识。
    public let id: ID
    /// 区域属于遮挡还是分隔类型。
    public let kind: Kind
    /// 包含避让边距的区域矩形；查询时可按方向规则镜像。
    public let frame: CGRect
    /// 系统提供的避让边距，已体现在 `frame` 中。
    public let margins: EdgeInsets
    /// 冻结快照时该区域是否处于活动状态。
    public let isActive: Bool

    /// 比较标识、类别、矩形、边距和活动状态。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.frame == rhs.frame && lhs.isActive == rhs.isActive && geometryInsetsEqual(lhs.margins, rhs.margins)
    }

    /// 将区域的全部相等性分量加入哈希器。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(kind); hasher.combine(isActive)
        hasher.combine(frame.origin.x); hasher.combine(frame.origin.y)
        hasher.combine(frame.width); hasher.combine(frame.height)
        hasher.combine(margins.top); hasher.combine(margins.leading)
        hasher.combine(margins.bottom); hasher.combine(margins.trailing)
    }

    /// 不透明标识；以系统区域的值标识映射，不使用其位置或数组下标。
    public struct ID: Hashable, Sendable {
        /// 系统区域标识在当前窗口内映射得到的 UUID。
        let value: UUID
    }
    /// 系统保留区域的类别。
    public enum Kind: Hashable, Sendable {
        /// `occlusion` 表示遮挡区域，`division` 表示分隔区域。
        case occlusion, division
    }
    /// 控制保留区域查询是否包含非活动区域的选项集合。
    public struct QueryOptions: OptionSet, Hashable, Sendable {
        /// 查询选项的原始位掩码。
        public let rawValue: Int
        /// 使用原始位掩码创建查询选项。
        ///
        /// - Parameter rawValue: 要保留的选项位。
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// 在查询结果中同时包含非活动区域；默认查询不包含此选项。
        public static let includeInactive = Self(rawValue: 1)
    }
}

/// 可在最低部署版本中保存的纯值存储，availability 仅限制公开查询入口。
struct GeometryReservedSnapshot: Equatable, Sendable {
    /// 系统区域在当前窗口内的稳定映射标识。
    let id: UUID
    /// 是否为分隔区域；`false` 表示遮挡区域。
    let division: Bool
    /// 归一化为观察者零原点局部空间的区域矩形。
    var frame: CGRect
    /// 系统的物理边距存储；查询时根据镜像规则交换水平分量。
    var margins: EdgeInsets
    /// 采样时系统报告的活动状态。
    let active: Bool

    /// 比较区域快照的身份、类别和所有几何分量。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.division == rhs.division && lhs.frame == rhs.frame && lhs.active == rhs.active && geometryInsetsEqual(lhs.margins, rhs.margins)
    }
}

/// 在单个窗口内为系统区域标识维护稳定的 UUID 映射。
@available(iOS 27.1, *)
@MainActor
final class GeometryRegionIdentifiers {
    /// 系统标识到公开不透明标识的窗口级映射。
    private var ids: [UIView.ReservedRegion.ID: UUID] = [:]
    /// 复用已有映射；首次遇到该系统区域时分配 UUID。
    func id(for value: UIView.ReservedRegion.ID) -> UUID {
        if let id = ids[value] { return id }
        let id = UUID()
        ids[value] = id
        return id
    }
}
