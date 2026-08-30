//
//  LiveRoomRechargePackage.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

struct LiveRoomRechargePackage: Equatable, Sendable {
    let amount: Int
    let bonus: Int

    var creditedAmount: Int? {
        let (value, overflow) = amount.addingReportingOverflow(bonus)
        return overflow ? nil : value
    }

    static let catalog = [
        LiveRoomRechargePackage(amount: 1_000, bonus: 0),
        LiveRoomRechargePackage(amount: 3_000, bonus: 100),
        LiveRoomRechargePackage(amount: 6_000, bonus: 300),
        LiveRoomRechargePackage(amount: 12_800, bonus: 800),
        LiveRoomRechargePackage(amount: 30_000, bonus: 2_400),
        LiveRoomRechargePackage(amount: 64_800, bonus: 6_800),
    ]
}
