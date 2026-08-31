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
    private let followButton = LiveRoomFollowButton(frame: .zero)
    private var messageLabels: [UILabel] = []
    private var shouldScrollToLatest = false
    private var scrollRequestGeneration = 0
    private var scheduledScrollGeneration: Int?

    var followDidTap: (() -> Void)?

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
                followButton
                    .fixedSize(axis: .horizontal)
                    .fixedSize(axis: .vertical)
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
        isFollowing: Bool,
        isFollowRequesting: Bool,
        messages: [String],
        scrollToLatest: Bool
    ) {
        titleLabel.text = title
        followButton.configure(
            title: follow,
            isFollowing: isFollowing,
            isRequesting: isFollowRequesting
        )
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

        followButton.accessibilityIdentifier = "liveRoom.follow.button"
        followButton.action = { [weak self] in
            self?.followDidTap?()
        }

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

/// 公屏关注按钮。
///
/// 未关注时使用高强调色提示主操作；已关注时降低饱和度并显示对勾，让用户能够快速
/// 区分“可关注”与“已完成”状态，同时保留再次点击取消关注的按钮语义。
final class LiveRoomFollowButton: LiveRoomHitTargetButton {

    private let checkmarkImageView = UIImageView(
        image: UIImage(systemName: "checkmark")
    )
    private let activityIndicatorView = UIActivityIndicatorView(
        style: .medium
    )
    private let titleLabel = UILabel()
    private var isFollowing = false
    private var isRequesting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        HStack(spacing: 5) {
            if isRequesting {
                activityIndicatorView
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                if isFollowing {
                    checkmarkImageView
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                }
                titleLabel.fixedSize(axis: .horizontal)
            }
        }
        .padding(.horizontal, isRequesting ? 8 : (isFollowing ? 10 : 9))
        .padding(.vertical, 5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func configure(
        title: String,
        isFollowing: Bool,
        isRequesting: Bool
    ) {
        let didChangeLayoutState = self.isFollowing != isFollowing
            || self.isRequesting != isRequesting
        self.isFollowing = isFollowing
        self.isRequesting = isRequesting
        titleLabel.text = title
        titleLabel.textColor = isFollowing
            ? UIColor.white.withAlphaComponent(0.88)
            : .white
        checkmarkImageView.tintColor = UIColor.white.withAlphaComponent(0.82)
        backgroundColor = isFollowing
            ? UIColor.white.withAlphaComponent(0.14)
            : .systemPink
        layer.borderWidth = isFollowing ? 1 : 0
        layer.borderColor = isFollowing
            ? UIColor.white.withAlphaComponent(0.24).cgColor
            : UIColor.clear.cgColor
        self.isSelected = isFollowing
        accessibilityLabel = title
        var traits: UIAccessibilityTraits = isFollowing
            ? [.button, .selected]
            : .button
        if isRequesting {
            traits.insert(.notEnabled)
            activityIndicatorView.startAnimating()
        } else {
            activityIndicatorView.stopAnimating()
        }
        accessibilityTraits = traits
        isEnabled = !isRequesting
        if didChangeLayoutState {
            setNeedsQuickLayout()
        }
        apply(state: buttonState)
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        layer.cornerCurve = .circular
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isUserInteractionEnabled = false
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.isUserInteractionEnabled = false
        checkmarkImageView.isAccessibilityElement = false
        checkmarkImageView.accessibilityIdentifier =
            "liveRoom.follow.checkmark"
        activityIndicatorView.color = .white
        activityIndicatorView.hidesWhenStopped = true
        activityIndicatorView.isUserInteractionEnabled = false
        activityIndicatorView.isAccessibilityElement = false
        activityIndicatorView.accessibilityIdentifier =
            "liveRoom.follow.activityIndicator"
    }

    private func apply(state: QuickLayoutButtonState) {
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.96, y: 0.96)
            : .identity
        alpha = state.isPressed
            ? 0.80
            : (state.isEnabled ? 1 : (isRequesting ? 0.82 : 0.56))
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomMessagesViewPreview(
    title: String,
    isFollowing: Bool,
    isRequesting: Bool
) -> UIViewController {
    let view = LiveRoomMessagesView()
    view.configure(
        title: "直播互动",
        follow: title,
        isFollowing: isFollowing,
        isFollowRequesting: isRequesting,
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

#Preview("公屏消息 · 已关注") {
    makeLiveRoomMessagesViewPreview(
        title: "已关注",
        isFollowing: true,
        isRequesting: false
    )
}

#Preview("公屏消息 · 关注请求中") {
    makeLiveRoomMessagesViewPreview(
        title: "关注中…",
        isFollowing: false,
        isRequesting: true
    )
}
#endif
