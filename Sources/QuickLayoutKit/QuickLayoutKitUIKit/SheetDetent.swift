import UIKit

@MainActor
public protocol SheetPresentationControllerDelegate: UIAdaptivePresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: SheetPresentationController)
}

public extension SheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: SheetPresentationController) {}
}

/// Sheet 与非模态面板在解析档位高度时提供的容器环境。从 iOS 15 起可用。
@MainActor
public protocol SheetPresentationControllerDetentResolutionContext: NSObjectProtocol {
    /// 本次解析所用容器的特征集合。
    var containerTraitCollection: UITraitCollection { get }
    /// 当前容器允许的最大档位内容高度，以点为单位。
    var maximumDetentValue: CGFloat { get }
}

@MainActor
final class SheetDetentContext: NSObject, SheetPresentationControllerDetentResolutionContext, SheetMediumDetentGeometry {
    let availableRegion: CGRect
    let divisionRegions: [CGRect]
    let maximumDetentValue: CGFloat
    let containerTraitCollection: UITraitCollection
    let minimumMediumHeight: CGFloat

    init(availableRegion: CGRect, divisionRegions: [CGRect], maximumDetentValue: CGFloat,
         containerTraitCollection: UITraitCollection, minimumMediumHeight: CGFloat = 0) {
        self.minimumMediumHeight = minimumMediumHeight
        self.availableRegion = availableRegion
        self.divisionRegions = divisionRegions
        self.maximumDetentValue = maximumDetentValue
        self.containerTraitCollection = containerTraitCollection
    }
}

extension SheetPresentationController {
    /// Sheet 和非模态面板共用的高度档位。每次布局按各自的容器环境解析。
    @MainActor
    open class Detent: NSObject {
        public struct Identifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public init(_ value: String) { rawValue = value }
            public init(stringLiteral value: String) { rawValue = value }
            public static let medium: Self = "medium"
            public static let large: Self = "large"
        }

        private var storedIdentifier: Identifier = .large
        private var isMedium = false
        private var customHeight: ((any SheetPresentationControllerDetentResolutionContext) -> CGFloat?)?
        static let effectChanged = Notification.Name("QuickLayoutKit.SheetDetent.backgroundEffectChanged")
        private var effect: UIVisualEffect?

        public required override init() { super.init() }

        /// 档位的稳定标识。省略自定义标识时，每个实例自动获得一个唯一值。
        open var identifier: Identifier { storedIdentifier }

        /// 档位选中时显示在内容后方的效果。设为 nil 会恢复容器的默认背景。
        open var backgroundEffect: UIVisualEffect? {
            get { effect }
            set {
                guard effect !== newValue else { return }
                effect = newValue
                NotificationCenter.default.post(name: Self.effectChanged, object: self)
            }
        }

        open class func medium() -> Self {
            let detent = self.init()
            detent.storedIdentifier = .medium
            detent.isMedium = true
            return detent
        }

        open class func large() -> Self { self.init() }

        /// 创建自定义档位。解析器返回 nil 时，当前容器会停用此档位。
        public class func custom(identifier: Identifier? = nil,
                                 resolver: @escaping (any SheetPresentationControllerDetentResolutionContext) -> CGFloat?) -> Self {
            let detent = self.init()
            detent.storedIdentifier = identifier ?? .init(UUID().uuidString)
            detent.customHeight = resolver
            return detent
        }

        public func resolvedValue(in context: any SheetPresentationControllerDetentResolutionContext) -> CGFloat? {
            let maximum = context.maximumDetentValue
            if let customHeight {
                guard let height = customHeight(context), height.isFinite, height > 0 else { return nil }
                return min(height, maximum)
            }
            guard isMedium else { return maximum }
            return SheetRegionGeometry.resolvedMediumHeight(maximum: maximum,
                traits: context.containerTraitCollection, geometry: context as? any SheetMediumDetentGeometry)
        }
    }
}
