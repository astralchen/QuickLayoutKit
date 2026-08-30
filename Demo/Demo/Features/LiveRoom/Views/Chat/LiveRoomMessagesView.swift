//
//  LiveRoomMessagesView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomMessagesView: LiveRoomCardView {

    let scrollView = QuickLayoutScrollView()
    private let titleLabel = UILabel()
    private let followLabel = UILabel()
    private let followBackgroundView = UIView()
    private var messageLabels: [UILabel] = []
    private var shouldScrollToLatest = false
    private var scrollRequestGeneration = 0
    private var scheduledScrollGeneration: Int?

    var latestMessage: String? {
        messageLabels.last?.text
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                titleLabel
                Spacer()
                followLabel
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background { followBackgroundView }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView(scrollView) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(messageLabels) { label in
                        label
                            .resizable(axis: .horizontal)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, 14, for: .scrollContent)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollIndicators)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard shouldScrollToLatest else { return }
        scrollToLatest()
    }

    /// 在 Controller 根布局稳定后提交最后一次滚动并清除请求。
    ///
    /// 输入编辑器消失时，公屏可能在同一事务内经历两次高度变化。子视图首次布局
    /// 不能提前消费请求，否则最终高度提交后将不再位于最新消息。
    func commitPendingScrollToLatest() {
        guard shouldScrollToLatest else { return }
        scrollToLatest()
        let generation = scrollRequestGeneration
        guard scheduledScrollGeneration != generation else { return }
        scheduledScrollGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.shouldScrollToLatest,
                self.scrollRequestGeneration == generation
            else { return }
            // ScrollView 的 contentSize 可能晚于父级 QuickLayout 一个提交周期更新。
            // 在清除请求前按最终几何再滚动一次，避免停在倒数一条消息。
            self.scrollToLatest()
            self.shouldScrollToLatest = false
            self.scheduledScrollGeneration = nil
        }
    }

    private func scrollToLatest() {
        scrollView.layoutIfNeeded()
        let bottomOffset = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.bottom
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: bottomOffset),
            animated: false
        )
    }

    func configure(
        title: String,
        follow: String,
        messages: [String],
        scrollToLatest: Bool
    ) {
        titleLabel.text = title
        followLabel.text = follow
        while messageLabels.count < messages.count {
            messageLabels.append(makeMessageLabel())
        }
        if messageLabels.count > messages.count {
            messageLabels.removeLast(messageLabels.count - messages.count)
        }
        for (index, label) in messageLabels.enumerated() {
            label.text = messages[index]
            label.accessibilityIdentifier = if index == messages.indices.last {
                "liveRoom.publicChat.latest"
            } else {
                "liveRoom.publicChat.message.\(index)"
            }
        }
        shouldScrollToLatest = scrollToLatest
        if scrollToLatest {
            scrollRequestGeneration += 1
            scheduledScrollGeneration = nil
        }
        setNeedsQuickLayout()
    }

    private func configureViews() {
        accessibilityIdentifier = "liveRoom.publicChat.container"
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
        scrollView.accessibilityIdentifier = "liveRoom.publicChat.scroll"

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true

        followLabel.font = .preferredFont(forTextStyle: .caption1)
        followLabel.textColor = .white
        followLabel.adjustsFontForContentSizeCategory = true
        followBackgroundView.backgroundColor = .systemPink
        followBackgroundView.layer.cornerRadius = 11

    }

    private func makeMessageLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = UIColor.white.withAlphaComponent(0.82)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .natural
        return label
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomMessagesViewPreview() -> UIViewController {
    let view = LiveRoomMessagesView()
    view.configure(
        title: "直播互动",
        follow: "关注直播间",
        messages: LiveRoomPreviewData.messages,
        scrollToLatest: true
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 300)
    }
}

#Preview("公屏消息") {
    makeLiveRoomMessagesViewPreview()
}
#endif
