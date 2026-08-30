import QuickLayout

/// 与 SwiftUI `UnitPoint` 对齐的常用单位坐标预设。
public extension UnitPoint {
    static var zero: UnitPoint { UnitPoint(x: 0, y: 0) }
    static var topLeading: UnitPoint { UnitPoint(x: 0, y: 0) }
    static var top: UnitPoint { UnitPoint(x: 0.5, y: 0) }
    static var topTrailing: UnitPoint { UnitPoint(x: 1, y: 0) }
    static var leading: UnitPoint { UnitPoint(x: 0, y: 0.5) }
    static var center: UnitPoint { UnitPoint(x: 0.5, y: 0.5) }
    static var trailing: UnitPoint { UnitPoint(x: 1, y: 0.5) }
    static var bottomLeading: UnitPoint { UnitPoint(x: 0, y: 1) }
    static var bottom: UnitPoint { UnitPoint(x: 0.5, y: 1) }
    static var bottomTrailing: UnitPoint { UnitPoint(x: 1, y: 1) }
}
