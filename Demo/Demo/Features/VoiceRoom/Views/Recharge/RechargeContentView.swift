//
//  RechargeContentView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页滚动内容，按余额、档位和底部操作三个业务层级组装。
final class RechargeContentView: QuickLayoutView {

    /// 显示当前金币余额和目标余额说明的卡片。
    let balanceCardView = RechargeBalanceCardView(frame: .zero)
    /// 显示充值档位网格的内容区域。
    let packageSectionView = RechargePackageSectionView(frame: .zero)
    /// 显示充值状态和确认按钮的底部区域。
    let footerView = RechargeFooterView(frame: .zero)

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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
/// 创建展示充值内容区域的预览控制器。
@MainActor
private func makeRechargeContentPreview() -> UIViewController {
    let view = RechargeContentView(frame: .zero)
    let packages = RechargePackage.catalog
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
            title: Localization.text(
                "liveRoom.recharge.confirm",
                package.creditedAmount ?? 0
            )
        )
    }
    view.footerView.setStatus(nil, color: UIColor.white.withAlphaComponent(0.68))
    view.footerView.configureRechargeButton(title: "充值 13,600 星币")
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
    }
}

@available(iOS 17.0, *)
#Preview("充值滚动内容") {
    makeRechargeContentPreview()
}
#endif
