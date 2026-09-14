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

    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let dividerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

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

    func configure(title: String, summary: String, subtitle: String) {
        titleLabel.text = title
        summaryLabel.text = summary
        subtitleLabel.text = subtitle
        setNeedsQuickLayout()
    }

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
