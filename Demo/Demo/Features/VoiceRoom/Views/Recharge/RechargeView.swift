//
//  RechargeView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页根视图。
///
/// 根视图只组装背景、滚动内容和成功浮层，并通过语义方法向控制器隐藏具体的
/// UILabel、按钮及卡片层级。
final class RechargeView: QuickLayoutView {

    /// 组件内容后方的背景视图。
    let backgroundView = QuickLayoutLinearGradientView(
        stops: [
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.13, green: 0.06, blue: 0.28, alpha: 1),
                location: 0
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.08, green: 0.10, blue: 0.27, alpha: 1),
                location: 0.56
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.03, green: 0.19, blue: 0.38, alpha: 1),
                location: 1
            ),
        ],
        startPoint: UnitPoint(x: 0.10, y: 0),
        endPoint: UnitPoint(x: 0.92, y: 1)
    )
    /// 承载内容并处理滚动的视图。
    let scrollView = QuickLayoutScrollView(.vertical)
    /// 组合余额卡片、充值档位和底部操作的内容容器。
    let contentView = RechargeContentView(frame: .zero)
    /// 显示充值成功反馈的覆盖视图。
    let successOverlayView = RechargeSuccessView(frame: .zero)

    /// 用户选择充值档位时调用的回调；参数为所选档位。
    var packageDidSelect: ((RechargePackage) -> Void)?
    /// 用户点击充值按钮时调用的回调。
    var rechargeDidTap: (() -> Void)?

    /// 当前状态标签的显示文案。
    var statusText: String? { contentView.footerView.statusText }
    /// 一个布尔值，指示充值成功浮层当前是否可见。
    var isSuccessAnimationVisible: Bool { !successOverlayView.isHidden }
    /// 已启动的充值成功反馈次数，供状态检查使用。
    var successAnimationCount = 0

    /// 驱动余额数字插值的显示刷新连接；停止后为 `nil`。
    var balanceDisplayLink: CADisplayLink?
    /// 余额数字动画的媒体时间起点，单位为秒。
    var balanceAnimationStartTime: CFTimeInterval = 0
    /// 余额数字动画的起始金币数。
    var balanceAnimationFrom = 0
    /// 余额数字动画最终显示的确认金币数。
    var balanceAnimationTo = 0

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

    /// 在主执行器上停止显示刷新，避免释放时跨隔离访问 UIKit 资源。
    isolated deinit {
        balanceDisplayLink?.invalidate()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        ZStack {
            backgroundView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            ScrollView(scrollView, .vertical) {
                contentView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)
            }
            // 仅背景延伸到全屏；充值内容仍避开导航栏、刘海和底部安全区。
            .safeAreaPadding(.all, 0)

            successOverlayView
                .resizable()
                .frame(width: 238, height: 162)
        }
    }

    /// 绑定档位选择和充值点击回调。
    func bindActions(
        packageDidSelect: @escaping (RechargePackage) -> Void,
        rechargeDidTap: @escaping () -> Void
    ) {
        self.packageDidSelect = packageDidSelect
        self.rechargeDidTap = rechargeDidTap
    }

    /// 更新余额、充值需求、档位与按钮文案，并按要求保留状态提示。
    func configure(
        balanceCaption: String,
        balanceText: String,
        requirementText: String,
        packageTitle: String,
        packages: [RechargePackage],
        selectedPackageAmount: Int,
        rechargeTitle: String,
        preservesStatus: Bool
    ) {
        contentView.balanceCardView.configure(
            caption: balanceCaption,
            balance: balanceText,
            requirement: requirementText
        )
        contentView.packageSectionView.configure(
            title: packageTitle,
            packages: packages,
            selectedAmount: selectedPackageAmount
        )
        contentView.footerView.configureRechargeButton(title: rechargeTitle)
        if !preservesStatus {
            contentView.footerView.setStatus(
                statusText,
                color: UIColor.white.withAlphaComponent(0.68)
            )
        }
        setNeedsQuickLayout()
    }

    /// 清除充值结果提示并恢复内容布局。
    func clearStatus() {
        contentView.footerView.setStatus(
            nil,
            color: UIColor.white.withAlphaComponent(0.68)
        )
    }

    /// 以失败提示颜色显示指定充值状态文案。
    func showFailureStatus(_ text: String) {
        contentView.footerView.setStatus(text, color: .systemPink)
    }

    /// 以成功提示颜色显示指定充值状态文案。
    func showSuccessStatus(_ text: String) {
        contentView.footerView.setStatus(text, color: .systemGreen)
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        accessibilityIdentifier = "liveRoom.recharge.page"
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        contentView.packageSectionView.packageDidSelect = { [weak self] package in
            self?.packageDidSelect?(package)
        }
        contentView.footerView.rechargeDidTap = { [weak self] in
            self?.rechargeDidTap?()
        }

        successOverlayView.isHidden = true
        successOverlayView.alpha = 0
        successOverlayView.accessibilityIdentifier =
            "liveRoom.recharge.successOverlay"
    }
}

#if DEBUG
/// 创建展示完整充值页面内容的预览控制器。
@MainActor
private func makeRechargeViewPreview() -> UIViewController {
    let view = RechargeView(frame: .zero)
    view.bindActions(packageDidSelect: { _ in }, rechargeDidTap: {})
    view.configure(
        balanceCaption: "当前余额",
        balanceText: "12,048 星币",
        requirementText: "本次赠送需余额 88,888",
        packageTitle: "选择充值档位",
        packages: RechargePackage.catalog,
        selectedPackageAmount: 12_800,
        rechargeTitle: "充值 13,600 星币",
        preservesStatus: false
    )
    return QuickLayoutHostingController {
        view
            .resizable()
    }
}

@available(iOS 17.0, *)
#Preview("充值根视图") {
    makeRechargeViewPreview()
}
#endif
