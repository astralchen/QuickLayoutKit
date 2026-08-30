//
//  LiveRoomRechargeBalanceCardView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页余额卡片。
///
/// 卡片自行拥有标题、余额和补足提示，并保持完整的垂直自然尺寸，避免外层空间
/// 不足时把文字裁切成非完整行。
final class LiveRoomRechargeBalanceCardView: QuickLayoutView {

    let backgroundView = UIView()
    let captionLabel = UILabel()
    let valueLabel = UILabel()
    let requirementLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

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

    func updateBalance(_ text: String) {
        valueLabel.text = text
        setNeedsQuickLayout()
    }

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
@MainActor
private func makeLiveRoomRechargeBalanceCardPreview() -> UIViewController {
    let view = LiveRoomRechargeBalanceCardView(frame: .zero)
    view.configure(
        caption: "当前余额",
        balance: "12,048 星币",
        requirement: "本次赠送需余额 88,888"
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(20)
        }
        .frame(width: 390, height: 210)
    }
}

#Preview("充值余额卡片") {
    makeLiveRoomRechargeBalanceCardPreview()
}
#endif
