import UIKit

/// 非模态面板的布局环境。所有矩形均使用宿主视图的坐标系。
@MainActor
public final class AdaptivePanelContext: NSObject, SheetPresentationControllerDetentResolutionContext, SheetMediumDetentGeometry {
    public let containerBounds: CGRect
    public let availableRegion: CGRect
    /// 系统分隔带（包含交互建议边距及未激活分隔），可用于自定义档位策略。
    /// 面板横向位置只受活动分隔影响；medium 在展开纵屏时仍参考物理分隔位置。
    public let divisionRegions: [CGRect]
    public let containerTraitCollection: UITraitCollection
    /// 本轮宿主或窗口提供的安全区；页面外框策略作用后的区域见 availableRegion。
    public var safeAreaInsets: UIEdgeInsets
    /// 内容最大高度；贴底时不包含底部安全区。
    public let maximumDetentValue: CGFloat
    let minimumMediumHeight: CGFloat
    /// 系统提供的铰链角度，单位为弧度；没有铰链信息时为 nil。
    public let hingeAngle: CGFloat?
    public let hingeState: HingeState

    init(containerBounds: CGRect, availableRegion: CGRect, divisionRegions: [CGRect],
         containerTraitCollection: UITraitCollection, maximumDetentValue: CGFloat,
         hingeAngle: CGFloat?, hingeState: HingeState, safeAreaInsets: UIEdgeInsets = .zero,
         minimumMediumHeight: CGFloat = 0) {
        self.containerBounds = containerBounds
        self.availableRegion = availableRegion
        self.divisionRegions = divisionRegions
        self.containerTraitCollection = containerTraitCollection
        self.maximumDetentValue = maximumDetentValue
        self.hingeAngle = hingeAngle
        self.hingeState = hingeState
        self.safeAreaInsets = safeAreaInsets
        self.minimumMediumHeight = minimumMediumHeight
    }

    public enum HingeState: Sendable {
        case unavailable, unknown, closed, partiallyOpen, fullyOpen
    }
}

/// 非模态面板与 Sheet 共用的档位类型。
public typealias AdaptivePanelDetent = SheetPresentationController.Detent

public extension SheetPresentationController.Detent {
    /// 使用面板的铰链角度、安全区或分隔区域计算高度。其他容器会停用此档位。
    @_disfavoredOverload
    static func custom(identifier: Identifier? = nil,
                       resolver: @escaping (AdaptivePanelContext) -> CGFloat?) -> Self {
        custom(identifier: identifier) { (context: any SheetPresentationControllerDetentResolutionContext) in
            guard let panel = context as? AdaptivePanelContext else { return nil }
            return resolver(panel)
        }
    }
}

extension AdaptivePanelContext {
    static func regions(in bounds: CGRect, divisions: [CGRect]) -> [CGRect] {
        SheetRegionGeometry.regions(in: bounds, divisions: divisions)
    }
}
