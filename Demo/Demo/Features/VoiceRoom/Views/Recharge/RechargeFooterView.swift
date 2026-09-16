//
//  RechargeFooterView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页底部状态与确认操作区域。
final class RechargeFooterView: QuickLayoutView {

    /// 显示当前操作结果或提示的标签。
    let statusLabel = UILabel()
    /// 提交当前充值档位的按钮。
    let rechargeButton = CapsuleTextButton(frame: .zero)

    /// 用户点击充值按钮时调用的回调。
    var rechargeDidTap: (() -> Void)?
    /// 当前状态标签的显示文案。
    var statusText: String? { statusLabel.text }

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
        VStack(spacing: 18) {
            statusLabel
                .frame(minHeight: 20)
            rechargeButton
                .resizable()
                .frame(height: 52)
        }
    }

    /// 设置状态文案和颜色，并刷新内容布局。
    func setStatus(_ text: String?, color: UIColor) {
        statusLabel.text = text
        statusLabel.textColor = color
        setNeedsQuickLayout()
    }

    /// 设置充值按钮的显示标题和统一样式。
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

    /// 配置子视图的样式、交互和辅助功能属性。
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
/// 创建展示充值底部操作区的预览控制器。
@MainActor
private func makeRechargeFooterPreview() -> UIViewController {
    let view = RechargeFooterView(frame: .zero)
    view.setStatus("充值成功，已到账 13,600 星币", color: .systemGreen)
    view.configureRechargeButton(title: "充值 13,600 星币")
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .padding(20)
        }
        .frame(width: 390, height: 180)
    }
}

@available(iOS 17.0, *)
#Preview("充值状态与确认区域") {
    makeRechargeFooterPreview()
}
#endif
