//
//  RoomPublicChatView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示房间公屏消息及关注状态的可滚动内容视图。
final class RoomPublicChatView: TranslucentCardView {

    /// 承载内容并处理滚动的视图。
    let scrollView = QuickLayoutScrollView()
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 切换并显示房间关注状态的按钮。
    private let followButton = FollowButton(frame: .zero)
    /// 按消息顺序排列的公屏文本标签。
    private var messageLabels: [UILabel] = []
    /// 一个布尔值，指示下一次有效布局后是否需要滚动到最新消息。
    private var shouldScrollToLatest = false
    /// 滚动请求的递增代次，用于排除过期回调。
    private var scrollRequestGeneration = 0
    /// 已安排执行的滚动请求代次；没有排队请求时为 `nil`。
    private var scheduledScrollGeneration: Int?

    /// 用户点击关注按钮时调用的回调。
    var followDidTap: (() -> Void)?

    /// 当前列表最后一条消息的文案；没有消息时为 `nil`。
    var latestMessage: String? {
        messageLabels.last?.text
    }

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

    /// 在内容布局后尝试执行当前有效的滚动到最新消息请求。
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

    /// 根据布局后的内容尺寸滚动到最后一条消息。
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

    /// 更新公屏标题、关注状态与消息列表，并记录是否需要滚动到底部。
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

    /// 配置子视图的样式、交互和辅助功能属性。
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

    /// 创建符合公屏字体、颜色和多行显示规则的消息标签。
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
final class FollowButton: MinimumHitTargetButton {

    /// 显示已关注或已选中状态的勾选图标。
    private let checkmarkImageView = UIImageView(
        image: UIImage(systemName: "checkmark")
    )
    /// 显示请求正在进行的活动指示器。
    private let activityIndicatorView = UIActivityIndicatorView(
        style: .medium
    )
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 一个布尔值，指示当前用户是否已关注房间。
    private var isFollowing = false
    /// 一个布尔值，指示当前操作是否正在等待业务确认。
    private var isRequesting = false

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

    /// 根据按钮实际高度更新胶囊形圆角。
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    /// 更新关注文案、已关注标记和请求加载状态。
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

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        apply(state: state)
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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

    /// 根据按钮高亮及可用状态更新关注按钮外观。
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
/// 创建展示指定关注状态的房间公屏的预览控制器。
@MainActor
private func makeRoomPublicChatViewPreview(
    title: String,
    isFollowing: Bool,
    isRequesting: Bool
) -> UIViewController {
    let view = RoomPublicChatView()
    view.configure(
        title: "直播互动",
        follow: title,
        isFollowing: isFollowing,
        isFollowRequesting: isRequesting,
        messages: VoiceRoomPreviewData.messages,
        scrollToLatest: true
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 300)
    }
}

@available(iOS 17.0, *)
#Preview("公屏消息 · 已关注") {
    makeRoomPublicChatViewPreview(
        title: "已关注",
        isFollowing: true,
        isRequesting: false
    )
}

@available(iOS 17.0, *)
#Preview("公屏消息 · 关注请求中") {
    makeRoomPublicChatViewPreview(
        title: "关注中…",
        isFollowing: false,
        isRequesting: true
    )
}
#endif
