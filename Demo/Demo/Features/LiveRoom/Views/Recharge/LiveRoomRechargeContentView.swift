//
//  LiveRoomRechargeContentView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页滚动内容，按余额、档位和底部操作三个业务层级组装。
final class LiveRoomRechargeContentView: QuickLayoutView {

    let balanceCardView = LiveRoomRechargeBalanceCardView(frame: .zero)
    let packageSectionView = LiveRoomRechargePackageSectionView(frame: .zero)
    let footerView = LiveRoomRechargeFooterView(frame: .zero)

    override var body: Layout {
        VStack(spacing: 18) {
            balanceCardView
                .resizable(axis: .horizontal)
            packageSectionView
                .resizable(axis: .horizontal)
            footerView
                .resizable(axis: .horizontal)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 28)
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargeContentPreview() -> UIViewController {
    let view = LiveRoomRechargeContentView(frame: .zero)
    let packages = LiveRoomRechargePackage.catalog
    let packageTitle = "选择充值档位"
    view.balanceCardView.configure(
        caption: "当前余额",
        balance: "12,048 星币",
        requirement: "本次赠送需余额 88,888"
    )
    view.packageSectionView.configure(
        title: packageTitle,
        packages: packages,
        selectedAmount: 12_800
    )
    view.packageSectionView.packageDidSelect = { [weak view] package in
        guard let view else { return }
        view.packageSectionView.configure(
            title: packageTitle,
            packages: packages,
            selectedAmount: package.amount
        )
        view.footerView.configureRechargeButton(
            title: DemoLocalization.text(
                "liveRoom.recharge.confirm",
                package.creditedAmount ?? 0
            )
        )
    }
    view.footerView.setStatus(nil, color: UIColor.white.withAlphaComponent(0.68))
    view.footerView.configureRechargeButton(title: "充值 13,600 星币")
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
        .frame(width: 390, height: 650)
    }
}

#Preview("充值滚动内容") {
    makeLiveRoomRechargeContentPreview()
}
#endif
