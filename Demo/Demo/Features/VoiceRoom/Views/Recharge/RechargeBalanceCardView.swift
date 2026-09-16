//
//  RechargeBalanceCardView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页余额卡片。
///
/// 卡片自行拥有标题、余额和补足提示，并保持完整的垂直自然尺寸，避免外层空间
/// 不足时把文字裁切成非完整行。
final class RechargeBalanceCardView: QuickLayoutView {

    /// 组件内容后方的背景视图。
    let backgroundView = UIView()
    /// 显示余额说明标题的标签。
    let captionLabel = UILabel()
    /// 显示当前字段值的标签。
    let valueLabel = UILabel()
    /// 显示目标余额或充值需求说明的标签。
    let requirementLabel = UILabel()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        VStack(alignment: .leading, spacing: 9) {
            captionLabel
            valueLabel
            requirementLabel
                .resizable(axis: .horizontal)
        }
        .padding(18)
        .background { backgroundView }
        .fixedSize(axis: .vertical)
    }

    /// 更新余额标题、余额值和当前充值需求说明。
    func configure(
        caption: String,
        balance: String,
        requirement: String
    ) {
        captionLabel.text = caption
        valueLabel.text = balance
        requirementLabel.text = requirement
        setNeedsQuickLayout()
    }

    /// 更新余额数字文案并使相关布局重新测量。
    func updateBalance(_ text: String) {
        valueLabel.text = text
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        accessibilityIdentifier = "liveRoom.recharge.balanceCard"

        backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        backgroundView.layer.cornerRadius = 22
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.borderWidth = 1
        backgroundView.layer.borderColor = UIColor.white
            .withAlphaComponent(0.14).cgColor

        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.70)
        captionLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: 36,
            weight: .bold
        )
        valueLabel.textColor = .white
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.70
        valueLabel.accessibilityIdentifier = "liveRoom.recharge.balance"

        requirementLabel.font = .preferredFont(forTextStyle: .footnote)
        requirementLabel.textColor = .systemYellow
        requirementLabel.adjustsFontForContentSizeCategory = true
        requirementLabel.numberOfLines = 0
    }
}

#if DEBUG
/// 创建展示充值余额卡片的预览控制器。
@MainActor
private func makeRechargeBalanceCardPreview() -> UIViewController {
    let view = RechargeBalanceCardView(frame: .zero)
    view.configure(
        caption: "当前余额",
        balance: "12,048 星币",
        requirement: "本次赠送需余额 88,888"
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(20)
        }
    }
}

@available(iOS 17.0, *)
#Preview("充值余额卡片") {
    makeRechargeBalanceCardPreview()
}
#endif
