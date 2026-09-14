//
//  RechargePackage.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

struct RechargePackage: Equatable, Sendable {
    let amount: Int
    let bonus: Int

    var creditedAmount: Int? {
        let (value, overflow) = amount.addingReportingOverflow(bonus)
        return overflow ? nil : value
    }

    static let catalog = [
        RechargePackage(amount: 1_000, bonus: 0),
        RechargePackage(amount: 3_000, bonus: 100),
        RechargePackage(amount: 6_000, bonus: 300),
        RechargePackage(amount: 12_800, bonus: 800),
        RechargePackage(amount: 30_000, bonus: 2_400),
        RechargePackage(amount: 64_800, bonus: 6_800),
    ]
}
