import UIKit

/// Device Hub 的摆放方式并非 UIKit 枚举。半折叠时用窗口分隔带的方向描述可见姿态。
enum ArrangementDevicePose: String {
    case closed, openPortrait, openLandscape, open, book, tabletop, partial, unknown

    var symbol: String {
        switch self {
        case .closed: "iphone"
        case .openPortrait: "rectangle.portrait"
        case .openLandscape, .open: "rectangle"
        case .book: "book"
        case .tabletop: "laptopcomputer"
        case .partial, .unknown: "angle"
        }
    }

    @MainActor func resolved(in window: UIWindow?) -> Self {
        #if compiler(>=6.4)
        guard #available(iOS 27.1, *), let window else { return self }
        switch self {
        case .open:
            let orientation = window.windowScene?.effectiveGeometry.interfaceOrientation
            if orientation?.isLandscape == true { return .openLandscape }
            if orientation?.isPortrait == true { return .openPortrait }
        case .partial:
            guard let fold = window.reservedRegions(kind: .division).first?.frame,
                  !fold.isEmpty, fold.width != fold.height else { return .partial }
            return fold.height > fold.width ? .book : .tabletop
        default: break
        }
        #endif
        return self
    }
}
