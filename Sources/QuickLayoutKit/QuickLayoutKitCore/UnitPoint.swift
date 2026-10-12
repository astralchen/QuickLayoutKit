import QuickLayout

/// 与 SwiftUI `UnitPoint` 对齐的常用单位坐标预设。
public extension UnitPoint {
    /// 原点的单位坐标 `(0, 0)`；方向解释由使用方决定。
    static var zero: UnitPoint { UnitPoint(x: 0, y: 0) }
    /// 顶部前缘的单位坐标 `(0, 0)`；方向解释由使用方决定。
    static var topLeading: UnitPoint { UnitPoint(x: 0, y: 0) }
    /// 顶部中点的单位坐标 `(0.5, 0)`；方向解释由使用方决定。
    static var top: UnitPoint { UnitPoint(x: 0.5, y: 0) }
    /// 顶部后缘的单位坐标 `(1, 0)`；方向解释由使用方决定。
    static var topTrailing: UnitPoint { UnitPoint(x: 1, y: 0) }
    /// 前缘中点的单位坐标 `(0, 0.5)`；方向解释由使用方决定。
    static var leading: UnitPoint { UnitPoint(x: 0, y: 0.5) }
    /// 中心的单位坐标 `(0.5, 0.5)`；方向解释由使用方决定。
    static var center: UnitPoint { UnitPoint(x: 0.5, y: 0.5) }
    /// 后缘中点的单位坐标 `(1, 0.5)`；方向解释由使用方决定。
    static var trailing: UnitPoint { UnitPoint(x: 1, y: 0.5) }
    /// 底部前缘的单位坐标 `(0, 1)`；方向解释由使用方决定。
    static var bottomLeading: UnitPoint { UnitPoint(x: 0, y: 1) }
    /// 底部中点的单位坐标 `(0.5, 1)`；方向解释由使用方决定。
    static var bottom: UnitPoint { UnitPoint(x: 0.5, y: 1) }
    /// 底部后缘的单位坐标 `(1, 1)`；方向解释由使用方决定。
    static var bottomTrailing: UnitPoint { UnitPoint(x: 1, y: 1) }
}
