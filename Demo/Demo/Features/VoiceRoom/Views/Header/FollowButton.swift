import QuickLayout
import QuickLayoutKit
import UIKit

/// 页头关注入口。常驻的两组文案共同参与测量，状态过渡不改变按钮宽度。
final class FollowButton: MinimumHitTargetButton {
    private struct PresentationState: Equatable {
        let isFollowing: Bool
        let isRequesting: Bool
    }

    private let gradientView = FollowGradientView()
    private let followedBackground = UIView()
    private let followLabel = UILabel()
    private let followedLabel = UILabel()
    private let plusImageView = UIImageView(image: UIImage(systemName: "plus"))
    private let checkmarkImageView = UIImageView(image: UIImage(systemName: "checkmark"))
    private let activityIndicatorView = UIActivityIndicatorView(style: .medium)
    private var presentationState: PresentationState?
    private var transitionAnimator: UIViewPropertyAnimator?
    private var iconAnimator: UIViewPropertyAnimator?
    private var pressAnimator: UIViewPropertyAnimator?
    private var generation = 0
    /// 可注入以验证减少动态效果；生产环境始终读取系统设置。
    var isReduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    var isTransitionAnimating: Bool { transitionAnimator?.isRunning == true || iconAnimator?.isRunning == true }

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
            gradientView.resizable()
            followedBackground.resizable()
            HStack(spacing: 5) {
                ZStack {
                    plusImageView.resizable().scaledToFit().frame(width: 12, height: 12)
                    checkmarkImageView.resizable().scaledToFit().frame(width: 12, height: 12)
                    activityIndicatorView.resizable().frame(width: 14, height: 14)
                }.frame(width: 16, height: 16)
                ZStack {
                    followLabel.fixedSize()
                    followedLabel.fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(minWidth: 88, minHeight: 28)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        for view in [gradientView, followedBackground] {
            view.layer.cornerRadius = min(view.bounds.width, view.bounds.height) / 2
        }
    }

    func configure(
        followTitle: String,
        followedTitle: String,
        accessibilityTitle: String,
        isFollowing: Bool,
        isRequesting: Bool
    ) {
        let previous = presentationState
        let next = PresentationState(isFollowing: isFollowing, isRequesting: isRequesting)
        let textChanged = followLabel.text != followTitle || followedLabel.text != followedTitle
        followLabel.text = followTitle
        followedLabel.text = followedTitle
        presentationState = next
        accessibilityLabel = accessibilityTitle
        isSelected = isFollowing
        accessibilityTraits = isFollowing ? [.button, .selected] : .button
        if isRequesting { accessibilityTraits.insert(.notEnabled) }
        isEnabled = !isRequesting
        if textChanged { setNeedsQuickLayout() }

        let animated = previous != nil && previous != next && !textChanged
            && window != nil && UIView.areAnimationsEnabled
        transition(from: previous, to: next, animated: animated)
    }

    private func transition(from previous: PresentationState?, to next: PresentationState, animated: Bool) {
        generation += 1
        let submission = generation
        interruptTransitions()
        if next.isRequesting { activityIndicatorView.startAnimating() }
        guard animated else {
            UIView.performWithoutAnimation { applyAppearance(next) }
            finishTransition(next)
            return
        }
        let reduced = isReduceMotionEnabled()
        let failed = previous?.isRequesting == true && !next.isRequesting
            && previous?.isFollowing == next.isFollowing
        let duration: TimeInterval = reduced ? 0.1 : (next.isRequesting ? 0.14 : (failed ? 0.18 : 0.22))
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) { [weak self] in
            self?.applyAppearance(next)
        }
        animator.addCompletion { [weak self] _ in
            guard let self, self.generation == submission else { return }
            self.transitionAnimator = nil
            self.finishTransition(next)
        }
        transitionAnimator = animator
        animator.startAnimation()

        if !reduced, previous?.isRequesting == true,
           previous?.isFollowing == false, next.isFollowing, !next.isRequesting {
            checkmarkImageView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            let spring = UIViewPropertyAnimator(duration: 0.32, dampingRatio: 0.75) { [weak self] in
                self?.checkmarkImageView.transform = .identity
            }
            spring.addCompletion { [weak self] _ in
                guard let self, self.generation == submission else { return }
                self.iconAnimator = nil
                self.checkmarkImageView.transform = .identity
            }
            iconAnimator = spring
            spring.startAnimation()
        }
    }

    private func applyAppearance(_ state: PresentationState) {
        gradientView.alpha = state.isFollowing ? 0 : 1
        followedBackground.alpha = state.isFollowing ? 1 : 0
        followLabel.alpha = state.isFollowing ? 0 : 1
        followedLabel.alpha = state.isFollowing ? 1 : 0
        plusImageView.alpha = !state.isRequesting && !state.isFollowing ? 1 : 0
        checkmarkImageView.alpha = !state.isRequesting && state.isFollowing ? 1 : 0
        activityIndicatorView.alpha = state.isRequesting ? 1 : 0
    }

    private func finishTransition(_ state: PresentationState) {
        if !state.isRequesting { activityIndicatorView.stopAnimating() }
    }

    /// 保留被打断动画的当前视觉值，新动画从该位置衔接；旧完成回调由代次过滤。
    private func interruptTransitions() {
        for animator in [transitionAnimator, iconAnimator] {
            if animator?.state == .active {
                animator?.stopAnimation(false)
                animator?.finishAnimation(at: .current)
            }
        }
        transitionAnimator = nil
        iconAnimator = nil
        checkmarkImageView.transform = .identity
    }

    override func quickLayoutButtonStateDidChange(_ state: QuickLayoutButtonState) {
        super.quickLayoutButtonStateDidChange(state)
        let currentTransform = layer.presentation()?.affineTransform() ?? transform
        pressAnimator?.stopAnimation(true)
        transform = currentTransform
        let target = state.isPressed && !isReduceMotionEnabled()
            ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        guard window != nil, UIView.areAnimationsEnabled, !isReduceMotionEnabled() else {
            transform = target
            return
        }
        // 按压只操作外层，成功回弹只操作内部对勾。
        let animator = UIViewPropertyAnimator(duration: 0.1, curve: .easeOut) { [weak self] in
            self?.transform = target
        }
        pressAnimator = animator
        animator.startAnimation()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateFonts()
            settleAppearance()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { settleAppearance() }
    }

    @objc private func settleAppearance() {
        generation += 1
        interruptTransitions()
        pressAnimator?.stopAnimation(true)
        pressAnimator = nil
        transform = .identity
        if let state = presentationState {
            UIView.performWithoutAnimation { applyAppearance(state) }
            finishTransition(state)
        }
    }

    private func updateFonts() {
        let font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold), compatibleWith: traitCollection
        )
        followLabel.font = font
        followedLabel.font = font
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        layer.cornerCurve = .circular
        gradientView.clipsToBounds = true
        followedBackground.backgroundColor = .white.withAlphaComponent(0.14)
        followedBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        followedBackground.layer.borderWidth = 1
        for view in [gradientView, followedBackground, followLabel, followedLabel, plusImageView, checkmarkImageView, activityIndicatorView] {
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }
        followLabel.textColor = .white
        followedLabel.textColor = .white.withAlphaComponent(0.9)
        followLabel.accessibilityIdentifier = "liveRoom.follow.title"
        followedLabel.accessibilityIdentifier = "liveRoom.follow.followedTitle"
        for imageView in [plusImageView, checkmarkImageView] {
            imageView.tintColor = .white
            imageView.contentMode = .scaleAspectFit
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(weight: .semibold)
        }
        plusImageView.accessibilityIdentifier = "liveRoom.follow.plus"
        checkmarkImageView.accessibilityIdentifier = "liveRoom.follow.checkmark"
        activityIndicatorView.color = .white
        activityIndicatorView.hidesWhenStopped = false
        activityIndicatorView.accessibilityIdentifier = "liveRoom.follow.activityIndicator"
        updateFonts()
        NotificationCenter.default.addObserver(self, selector: #selector(settleAppearance),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
}

private final class FollowGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor(red: 244 / 255, green: 82 / 255, blue: 155 / 255, alpha: 1).cgColor,
                           UIColor(red: 152 / 255, green: 98 / 255, blue: 235 / 255, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }

    required init?(coder: NSCoder) { return nil }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("关注 · 四种状态") {
    let buttons = [(false, false), (false, true), (true, false), (true, true)].map { following, requesting in
        let button = FollowButton(frame: .zero)
        button.configure(followTitle: "关注", followedTitle: "已关注", accessibilityTitle: "关注直播间",
                         isFollowing: following, isRequesting: requesting)
        return button
    }
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            VStack(spacing: 16) {
                buttons[0].fixedSize()
                buttons[1].fixedSize()
                buttons[2].fixedSize()
                buttons[3].fixedSize()
            }.padding(20)
        }
    }
}
#endif
