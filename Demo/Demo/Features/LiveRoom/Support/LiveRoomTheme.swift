//
//  LiveRoomTheme.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import UIKit

@MainActor
enum LiveRoomTheme {
    static let seatColors: [UIColor] = [
        .systemPink, .systemTeal, .systemPurple, .systemOrange,
        .systemIndigo, .systemGreen, .systemBlue, .systemYellow, .systemPink,
    ]

    static let giftColors: [UIColor] = [
        .systemPink, .systemYellow, .systemTeal, .systemPurple,
        .systemIndigo, .systemOrange,
    ]

    static func seatColor(at index: Int) -> UIColor {
        seatColors[min(max(index, 0), seatColors.count - 1)]
    }

    static func giftColor(at index: Int) -> UIColor {
        giftColors[min(max(index, 0), giftColors.count - 1)]
    }
}
