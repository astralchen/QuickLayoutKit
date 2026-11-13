import UIKit

/// 非模态面板的布局环境。所有矩形均使用宿主视图的坐标系。
@MainActor
public struct AdaptivePanelContext {
    public let containerBounds: CGRect
    public let availableRegion: CGRect
    /// 系统分隔带（包含交互建议边距及未激活分隔），可用于自定义档位策略。
    /// 面板横向位置只受活动分隔影响；medium 在展开纵屏时仍参考物理分隔位置。
    public let divisionRegions: [CGRect]
    public let containerTraitCollection: UITraitCollection
    /// 本轮宿主或窗口提供的安全区；页面外框策略作用后的区域见 availableRegion。
    public var safeAreaInsets: UIEdgeInsets = .zero
    /// 内容最大高度；贴底时不包含底部安全区。
    public let maximumDetentValue: CGFloat
    /// 系统提供的铰链角度，单位为弧度；没有铰链信息时为 nil。
    public let hingeAngle: CGFloat?
    public let hingeState: HingeState

    public enum HingeState: Sendable {
        case unavailable, unknown, closed, partiallyOpen, fullyOpen
    }
}

/// 自定义解析器返回 nil 时，该档位在当前环境中停用。
@MainActor
public struct AdaptivePanelDetent {
    public struct Identifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { rawValue = value }
        public static let medium: Self = "medium"
        public static let large: Self = "large"
    }

    public let identifier: Identifier
    private let resolver: (AdaptivePanelContext) -> CGFloat?

    public static func medium() -> Self {
        .custom(identifier: .medium) { context in
            guard context.containerTraitCollection.verticalSizeClass != .compact else { return nil }
            // iOS 27 实测系统 medium 为最大内容高度的 56%，与旧版约一半的规则不同。
            // 这是组件的相对高度策略；不依赖设备型号，也不读取 UIKit 私有解析上下文。
            if #available(iOS 27.0, *) {
                var height = context.maximumDetentValue * 0.56
                // 桌面姿态的 medium 落在横向分隔带下方；large 与自定义档位不受此限制。
                // 这里保留系统为交互内容建议的 margins，避免内容贴住铰链。
                let region = context.availableRegion
                for division in context.divisionRegions where division.width > division.height
                    && division.minX <= region.minX + 1 && division.maxX >= region.maxX - 1
                    && division.maxY > region.minY && division.maxY < region.maxY {
                    height = min(height, region.maxY - division.maxY)
                }
                return height
            }
            return context.maximumDetentValue * 0.5
        }
    }

    public static func large() -> Self {
        .custom(identifier: .large) { $0.maximumDetentValue }
    }

    public static func custom(identifier: Identifier, resolver: @escaping (AdaptivePanelContext) -> CGFloat?) -> Self {
        Self(identifier: identifier, resolver: resolver)
    }

    public func resolvedValue(in context: AdaptivePanelContext) -> CGFloat? {
        guard let value = resolver(context), value.isFinite, value > 0 else { return nil }
        return min(value, context.maximumDetentValue)
    }
}

extension AdaptivePanelContext {
    /// 仅使用贯穿宿主可见区域的分隔带切分空间，坐标统一为宿主坐标。
    static func regions(in bounds: CGRect, divisions: [CGRect]) -> [CGRect] {
        var regions = [bounds]
        for division in divisions {
            regions = regions.flatMap { region -> [CGRect] in
                let intersection = region.intersection(division)
                guard !intersection.isNull, intersection.width >= 0, intersection.height >= 0,
                      intersection.width > 0 || intersection.height > 0 else { return [region] }
                if division.height > division.width,
                   division.minY <= region.minY + 1, division.maxY >= region.maxY - 1 {
                    return [CGRect(x: region.minX, y: region.minY, width: intersection.minX - region.minX, height: region.height),
                            CGRect(x: intersection.maxX, y: region.minY, width: region.maxX - intersection.maxX, height: region.height)]
                        .filter { $0.width > 0 }
                }
                if division.width > division.height,
                   division.minX <= region.minX + 1, division.maxX >= region.maxX - 1 {
                    return [CGRect(x: region.minX, y: region.minY, width: region.width, height: intersection.minY - region.minY),
                            CGRect(x: region.minX, y: intersection.maxY, width: region.width, height: region.maxY - intersection.maxY)]
                        .filter { $0.height > 0 }
                }
                return [region]
            }
        }
        return regions
    }
}
