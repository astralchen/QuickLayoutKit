//
//  IMessageChatMediaViews.swift
//  Demo
//
//  UIKit views for media drafts, sent media messages, and full-screen preview.
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

nonisolated struct IMessageChatMediaStrings: Equatable, Sendable {
    let photo: String
    let itemsFormat: String
    let image: String
    let animatedImage: String
    let video: String
    let videoDurationFormat: String
    let importing: String
    let remove: String
    let play: String
    let openPreview: String
    let close: String
    let firstItem: String
    let lastItem: String
    let positionFormat: String
}

/// Composer 媒体预览项的尺寸规则。
///
/// 设计图固定预览高度，并让宽度跟随附件像素比例。极窄或极宽资源会被限制在
/// 合理范围，避免删除按钮相互覆盖或单个横图占满整条输入栏。
nonisolated enum IMessageChatMediaDraftLayoutPolicy {
    static let itemHeight: CGFloat = 120
    static let minimumWidth: CGFloat = 80
    static let maximumWidth: CGFloat = 160

    static func itemSize(for pixelSize: CGSize?) -> CGSize {
        guard let pixelSize,
              pixelSize.width.isFinite,
              pixelSize.height.isFinite,
              pixelSize.width > 0,
              pixelSize.height > 0 else {
            return CGSize(width: minimumWidth, height: itemHeight)
        }
        let aspectRatio = pixelSize.width / pixelSize.height
        let width = min(maximumWidth, max(minimumWidth, itemHeight * aspectRatio))
        return CGSize(width: width, height: itemHeight)
    }
}

@MainActor
final class IMessageChatMediaStackStateStore {
    private var indices: [Int: Int] = [:]

    func index(for messageID: Int, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return min(max(0, indices[messageID] ?? 0), itemCount - 1)
    }

    func setIndex(_ index: Int, for messageID: Int, itemCount: Int) {
        guard itemCount > 0 else {
            indices.removeValue(forKey: messageID)
            return
        }
        indices[messageID] = min(max(0, index), itemCount - 1)
    }

    func retainMessages(_ messageIDs: Set<Int>) {
        indices = indices.filter { messageIDs.contains($0.key) }
    }
}

/// 层叠媒体的纯展示算法。所有结果都只基于索引计算，不改变附件数组。
nonisolated enum IMessageChatMediaStackPolicy {
    static let maximumVisibleCardCount = 5

    static func renderOrder(frontIndex: Int, itemCount: Int) -> [Int] {
        guard itemCount > 0 else { return [] }
        let front = min(max(0, frontIndex), itemCount - 1)
        return Array(front..<itemCount) + Array(0..<front)
    }

    /// 返回围绕当前封面的连续可见窗口。
    ///
    /// 窗口最多保留五项：中间位置优先在当前项两侧各保留两项；接近首尾时，
    /// 空出来的名额让给另一侧。结果始终按原始媒体索引递增，不改变附件顺序。
    static func visibleIndices(frontIndex: Int, itemCount: Int) -> [Int] {
        guard itemCount > 0 else { return [] }
        let front = min(max(0, frontIndex), itemCount - 1)
        let visibleCount = min(maximumVisibleCardCount, itemCount)
        var lowerBound = max(0, front - visibleCount / 2)
        var upperBound = min(itemCount, lowerBound + visibleCount)
        lowerBound = max(0, upperBound - visibleCount)
        upperBound = min(itemCount, lowerBound + visibleCount)
        return Array(lowerBound..<upperBound)
    }

    static func isHorizontalPan(velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y) * 1.2
    }

    static func targetIndex(
        frontIndex: Int,
        itemCount: Int,
        translationX: CGFloat,
        velocityX: CGFloat
    ) -> Int? {
        guard itemCount > 1 else { return nil }
        let directionalX = abs(translationX) >= 8 ? translationX : velocityX
        guard directionalX != 0 else { return nil }
        let target = frontIndex + (directionalX < 0 ? 1 : -1)
        return (0..<itemCount).contains(target) ? target : nil
    }

    static func shouldCommit(
        translationX: CGFloat,
        velocityX: CGFloat,
        cardWidth: CGFloat
    ) -> Bool {
        let passedDistance = abs(translationX) >= max(44, cardWidth * 0.18)
        let velocityMatchesTranslation = translationX == 0
            || velocityX == 0
            || (translationX < 0) == (velocityX < 0)
        let passedVelocity = abs(velocityX) >= 550 && velocityMatchesTranslation
        return passedDistance || passedVelocity
    }
}

@available(iOS 26.0, *)
final class IMessageChatMediaDraftStripView: UIView {
    private enum Metrics {
        static let spacing: CGFloat = 4
    }

    let scrollView = UIScrollView()
    private let contentView = UIView()
    private var itemViews: [UUID: DraftItemView] = [:]
    private var strings: IMessageChatMediaStrings?

    var removeRequested: ((UUID) -> Void)?

    /// 测试和页面级调试用于确认当前有序预览项的实际 frame。
    var renderedItemFrames: [CGRect] {
        itemViews.values
            .sorted(by: { $0.order < $1.order })
            .map(\.frame)
    }

    /// 当前显示动态图片标志的媒体 ID。
    var animatedBadgeItemIDs: Set<UUID> {
        Set(
            itemViews.compactMap { id, view in
                view.animatedBadgeView.isHidden ? nil : id
            }
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        accessibilityIdentifier = "imessage.composer.mediaStrip"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        var x: CGFloat = 0
        for view in itemViews.values.sorted(by: { $0.order < $1.order }) {
            view.frame = CGRect(origin: CGPoint(x: x, y: 0), size: view.itemSize)
            x += view.itemSize.width + Metrics.spacing
        }
        let width = max(0, x - Metrics.spacing)
        contentView.frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: IMessageChatMediaDraftLayoutPolicy.itemHeight
        )
        scrollView.contentSize = contentView.bounds.size
    }

    func configure(
        _ draft: IMessageChatMediaDraftPresentation?,
        strings: IMessageChatMediaStrings
    ) {
        self.strings = strings
        let items = draft?.items ?? []
        let wantedIDs = Set(items.map(\.id))
        for (id, view) in itemViews where !wantedIDs.contains(id) {
            view.removeFromSuperview()
            itemViews.removeValue(forKey: id)
        }
        for (order, item) in items.enumerated() {
            let itemView = itemViews[item.id] ?? DraftItemView()
            if itemView.superview == nil {
                contentView.addSubview(itemView)
                itemViews[item.id] = itemView
            }
            itemView.order = order
            itemView.configure(
                item,
                order: order,
                totalCount: items.count,
                strings: strings
            )
            itemView.removeRequested = { [weak self] in
                self?.removeRequested?(item.id)
            }
        }
        isHidden = items.isEmpty
        setNeedsLayout()
    }

    private final class DraftItemView: UIView {
        let imageView = UIImageView()
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        let videoBadge = UIImageView()
        let durationLabel = UILabel()
        let animatedBadgeView = UIView()
        let animatedBadgeImageView = UIImageView()
        let removeButton = UIButton(type: .system)
        var order = 0
        var itemSize = IMessageChatMediaDraftLayoutPolicy.itemSize(for: nil)
        var removeRequested: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.cornerRadius = 12
            layer.cornerCurve = .continuous
            backgroundColor = .secondarySystemFill

            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            addSubview(imageView)

            activityIndicator.hidesWhenStopped = true
            addSubview(activityIndicator)

            videoBadge.image = UIImage(systemName: "video.fill")
            videoBadge.tintColor = .white
            addSubview(videoBadge)

            durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            durationLabel.textColor = .white
            durationLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
            durationLabel.shadowOffset = CGSize(width: 0, height: 1)
            addSubview(durationLabel)

            animatedBadgeView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
            animatedBadgeView.layer.cornerRadius = 14
            animatedBadgeView.layer.cornerCurve = .continuous
            animatedBadgeImageView.image = UIImage(
                systemName: "livephoto",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 15,
                    weight: .semibold
                )
            )
            animatedBadgeImageView.tintColor = .systemBlue
            animatedBadgeImageView.contentMode = .scaleAspectFit
            animatedBadgeView.addSubview(animatedBadgeImageView)
            addSubview(animatedBadgeView)

            var configuration = UIButton.Configuration.filled()
            configuration.image = UIImage(systemName: "xmark")
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.62)
            configuration.contentInsets = .zero
            configuration.cornerStyle = .capsule
            removeButton.configuration = configuration
            removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
            addSubview(removeButton)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
            activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
            removeButton.frame = CGRect(x: bounds.maxX - 32, y: 0, width: 32, height: 32)
            animatedBadgeView.frame = CGRect(x: 6, y: 6, width: 28, height: 28)
            animatedBadgeImageView.frame = animatedBadgeView.bounds.insetBy(dx: 5, dy: 5)
            videoBadge.frame = CGRect(x: 8, y: bounds.maxY - 26, width: 20, height: 18)
            durationLabel.sizeToFit()
            durationLabel.frame.origin = CGPoint(
                x: bounds.maxX - durationLabel.bounds.width - 7,
                y: bounds.maxY - durationLabel.bounds.height - 6
            )
        }

        func configure(
            _ item: IMessageChatMediaDraftItemPresentation,
            order: Int,
            totalCount: Int,
            strings: IMessageChatMediaStrings
        ) {
            self.order = order
            imageView.image = nil
            videoBadge.isHidden = true
            durationLabel.isHidden = true
            animatedBadgeView.isHidden = true
            itemSize = IMessageChatMediaDraftLayoutPolicy.itemSize(for: nil)
            switch item.content {
            case .importing:
                activityIndicator.startAnimating()
                accessibilityLabel = strings.importing
            case .ready(let media):
                activityIndicator.stopAnimating()
                imageView.image = UIImage(contentsOfFile: media.thumbnailFileURL.path)
                itemSize = IMessageChatMediaDraftLayoutPolicy.itemSize(
                    for: media.pixelSize
                )
                let position = String(
                    format: strings.positionFormat,
                    order + 1,
                    totalCount
                )
                switch media.kind {
                case .image:
                    animatedBadgeView.isHidden = !media.isAnimatedImage
                    let imageDescription = media.isAnimatedImage
                        ? strings.animatedImage
                        : strings.image
                    accessibilityLabel = "\(position), \(imageDescription)"
                case .video(let duration):
                    videoBadge.isHidden = false
                    durationLabel.isHidden = false
                    durationLabel.text = Self.durationText(duration)
                    let videoDescription = String(
                        format: strings.videoDurationFormat,
                        durationLabel.text ?? ""
                    )
                    accessibilityLabel = "\(position), \(videoDescription)"
                }
            }
            removeButton.accessibilityLabel = strings.remove
            accessibilityIdentifier = "imessage.composer.media.\(item.id.uuidString)"
            setNeedsLayout()
        }

        @objc private func removeTapped() {
            removeRequested?()
        }

        private static func durationText(_ duration: TimeInterval) -> String {
            let seconds = max(0, Int(duration.rounded()))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }
}

@available(iOS 26.0, *)
final class IMessageChatMediaMessageView: UIView, UIGestureRecognizerDelegate {
    private enum Metrics {
        static let singleMaximumWidth: CGFloat = 252
        static let singleMaximumHeight: CGFloat = 360
        static let singleMinimumEdge: CGFloat = 120
        static let groupCardSize = CGSize(width: 216, height: 300)
        static let groupOffset = CGPoint(x: 8, y: 6)
        static let titleHeight: CGFloat = 24
        static let titleSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 22
    }

    private final class CardView: UIView {
        struct BindingIdentity: Equatable, Sendable {
            let messageID: Int
            let groupID: UUID
            let itemID: UUID
            let frontIndex: Int
        }

        let imageView = UIImageView()
        let playBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        let playImageView = UIImageView(image: UIImage(systemName: "play.fill"))
        var mediaIndex = 0
        var restingFrame: CGRect = .zero
        var restingTransform: CGAffineTransform = .identity
        private var representedIdentity: BindingIdentity?
        private var imageTask: Task<Void, Never>?

        func represents(
            messageID: Int,
            groupID: UUID,
            itemID: UUID
        ) -> Bool {
            representedIdentity?.messageID == messageID
                && representedIdentity?.groupID == groupID
                && representedIdentity?.itemID == itemID
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.cornerRadius = Metrics.cornerRadius
            layer.cornerCurve = .continuous
            backgroundColor = .secondarySystemFill
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            addSubview(imageView)
            playBackground.clipsToBounds = true
            playBackground.layer.cornerRadius = 24
            playImageView.tintColor = .label
            playImageView.contentMode = .scaleAspectFit
            playBackground.contentView.addSubview(playImageView)
            addSubview(playBackground)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
            playBackground.frame = CGRect(
                x: bounds.midX - 24,
                y: bounds.midY - 24,
                width: 48,
                height: 48
            )
            playImageView.frame = playBackground.contentView.bounds.insetBy(dx: 15, dy: 13)
        }

        func configure(
            _ item: IMessageChatMediaItem,
            index: Int,
            identity: BindingIdentity
        ) {
            let keepsCurrentImage = represents(
                messageID: identity.messageID,
                groupID: identity.groupID,
                itemID: identity.itemID
            )
            mediaIndex = index
            representedIdentity = identity
            imageTask?.cancel()
            if !keepsCurrentImage {
                imageView.image = nil
            }
            playBackground.isHidden = !item.kind.isVideo
            let url = item.thumbnailFileURL
            imageTask = Task { [weak self] in
                let data = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                guard !Task.isCancelled,
                      let self,
                      self.representedIdentity == identity,
                      let data else { return }
                self.imageView.image = UIImage(data: data)
            }
        }

        func reset() {
            imageTask?.cancel()
            imageTask = nil
            representedIdentity = nil
            imageView.image = nil
            playBackground.isHidden = true
            restingFrame = .zero
            restingTransform = .identity
            transform = .identity
            alpha = 1
            layer.zPosition = 0
        }
    }

    let itemCountLabel = UILabel()
    private let itemCountIcon = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill"))
    private let singleMaskLayer = CAShapeLayer()
    private var cards: [CardView] = []
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

    private var messageID = 0
    private var direction: IMessageChatDirection = .incoming
    private var group: IMessageChatMediaGroupAttachment?
    private var strings: IMessageChatMediaStrings?
    private(set) var frontMediaIndex = 0
    private var isAnimating = false
    private var resolvedSize = CGSize(width: 252, height: 252)

    var frontIndexDidChange: ((Int, Int) -> Void)?
    var previewRequested: ((Int, IMessageChatMediaGroupAttachment, Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        itemCountLabel.font = .preferredFont(forTextStyle: .headline)
        itemCountLabel.adjustsFontForContentSizeCategory = true
        itemCountLabel.textColor = .systemBlue
        itemCountLabel.textAlignment = .natural
        itemCountIcon.tintColor = .systemBlue
        addSubview(itemCountIcon)
        addSubview(itemCountLabel)
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        tapGesture.require(toFail: panGesture)
        addGestureRecognizer(tapGesture)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button, .adjustable]
        accessibilityIdentifier = "imessage.media.message"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { resolvedSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCards()
    }

    func configure(
        messageID: Int,
        direction: IMessageChatDirection,
        group: IMessageChatMediaGroupAttachment,
        frontIndex: Int,
        strings: IMessageChatMediaStrings
    ) {
        self.messageID = messageID
        self.direction = direction
        self.group = group
        self.strings = strings
        frontMediaIndex = min(max(0, frontIndex), max(0, group.items.count - 1))
        ensureCardCount(
            min(
                group.items.count,
                IMessageChatMediaStackPolicy.maximumVisibleCardCount
            )
        )
        let previousSize = resolvedSize
        resolvedSize = Self.size(for: group)
        if previousSize != resolvedSize { invalidateIntrinsicContentSize() }
        panGesture.isEnabled = group.items.count > 1
        itemCountLabel.isHidden = group.items.count == 1
        itemCountIcon.isHidden = group.items.count == 1
        itemCountLabel.text = String(format: strings.itemsFormat, group.items.count)
        accessibilityValue = String(
            format: strings.positionFormat,
            frontMediaIndex + 1,
            group.items.count
        )
        accessibilityHint = strings.openPreview
        updateAccessibilityLabel()
        bindCards()
        setNeedsLayout()
    }

    func reset() {
        group = nil
        strings = nil
        messageID = 0
        frontMediaIndex = 0
        isAnimating = false
        itemCountLabel.text = nil
        itemCountIcon.isHidden = true
        itemCountLabel.isHidden = true
        singleMaskLayer.path = nil
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityHint = nil
        cards.forEach { $0.reset() }
    }

    override func accessibilityIncrement() {
        move(to: frontMediaIndex + 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    override func accessibilityDecrement() {
        move(to: frontMediaIndex - 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let group,
              group.items.count > 1,
              !isAnimating else { return false }
        let velocity = panGesture.velocity(in: self)
        return IMessageChatMediaStackPolicy.isHorizontalPan(velocity: velocity)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let group else { return }
        let location = gesture.location(in: self)
        let index = cards
            .sorted { $0.layer.zPosition > $1.layer.zPosition }
            .first(where: { !$0.isHidden && $0.frame.contains(location) })?
            .mediaIndex ?? frontMediaIndex
        previewRequested?(messageID, group, index)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let group, group.items.count > 1, !isAnimating else { return }
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        let targetIndex = IMessageChatMediaStackPolicy.targetIndex(
            frontIndex: frontMediaIndex,
            itemCount: group.items.count,
            translationX: translation.x,
            velocityX: velocity.x
        )
        let directionalX = abs(translation.x) >= 8 ? translation.x : velocity.x
        let atBoundary = targetIndex == nil && directionalX != 0

        switch gesture.state {
        case .changed:
            let rawX = translation.x
            let x = atBoundary ? max(-18, min(18, rawX * 0.2)) : rawX
            frontCard?.transform = CGAffineTransform(translationX: x, y: 0)
                .rotated(by: max(-4, min(4, x / 45)) * .pi / 180)
        case .ended:
            let shouldCommit = IMessageChatMediaStackPolicy.shouldCommit(
                translationX: translation.x,
                velocityX: velocity.x,
                cardWidth: Metrics.groupCardSize.width
            )
            if let targetIndex, shouldCommit {
                move(to: targetIndex, animated: true, velocityX: velocity.x)
            } else {
                restoreCards(animated: true)
            }
        case .cancelled, .failed:
            restoreCards(animated: true)
        default:
            break
        }
    }

    private func move(to index: Int, animated: Bool, velocityX: CGFloat = 0) {
        guard let group else { return }
        guard group.items.indices.contains(index) else {
            restoreCards(animated: animated)
            let announcement = index < 0 ? strings?.firstItem : strings?.lastItem
            if let announcement {
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
            return
        }
        guard index != frontMediaIndex else { return }
        if !animated {
            frontMediaIndex = index
            bindCards()
            layoutCards()
            finishMove(to: index, in: group)
            return
        }
        if UIAccessibility.isReduceMotionEnabled {
            isAnimating = true
            UIView.transition(
                with: self,
                duration: 0.16,
                options: [.transitionCrossDissolve, .beginFromCurrentState],
                animations: { [weak self] in
                    guard let self else { return }
                    self.frontMediaIndex = index
                    self.bindCards()
                    self.layoutCards()
                },
                completion: { [weak self] _ in
                    self?.finishMove(to: index, in: group)
                }
            )
            return
        }
        isAnimating = true
        let previousIndex = frontMediaIndex
        let movingCard = frontCard
        let revealedCard = cards.first { !$0.isHidden && $0.mediaIndex == index }
        if !UIAccessibility.isReduceMotionEnabled {
            revealedCard?.transform = CGAffineTransform(scaleX: 0.965, y: 0.965)
        }
        let changes = { [weak self] in
            guard let self else { return }
            movingCard?.alpha = 0.12
            movingCard?.transform = CGAffineTransform(
                translationX: index > self.frontMediaIndex ? -72 : 72,
                y: 0
            ).rotated(
                by: (index > self.frontMediaIndex ? -4 : 4) * .pi / 180
            )
            revealedCard?.transform = .identity
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.frontMediaIndex = index
            self.bindCards()
            self.layoutCards()
            let retiredCard = self.cards.first {
                !$0.isHidden && $0.mediaIndex == previousIndex
            }
            if animated && !UIAccessibility.isReduceMotionEnabled,
               let retiredCard {
                retiredCard.alpha = 0
                retiredCard.transform = CGAffineTransform(
                    translationX: index > previousIndex ? -12 : 12,
                    y: 0
                ).concatenating(retiredCard.restingTransform)
                UIView.animate(
                    withDuration: 0.12,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: {
                        retiredCard.alpha = 1
                        retiredCard.transform = retiredCard.restingTransform
                    },
                    completion: { [weak self] _ in
                        self?.finishMove(to: index, in: group)
                    }
                )
            } else {
                self.finishMove(to: index, in: group)
            }
        }
        let normalizedVelocity = abs(velocityX) / max(1, Metrics.groupCardSize.width)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: normalizedVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes,
            completion: completion
        )
    }

    private func restoreCards(animated: Bool) {
        let changes: () -> Void = { [weak self] in
            guard let frontCard = self?.frontCard else { return }
            frontCard.transform = frontCard.restingTransform
        }
        guard animated && !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func bindCards() {
        guard let group, !group.items.isEmpty else { return }
        let visibleIndices = IMessageChatMediaStackPolicy.visibleIndices(
            frontIndex: frontMediaIndex,
            itemCount: group.items.count
        )
        var reusableCards = cards
        var orderedCards: [CardView] = []
        for index in visibleIndices {
            let item = group.items[index]
            let card: CardView
            if let existingIndex = reusableCards.firstIndex(where: {
                $0.represents(
                    messageID: messageID,
                    groupID: group.id,
                    itemID: item.id
                )
            }) {
                card = reusableCards.remove(at: existingIndex)
            } else {
                card = reusableCards.removeFirst()
            }
            orderedCards.append(card)
            card.isHidden = false
            card.configure(
                item,
                index: index,
                identity: CardView.BindingIdentity(
                    messageID: messageID,
                    groupID: group.id,
                    itemID: item.id,
                    frontIndex: frontMediaIndex
                )
            )
            card.layer.zPosition = CGFloat(30 - abs(index - frontMediaIndex))
            card.alpha = 1
        }
        cards = orderedCards + reusableCards
        reusableCards.forEach { $0.isHidden = true }
    }

    private func ensureCardCount(_ count: Int) {
        while cards.count < count {
            let card = CardView()
            cards.append(card)
            addSubview(card)
        }
        while cards.count > count {
            let card = cards.removeLast()
            card.reset()
            card.removeFromSuperview()
        }
    }

    private func layoutCards() {
        guard let group, !group.items.isEmpty else { return }
        let isGroup = group.items.count > 1
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let outwardSign: CGFloat = direction == .outgoing
            ? (isRTL ? -1 : 1)
            : (isRTL ? 1 : -1)

        if isGroup {
            let titleAtTrailingEdge = outwardSign > 0
            itemCountIcon.frame = CGRect(
                x: titleAtTrailingEdge ? bounds.maxX - 112 : 0,
                y: 2,
                width: 18,
                height: 18
            )
            itemCountLabel.frame = CGRect(
                x: titleAtTrailingEdge ? bounds.maxX - 90 : 22,
                y: 0,
                width: 90,
                height: Metrics.titleHeight
            )
            let cardY = Metrics.titleHeight + Metrics.titleSpacing
            let visibleIndices = IMessageChatMediaStackPolicy.visibleIndices(
                frontIndex: frontMediaIndex,
                itemCount: group.items.count
            )
            for card in cards where !card.isHidden {
                guard let position = visibleIndices.firstIndex(of: card.mediaIndex) else {
                    continue
                }
                let visualPosition = outwardSign > 0
                    ? position
                    : visibleIndices.count - position - 1
                let depth = abs(card.mediaIndex - frontMediaIndex)
                let relativeDirection = CGFloat(
                    card.mediaIndex == frontMediaIndex
                        ? 0
                        : card.mediaIndex > frontMediaIndex ? 1 : -1
                )
                let physicalSide = relativeDirection * outwardSign
                let rotationDegrees = -physicalSide * min(4, CGFloat(depth) * 1.2)
                card.layer.mask = nil
                let restingFrame = CGRect(
                    x: CGFloat(visualPosition) * Metrics.groupOffset.x,
                    y: cardY + CGFloat(depth) * Metrics.groupOffset.y,
                    width: Metrics.groupCardSize.width,
                    height: Metrics.groupCardSize.height
                )
                card.restingFrame = restingFrame
                card.transform = .identity
                card.bounds = CGRect(origin: .zero, size: restingFrame.size)
                card.center = CGPoint(x: restingFrame.midX, y: restingFrame.midY)
                card.restingTransform = CGAffineTransform(
                    rotationAngle: rotationDegrees * .pi / 180
                )
                card.transform = card.restingTransform
                card.layer.zPosition = CGFloat(30 - depth)
            }
        } else {
            itemCountIcon.frame = .zero
            itemCountLabel.frame = .zero
            let card = cards[0]
            card.frame = bounds
            card.restingFrame = bounds
            card.layer.mask = singleMaskLayer
            singleMaskLayer.frame = card.bounds
            singleMaskLayer.path = bubblePath(
                in: card.bounds,
                tailOnRight: direction == .outgoing ? !isRTL : isRTL
            )
        }
    }

    private func updateAccessibilityLabel() {
        guard let group, let strings, !group.items.isEmpty else { return }
        let item = group.items[frontMediaIndex]
        let kind = item.kind.isVideo ? strings.video : strings.image
        if group.items.count == 1 {
            accessibilityLabel = kind
        } else {
            accessibilityLabel = "\(String(format: strings.itemsFormat, group.items.count)), \(kind)"
        }
    }

    private static func size(for group: IMessageChatMediaGroupAttachment) -> CGSize {
        guard group.items.count == 1, let item = group.items.first else {
            let backCardCount = min(
                group.items.count,
                IMessageChatMediaStackPolicy.maximumVisibleCardCount
            ) - 1
            return CGSize(
                width: Metrics.groupCardSize.width
                    + Metrics.groupOffset.x * CGFloat(backCardCount),
                height: Metrics.titleHeight + Metrics.titleSpacing
                    + Metrics.groupCardSize.height
                    + Metrics.groupOffset.y * CGFloat(backCardCount)
            )
        }
        let rawRatio = item.pixelSize.width / max(1, item.pixelSize.height)
        let ratio = min(1.55, max(0.70, rawRatio))
        var width = Metrics.singleMaximumWidth
        var height = width / ratio
        if height > Metrics.singleMaximumHeight {
            height = Metrics.singleMaximumHeight
            width = max(Metrics.singleMinimumEdge, height * ratio)
        }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    /// 返回当前已绑定媒体卡片的布局 frame，供页面内布局回归测试使用。
    func visibleCardFrame(forMediaIndex index: Int) -> CGRect? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.restingFrame
    }

    /// 返回当前已绑定媒体卡片的展示层级，供页面内布局回归测试使用。
    func visibleCardZPosition(forMediaIndex index: Int) -> CGFloat? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.layer.zPosition
    }

    /// 返回当前已绑定媒体卡片的静态扇形变换。
    func visibleCardRestingTransform(forMediaIndex index: Int) -> CGAffineTransform? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }?.restingTransform
    }

    /// 当前参与展示的卡片层数。
    var visibleCardCount: Int {
        cards.lazy.filter { !$0.isHidden }.count
    }

    /// 返回指定媒体当前绑定的 CardView 身份，供重用回归测试使用。
    func visibleCardObjectIdentifier(forMediaIndex index: Int) -> ObjectIdentifier? {
        cards.first { !$0.isHidden && $0.mediaIndex == index }.map(ObjectIdentifier.init)
    }

    private var frontCard: CardView? {
        cards.first { !$0.isHidden && $0.mediaIndex == frontMediaIndex }
    }

    private func finishMove(
        to index: Int,
        in group: IMessageChatMediaGroupAttachment
    ) {
        isAnimating = false
        frontIndexDidChange?(messageID, index)
        UISelectionFeedbackGenerator().selectionChanged()
        updateAccessibilityLabel()
        accessibilityValue = String(
            format: strings?.positionFormat ?? "%d/%d",
            index + 1,
            group.items.count
        )
        let kind = group.items[index].kind.isVideo ? strings?.video : strings?.image
        UIAccessibility.post(
            notification: .announcement,
            argument: [accessibilityValue, kind]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }

    private func bubblePath(in rect: CGRect, tailOnRight: Bool) -> CGPath {
        let tail: CGFloat = 13
        let body = tailOnRight
            ? CGRect(x: 0, y: 0, width: rect.width - tail, height: rect.height)
            : CGRect(x: tail, y: 0, width: rect.width - tail, height: rect.height)
        let path = UIBezierPath(roundedRect: body, cornerRadius: Metrics.cornerRadius)
        let tailPath = UIBezierPath()
        if tailOnRight {
            tailPath.move(to: CGPoint(x: body.maxX - 8, y: body.maxY - 22))
            tailPath.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                controlPoint1: CGPoint(x: body.maxX + 1, y: body.maxY - 9),
                controlPoint2: CGPoint(x: rect.maxX - 6, y: rect.maxY - 1)
            )
            tailPath.addLine(to: CGPoint(x: body.maxX - 7, y: body.maxY - 5))
        } else {
            tailPath.move(to: CGPoint(x: body.minX + 8, y: body.maxY - 22))
            tailPath.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                controlPoint1: CGPoint(x: body.minX - 1, y: body.maxY - 9),
                controlPoint2: CGPoint(x: rect.minX + 6, y: rect.maxY - 1)
            )
            tailPath.addLine(to: CGPoint(x: body.minX + 7, y: body.maxY - 5))
        }
        tailPath.close()
        path.append(tailPath)
        return path.cgPath
    }
}

@available(iOS 26.0, *)
final class IMessageChatMediaBubbleCell: QuickLayoutCollectionViewCell {
    let mediaView = IMessageChatMediaMessageView()
    let deliveryLabel = UILabel()
    private var message: IMessageChatMessagePresentation?
    // 估算行在动画事务内首次配置时，普通 UIView 的 intrinsic size 可能被 10 × 10
    // 占位测量吞掉。把已解析的媒体尺寸直接写进 Cell 布局值，确保第一次自适应测量
    // 就包含完整卡片栈，而不是只留下数量标题的高度。
    private var mediaSize = CGSize(width: 252, height: 252)

    var frontIndexDidChange: ((Int, Int) -> Void)?
    var previewRequested: ((Int, IMessageChatMediaGroupAttachment, Int) -> Void)?

    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [mediaView]
    }

    @LayoutBuilder
    override var body: Layout {
        HStack(spacing: 0) {
            if message?.direction == .outgoing { Spacer() }
            VStack(
                alignment: message?.direction == .outgoing ? .trailing : .leading,
                spacing: 3
            ) {
                mediaView.frame(
                    width: mediaSize.width,
                    height: mediaSize.height
                )
                if message?.deliveryText != nil { deliveryLabel }
            }
            if message?.direction != .outgoing { Spacer() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        deliveryLabel.font = .preferredFont(forTextStyle: .caption2)
        deliveryLabel.adjustsFontForContentSizeCategory = true
        deliveryLabel.textColor = .secondaryLabel
        deliveryLabel.textAlignment = .natural
        isAccessibilityElement = false
        mediaView.frontIndexDidChange = { [weak self] messageID, index in
            self?.frontIndexDidChange?(messageID, index)
        }
        mediaView.previewRequested = { [weak self] messageID, group, index in
            self?.previewRequested?(messageID, group, index)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        _ message: IMessageChatMessagePresentation,
        group: IMessageChatMediaGroupAttachment,
        frontIndex: Int,
        strings: IMessageChatMediaStrings
    ) {
        self.message = message
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        mediaView.configure(
            messageID: message.id,
            direction: message.direction,
            group: group,
            frontIndex: frontIndex,
            strings: strings
        )
        mediaSize = mediaView.intrinsicContentSize
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        mediaView.reset()
        mediaSize = CGSize(width: 252, height: 252)
        setNeedsQuickLayout()
    }
}

@available(iOS 26.0, *)
final class IMessageChatMediaPreviewController:
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout {

    private final class PreviewCell: UICollectionViewCell, UIScrollViewDelegate {
        static let reuseIdentifier = "IMessageChatMediaPreviewCell"
        let scrollView = UIScrollView()
        let imageView = UIImageView()
        let playButton = UIButton(type: .system)
        var playRequested: (() -> Void)?
        private var representedItemID: UUID?
        private var imageTask: Task<Void, Never>?

        override init(frame: CGRect) {
            super.init(frame: frame)
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 4
            scrollView.delegate = self
            contentView.addSubview(scrollView)
            imageView.contentMode = .scaleAspectFit
            scrollView.addSubview(imageView)
            var configuration = UIButton.Configuration.filled()
            configuration.image = UIImage(systemName: "play.fill")
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = .white
            configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
            playButton.configuration = configuration
            playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
            contentView.addSubview(playButton)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            contentView.addGestureRecognizer(doubleTap)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = contentView.bounds
            imageView.frame = scrollView.bounds
            playButton.frame = CGRect(
                x: contentView.bounds.midX - 28,
                y: contentView.bounds.midY - 28,
                width: 56,
                height: 56
            )
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            imageView.image = nil
            playButton.isHidden = true
            playRequested = nil
            representedItemID = nil
            imageTask?.cancel()
            imageTask = nil
            scrollView.zoomScale = 1
        }

        func configure(_ item: IMessageChatMediaItem, play: @escaping () -> Void) {
            representedItemID = item.id
            imageTask?.cancel()
            imageView.image = UIImage(contentsOfFile: item.thumbnailFileURL.path)
            playButton.isHidden = !item.kind.isVideo
            playRequested = play
            guard !item.kind.isVideo else { return }
            let itemID = item.id
            let url = item.originalFileURL
            imageTask = Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) {
                    Self.downsampledCGImage(at: url, maximumPixelSize: 2048)
                }.value
                guard !Task.isCancelled,
                      let self,
                      representedItemID == itemID,
                      let image else { return }
                imageView.image = UIImage(cgImage: image)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc private func playTapped() { playRequested?() }

        @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2, animated: true)
        }

        nonisolated private static func downsampledCGImage(
            at url: URL,
            maximumPixelSize: Int
        ) -> CGImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        }
    }

    private let group: IMessageChatMediaGroupAttachment
    private let initialIndex: Int
    private let strings: IMessageChatMediaStrings
    private let collectionView: UICollectionView
    private weak var activePlayerController: AVPlayerViewController?

    init(
        group: IMessageChatMediaGroupAttachment,
        initialIndex: Int,
        strings: IMessageChatMediaStrings
    ) {
        self.group = group
        self.initialIndex = min(max(0, initialIndex), max(0, group.items.count - 1))
        self.strings = strings
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            PreviewCell.self,
            forCellWithReuseIdentifier: PreviewCell.reuseIdentifier
        )
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)

        let closeButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "xmark")
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.configuration = configuration
        closeButton.accessibilityLabel = strings.close
        closeButton.accessibilityIdentifier = "imessage.media.preview.close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView.bounds.width > 0 else { return }
        let expectedOffset = CGFloat(initialIndex) * collectionView.bounds.width
        if collectionView.contentOffset == .zero, initialIndex > 0 {
            collectionView.setContentOffset(CGPoint(x: expectedOffset, y: 0), animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }
        stopActivePlayer()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        group.items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PreviewCell.reuseIdentifier,
            for: indexPath
        ) as! PreviewCell
        let item = group.items[indexPath.item]
        cell.configure(item) { [weak self] in self?.playVideo(at: indexPath.item) }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    private func playVideo(at index: Int) {
        guard group.items.indices.contains(index), group.items[index].kind.isVideo else { return }
        let playerController = AVPlayerViewController()
        playerController.player = AVPlayer(url: group.items[index].originalFileURL)
        playerController.presentationController?.delegate = self
        activePlayerController = playerController
        present(playerController, animated: true) {
            playerController.player?.play()
        }
    }

    private func stopActivePlayer() {
        activePlayerController?.player?.pause()
        activePlayerController?.player = nil
        activePlayerController = nil
    }

    @objc private func closeTapped() {
        stopActivePlayer()
        dismiss(animated: true)
    }
}

@available(iOS 26.0, *)
extension IMessageChatMediaPreviewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        stopActivePlayer()
    }
}
