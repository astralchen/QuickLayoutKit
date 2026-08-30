//
//  LiveRoomRechargeViewModel.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

@MainActor
final class LiveRoomRechargeViewModel {

    struct Transaction: Equatable {
        let previousBalance: Int
        let updatedBalance: Int
        let creditedAmount: Int
    }

    let packages: [LiveRoomRechargePackage]
    let requiredBalance: Int
    private(set) var currentBalance: Int
    private(set) var selectedPackageAmount: Int

    init(
        currentBalance: Int,
        requiredBalance: Int,
        packages: [LiveRoomRechargePackage]? = nil
    ) {
        let resolvedPackages = packages ?? LiveRoomRechargePackage.catalog
        self.currentBalance = max(0, currentBalance)
        self.requiredBalance = max(0, requiredBalance)
        self.packages = resolvedPackages
        let deficit = max(0, requiredBalance - currentBalance)
        selectedPackageAmount = resolvedPackages.first(where: {
            ($0.creditedAmount ?? 0) >= deficit
        })?.amount ?? resolvedPackages.last?.amount ?? 0
    }

    var selectedPackage: LiveRoomRechargePackage? {
        packages.first { $0.amount == selectedPackageAmount }
    }

    @discardableResult
    func selectPackage(amount: Int) -> Bool {
        guard packages.contains(where: { $0.amount == amount }) else {
            return false
        }
        selectedPackageAmount = amount
        return true
    }

    /// 业务回调确认入账后才提交页面余额，避免充值动画展示未落账的数据。
    func performRecharge(
        balanceDidRecharge: (Int) -> Int?
    ) -> Transaction? {
        guard
            let package = selectedPackage,
            let creditedAmount = package.creditedAmount,
            let updatedBalance = balanceDidRecharge(creditedAmount)
        else { return nil }

        let previousBalance = currentBalance
        currentBalance = max(0, updatedBalance)
        return Transaction(
            previousBalance: previousBalance,
            updatedBalance: currentBalance,
            creditedAmount: creditedAmount
        )
    }
}
