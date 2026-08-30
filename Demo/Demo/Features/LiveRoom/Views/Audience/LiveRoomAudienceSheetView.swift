//
//  LiveRoomAudienceSheetView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomAudienceSheetView: QuickLayoutView {

    let collectionView: UICollectionView = {
        UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
    }()

    private let backgroundView = QuickLayoutLinearGradientView(
        stops: [
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.12, green: 0.06, blue: 0.28, alpha: 1),
                location: 0
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.05, green: 0.08, blue: 0.20, alpha: 1),
                location: 1
            ),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private let headerView = LiveRoomAudienceSheetHeaderView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        ZStack {
            // 背景覆盖完整 Sheet，内容再分别处理顶部与底部安全区域。
            backgroundView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            VStack(spacing: 0) {
                headerView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)

                collectionView.resizable()
            }
            // 安全区域在前景容器边界统一消费，避免固定高度 Header 的测量顺序
            // 让标题与 Dynamic Island 或系统 Sheet grabber 落入同一纵向区域。
            .safeAreaPadding(.top, 0)
        }
    }

    func configure(title: String, summary: String, subtitle: String) {
        headerView.configure(
            title: title,
            summary: summary,
            subtitle: subtitle
        )
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "liveRoom.audience.sheet"
        backgroundColor = .clear

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.showsVerticalScrollIndicator = true
        collectionView.indicatorStyle = .white
        collectionView.accessibilityIdentifier = "liveRoom.audience.list"
    }
}

#if DEBUG
#Preview("在线用户 Sheet 内容") {
    LiveRoomAudienceSheetViewController(
        viewModel: LiveRoomAudienceViewModel(
            totalCount: 1_280,
            members: LiveRoomPreviewData.audienceMembers
        )
    )
}
#endif
