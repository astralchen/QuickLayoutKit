//
//  RechargePackage.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 充值档位的基础金币数与赠送金币数。
struct RechargePackage: Equatable, Sendable {
    /// 用于标识充值档位的基础金币数。
    let amount: Int
    /// 此档位额外赠送的金币数。
    let bonus: Int

    /// 基础金币与赠送金币之和；整数溢出时为 `nil`。
    var creditedAmount: Int? {
        let (value, overflow) = amount.addingReportingOverflow(bonus)
        return overflow ? nil : value
    }

    /// 按基础金币数升序排列的内置充值档位。
    static let catalog = [
        RechargePackage(amount: 1_000, bonus: 0),
        RechargePackage(amount: 3_000, bonus: 100),
        RechargePackage(amount: 6_000, bonus: 300),
        RechargePackage(amount: 12_800, bonus: 800),
        RechargePackage(amount: 30_000, bonus: 2_400),
        RechargePackage(amount: 64_800, bonus: 6_800),
    ]
}
