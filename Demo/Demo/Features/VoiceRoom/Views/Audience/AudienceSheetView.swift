//
//  AudienceSheetView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 组合观众面板页头与观众集合列表的内容视图。
final class AudienceSheetView: QuickLayoutView {

    /// 负责内容条目展示和复用的集合视图。
    let collectionView: UICollectionView = {
        UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
    }()

    /// 组件内容后方的背景视图。
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
    /// 面板顶部的标题和摘要视图。
    private let headerView = AudienceSheetHeaderView()

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

    /// 更新观众列表页头显示的标题和人数信息。
    func configure(title: String, summary: String, subtitle: String) {
        headerView.configure(
            title: title,
            summary: summary,
            subtitle: subtitle
        )
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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
@available(iOS 17.0, *)
#Preview("在线用户 Sheet 内容") {
    AudienceSheetViewController(
        viewModel: AudienceSheetViewModel(
            totalCount: 1_280,
            members: VoiceRoomPreviewData.audienceMembers
        )
    )
}
#endif
