//
//  AudienceSheetHeaderView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 在线用户 Sheet 的固定上下文头部；列表滚动时不随内容离开屏幕。
final class AudienceSheetHeaderView: QuickLayoutView {

    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示汇总信息的标签。
    private let summaryLabel = UILabel()
    /// 显示标题补充说明的标签。
    private let subtitleLabel = UILabel()
    /// 分隔相邻内容区域的细线视图。
    private let dividerView = UIView()

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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 9) {
                    titleLabel
                        .resizable(axis: .horizontal)
                    summaryLabel
                        .fixedSize(axis: .horizontal)
                }
                subtitleLabel
                    .resizable(axis: .horizontal)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            dividerView
                .resizable()
                .frame(height: pixelAlignedDividerHeight)
        }
    }

    /// 按当前显示设备的缩放比例换算一个物理像素，并将结果保留两位小数。
    private var pixelAlignedDividerHeight: CGFloat {
        let onePixelHeight = 1 / max(traitCollection.displayScale, 1)
        return (onePixelHeight * 100).rounded() / 100
    }

    /// 更新观众面板的标题、在线人数摘要和补充说明。
    func configure(title: String, summary: String, subtitle: String) {
        titleLabel.text = title
        summaryLabel.text = summary
        subtitleLabel.text = subtitle
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        backgroundColor = .clear
        accessibilityIdentifier = "liveRoom.audience.header"

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true

        summaryLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        summaryLabel.textColor = .systemYellow

        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        dividerView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    }
}

#if DEBUG
/// 创建展示观众面板页头的预览控制器。
@MainActor
private func makeAudienceSheetHeaderPreview() -> UIViewController {
    let headerView = AudienceSheetHeaderView()
    headerView.configure(
        title: VoiceRoomPreviewData.audienceHeaderTitle,
        summary: VoiceRoomPreviewData.audienceHeaderSummary,
        subtitle: VoiceRoomPreviewData.audienceHeaderSubtitle
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            headerView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
    }
}

@available(iOS 17.0, *)
#Preview("在线用户 Sheet 头部") {
    makeAudienceSheetHeaderPreview()
}
#endif
