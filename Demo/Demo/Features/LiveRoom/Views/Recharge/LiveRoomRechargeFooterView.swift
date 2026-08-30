//
//  LiveRoomRechargeFooterView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页底部状态与确认操作区域。
final class LiveRoomRechargeFooterView: QuickLayoutView {

    let statusLabel = UILabel()
    let rechargeButton = LiveRoomCapsuleTextButton(frame: .zero)

    var rechargeDidTap: (() -> Void)?
    var statusText: String? { statusLabel.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(spacing: 18) {
            statusLabel
                .frame(minHeight: 20)
            rechargeButton
                .resizable()
                .frame(height: 52)
        }
    }

    func setStatus(_ text: String?, color: UIColor) {
        statusLabel.text = text
        statusLabel.textColor = color
        setNeedsQuickLayout()
    }

    func configureRechargeButton(title: String) {
        rechargeButton.configure(
            title: title,
            font: .systemFont(ofSize: 17, weight: .semibold),
            foregroundColor: UIColor(
                red: 0.12,
                green: 0.10,
                blue: 0.04,
                alpha: 1
            ),
            backgroundColor: .systemYellow,
            contentInsets: EdgeInsets(
                top: 12,
                leading: 20,
                bottom: 12,
                trailing: 20
            )
        )
        setNeedsQuickLayout()
    }

    private func configureViews() {
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "liveRoom.recharge.status"

        rechargeButton.accessibilityIdentifier = "liveRoom.recharge.confirm"
        rechargeButton.action = { [weak self] in
            self?.rechargeDidTap?()
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargeFooterPreview() -> UIViewController {
    let view = LiveRoomRechargeFooterView(frame: .zero)
    view.setStatus("充值成功，已到账 13,600 星币", color: .systemGreen)
    view.configureRechargeButton(title: "充值 13,600 星币")
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(20)
        }
        .frame(width: 390, height: 180)
    }
}

#Preview("充值状态与确认区域") {
    makeLiveRoomRechargeFooterPreview()
}
#endif
