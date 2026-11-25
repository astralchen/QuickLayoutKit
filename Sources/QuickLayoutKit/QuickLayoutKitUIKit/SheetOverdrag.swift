import UIKit

struct SheetOverdrag {
    private static let resistance: CGFloat = 0.55
    private let limit: CGFloat
    let distance: CGFloat

    init(offset: CGFloat = 0) {
        // 快速回弹的呈现位置可能接近或越过拖动上限，为接续手势保留可逆的区间。
        limit = max(8, offset + 0.25)
        distance = offset > 0 ? limit * offset / ((limit - offset) * Self.resistance) : offset
    }

    func offset(for distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return distance }
        let resisted = distance * Self.resistance
        return limit * resisted / (limit + resisted)
    }

    @MainActor
    static func spring(velocity: CGFloat) -> UISpringTimingParameters {
        let stiffness: CGFloat = 1000 / 3
        let initialVelocity = velocity / 100
        let dampingRatio: CGFloat = abs(initialVelocity) > 5 ? 0.8 : 1
        return UISpringTimingParameters(mass: 1, stiffness: stiffness, damping: 2 * sqrt(stiffness) * dampingRatio,
                                        initialVelocity: CGVector(dx: initialVelocity, dy: initialVelocity))
    }
}
