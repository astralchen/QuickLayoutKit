//
//  RechargeViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 管理充值档位选择和业务层确认后的余额。
@MainActor
final class RechargeViewModel {

    /// 充值确认前后用于驱动成功展示的余额记录。
    struct Transaction: Equatable {
        /// 本次充值确认前的金币余额。
        let previousBalance: Int
        /// 业务层确认入账后的金币余额。
        let updatedBalance: Int
        /// 本次充值实际入账的金币数，包含赠送部分。
        let creditedAmount: Int
    }

    /// 可供选择的充值档位列表。
    let packages: [RechargePackage]
    /// 当前操作所需的目标金币余额。
    let requiredBalance: Int
    /// 业务层确认的当前金币余额。
    private(set) var currentBalance: Int
    /// 当前选中档位的基础金币数。
    private(set) var selectedPackageAmount: Int

    /// 创建充值状态，并默认选择能覆盖余额缺口的第一个档位。
    ///
    /// 没有足够额度的档位时选择最后一项；空目录以零作为未选中的档位金额。
    init(
        currentBalance: Int,
        requiredBalance: Int,
        packages: [RechargePackage]? = nil
    ) {
        let resolvedPackages = packages ?? RechargePackage.catalog
        self.currentBalance = max(0, currentBalance)
        self.requiredBalance = max(0, requiredBalance)
        self.packages = resolvedPackages
        let deficit = max(0, requiredBalance - currentBalance)
        selectedPackageAmount = resolvedPackages.first(where: {
            ($0.creditedAmount ?? 0) >= deficit
        })?.amount ?? resolvedPackages.last?.amount ?? 0
    }

    /// 当前选中的充值档位；档位不存在时为 `nil`。
    var selectedPackage: RechargePackage? {
        packages.first { $0.amount == selectedPackageAmount }
    }

    /// 选择基础金币数匹配的充值档位。
    ///
    /// - Returns: 档位存在时为 `true`；否则保持原选择并返回 `false`。
    @discardableResult
    func selectPackage(amount: Int) -> Bool {
        guard packages.contains(where: { $0.amount == amount }) else {
            return false
        }
        selectedPackageAmount = amount
        return true
    }

    /// 通过业务回调确认入账，并在成功后提交页面余额。
    ///
    /// - Parameter balanceDidRecharge: 接收总入账金币数的同步回调；返回业务层最新余额，拒绝时返回 `nil`。
    /// - Returns: 用于成功展示的余额交易记录；档位无效、金额溢出或业务拒绝时为 `nil`。
    func performRecharge(
        balanceDidRecharge: (Int) -> Int?
    ) -> Transaction? {
        guard
            let package = selectedPackage,
            let creditedAmount = package.creditedAmount,
            let updatedBalance = balanceDidRecharge(creditedAmount)
        else { return nil }

        // 只有业务回调返回确认余额后才生成交易记录，成功动画不提前修改会话资金。
        let previousBalance = currentBalance
        currentBalance = max(0, updatedBalance)
        return Transaction(
            previousBalance: previousBalance,
            updatedBalance: currentBalance,
            creditedAmount: creditedAmount
        )
    }
}
