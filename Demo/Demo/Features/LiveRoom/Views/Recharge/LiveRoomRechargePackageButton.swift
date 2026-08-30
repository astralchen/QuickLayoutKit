//
//  LiveRoomRechargePackageButton.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomRechargePackageButton: QuickLayoutButton {

    private let amountLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var body: Layout {
        VStack(spacing: 4) {
            amountLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity)
            detailLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 10)
    }

    func configure(
        package: LiveRoomRechargePackage,
        isSelected: Bool
    ) {
        amountLabel.text = DemoLocalization.text(
            "liveRoom.recharge.package.amount",
            package.amount
        )
        detailLabel.text = package.bonus > 0
            ? DemoLocalization.text(
                "liveRoom.recharge.package.bonus",
                package.bonus
            )
            : DemoLocalization.text("liveRoom.recharge.package.standard")
        amountLabel.textColor = isSelected ? .systemYellow : .white
        detailLabel.textColor = isSelected
            ? UIColor.systemYellow.withAlphaComponent(0.86)
            : UIColor.white.withAlphaComponent(0.68)
        backgroundColor = isSelected
            ? UIColor.systemYellow.withAlphaComponent(0.18)
            : UIColor.white.withAlphaComponent(0.07)
        layer.borderColor = (
            isSelected
                ? UIColor.systemYellow
                : UIColor.white.withAlphaComponent(0.14)
        ).cgColor
        layer.borderWidth = isSelected ? 2 : 1
        self.isSelected = isSelected
        accessibilityValue = isSelected
            ? DemoLocalization.text("liveRoom.recharge.package.selected")
            : nil
        setNeedsQuickLayout()
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.97, y: 0.97)
            : .identity
        alpha = state.isPressed ? 0.84 : (state.isEnabled ? 1 : 0.56)
    }

    private func configureViews() {
        clipsToBounds = true
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        amountLabel.font = .monospacedDigitSystemFont(
            ofSize: 16,
            weight: .semibold
        )
        detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
        [amountLabel, detailLabel].forEach {
            $0.textAlignment = .center
            $0.numberOfLines = 1
            $0.adjustsFontSizeToFitWidth = true
            $0.minimumScaleFactor = 0.68
            $0.lineBreakMode = .byClipping
            $0.isUserInteractionEnabled = false
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargePackageButtonPreview() -> UIViewController {
    let button = LiveRoomRechargePackageButton(frame: .zero)
    button.configure(
        package: LiveRoomRechargePackage.catalog[4],
        isSelected: true
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            button
                .resizable()
                .frame(width: 176, height: 88)
        }
    }
}

#Preview("充值档位按钮") {
    makeLiveRoomRechargePackageButtonPreview()
}
#endif
