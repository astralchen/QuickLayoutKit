//
//  RechargePackageButton.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示充值金币数、赠送说明和选中状态的档位按钮。
final class RechargePackageButton: QuickLayoutButton {

    /// 显示充值档位基础金币数的标签。
    private let amountLabel = UILabel()
    /// 显示档位赠送金币或标准档位说明的标签。
    private let detailLabel = UILabel()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 应用充值档位数据，并更新选中边框与辅助功能状态。
    func configure(
        package: RechargePackage,
        isSelected: Bool
    ) {
        amountLabel.text = Localization.text(
            "liveRoom.recharge.package.amount",
            package.amount
        )
        detailLabel.text = package.bonus > 0
            ? Localization.text(
                "liveRoom.recharge.package.bonus",
                package.bonus
            )
            : Localization.text("liveRoom.recharge.package.standard")
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
            ? Localization.text("liveRoom.recharge.package.selected")
            : nil
        setNeedsQuickLayout()
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.97, y: 0.97)
            : .identity
        alpha = state.isPressed ? 0.84 : (state.isEnabled ? 1 : 0.56)
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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
/// 创建展示充值档位按钮的预览控制器。
@MainActor
private func makeRechargePackageButtonPreview() -> UIViewController {
    let button = RechargePackageButton(frame: .zero)
    button.configure(
        package: RechargePackage.catalog[4],
        isSelected: true
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            button
                .resizable()
                .frame(width: 176, height: 88)
        }
    }
}

@available(iOS 17.0, *)
#Preview("充值档位按钮") {
    makeRechargePackageButtonPreview()
}
#endif
