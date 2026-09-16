//
//  VoiceRoomTheme.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

/// 语音房麦位和礼物共用的主题调色板。
@MainActor
enum VoiceRoomTheme {
    /// 麦位头像和装饰使用的主题颜色列表。
    static let seatColors: [UIColor] = [
        .systemPink, .systemTeal, .systemPurple, .systemOrange,
        .systemIndigo, .systemGreen, .systemBlue, .systemYellow, .systemPink,
    ]

    /// 礼物图标和特效使用的主题颜色列表。
    static let giftColors: [UIColor] = [
        .systemPink, .systemYellow, .systemTeal, .systemPurple,
        .systemIndigo, .systemOrange,
    ]

    /// 返回指定索引对应的麦位颜色；超出范围的索引限制到调色板首项或末项。
    static func seatColor(at index: Int) -> UIColor {
        seatColors[min(max(index, 0), seatColors.count - 1)]
    }

    /// 返回指定索引对应的礼物颜色；超出范围的索引限制到调色板首项或末项。
    static func giftColor(at index: Int) -> UIColor {
        giftColors[min(max(index, 0), giftColors.count - 1)]
    }
}
