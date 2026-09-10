//
//  IMessageChatMediaViews.swift
//  Demo
//
//  媒体草稿、已发送媒体消息与全屏预览使用的 UIKit 视图。
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

/// 照片草稿、媒体消息与全屏预览共用的本地化文字。
nonisolated struct IMessageChatMediaStrings: Equatable, Sendable {
    /// 照片选择入口的标题。
    let photo: String
    /// 媒体项目数量的格式字符串，使用整数占位符。
    let itemsFormat: String
    /// 静态图片的辅助功能类型名称。
    let image: String
    /// 动态图像或 Live Photo 的辅助功能类型名称。
    let animatedImage: String
    /// 视频的辅助功能类型名称。
    let video: String
    /// 包含视频时长的格式字符串，使用字符串占位符。
    let videoDurationFormat: String
    /// 媒体导入期间显示或朗读的状态文字。
    let importing: String
    /// 删除媒体草稿操作的标签。
    let remove: String
    /// 播放视频操作的标签。
    let play: String
    /// 打开全屏媒体预览的辅助功能提示。
    let openPreview: String
    /// 关闭全屏预览操作的标签。
    let close: String
    /// 尝试越过媒体集合首项时朗读的提示。
    let firstItem: String
    /// 尝试越过媒体集合末项时朗读的提示。
    let lastItem: String
    /// 媒体当前位置与总数的格式字符串，使用两个整数占位符。
    let positionFormat: String
}

/// Composer 媒体预览项的尺寸规则。
///
/// 设计图固定预览高度，并让宽度跟随附件像素比例。极窄或极宽资源会被限制在
/// 合理范围，避免删除按钮相互覆盖或单个横图占满整条输入栏。
nonisolated enum IMessageChatMediaDraftLayoutPolicy {
    /// 媒体草稿预览项的固定高度，单位为点。
    static let itemHeight: CGFloat = 120
    /// 媒体草稿预览项的最小宽度，单位为点。
    static let minimumWidth: CGFloat = 80
    /// 媒体草稿预览项的最大宽度，单位为点。
    static let maximumWidth: CGFloat = 160

    /// 按媒体宽高比计算固定高度的草稿尺寸，并限制宽度范围。
    ///
    /// 像素尺寸缺失、非有限或非正数时使用最小宽度。
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

/// 按消息身份保存媒体堆叠封面位置，使状态跨单元格复用保留的对象。
@MainActor
final class IMessageChatMediaStackStateStore {
    /// 消息标识符到当前封面索引的映射。
    private var indices: [Int: Int] = [:]

    /// 返回指定消息的封面索引，并将结果限制在当前媒体数量内。
    func index(for messageID: Int, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return min(max(0, indices[messageID] ?? 0), itemCount - 1)
    }

    /// 保存经边界修正的封面索引；媒体集合为空时移除记录。
    func setIndex(_ index: Int, for messageID: Int, itemCount: Int) {
        guard itemCount > 0 else {
            indices.removeValue(forKey: messageID)
            return
        }
        indices[messageID] = min(max(0, index), itemCount - 1)
    }

    /// 仅保留仍存在于时间线中的消息封面记录。
    func retainMessages(_ messageIDs: Set<Int>) {
        indices = indices.filter { messageIDs.contains($0.key) }
    }
}

/// 层叠媒体的纯展示算法。所有结果都只基于索引计算，不改变附件数组。
nonisolated enum IMessageChatMediaStackPolicy {
    /// 媒体堆叠同时保留的最大卡片数量。
    static let maximumVisibleCardCount = 5

    /// 返回从当前封面开始、再接回集合起点的完整媒体索引顺序。
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

    /// 返回手势速度是否以水平方向为主，用于避免抢占时间线纵向滚动。
    static func isHorizontalPan(velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y) * 1.2
    }

    /// 根据水平位移或速度返回相邻目标索引。
    ///
    /// 媒体不足两项、没有有效方向或将越过集合边界时返回 `nil`。
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

    /// 返回拖动距离或同向速度是否达到切换封面的提交阈值。
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

/// 按选择顺序显示可删除媒体草稿的横向滚动视图。
@available(iOS 26.0, *)
final class IMessageChatMediaDraftStripView: UIView {
    /// 媒体草稿条带的布局常量。
    private enum Metrics {
        /// 相邻媒体草稿卡片之间的间距，单位为点。
        static let spacing: CGFloat = 4
    }

    /// 承载媒体草稿条带的水平滚动容器。
    let scrollView = UIScrollView()
    /// 按序排列媒体草稿项目的内容视图。
    private let contentView = UIView()
    /// 按稳定身份复用的媒体草稿项目视图。
    private var itemViews: [UUID: DraftItemView] = [:]
    /// 当前媒体草稿的本地化文字；尚未配置时为 `nil`。
    private var strings: IMessageChatMediaStrings?

    /// 用户请求删除草稿项目时调用的闭包，参数为项目身份。
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

    /// 使用指定初始边框创建 `IMessageChatMediaDraftStripView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        accessibilityIdentifier = "imessage.composer.mediaStrip"
    }

    /// 不支持从归档创建 `IMessageChatMediaDraftStripView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据当前边界更新 `IMessageChatMediaDraftStripView` 的子视图布局与图层几何。
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

    /// 按草稿身份增删和复用项目视图，应用有序内容及本地化标签。
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

    /// 显示单个媒体草稿缩略图、导入状态和删除入口的视图。
    private final class DraftItemView: UIView {
        /// 显示当前媒体图像的图像视图。
        let imageView = UIImageView()
        /// 媒体原件尚在导入时显示的活动指示器。
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        /// 标示草稿为视频的图像视图。
        let videoBadge = UIImageView()
        /// 显示音频或视频时长的标签。
        let durationLabel = UILabel()
        /// 动态图像标记的背景容器。
        let animatedBadgeView = UIView()
        /// 标示动态图像或 Live Photo 的符号视图。
        let animatedBadgeImageView = UIImageView()
        /// 删除当前媒体草稿项目的按钮。
        let removeButton = IMessageChatDraftRemoveButton(frame: .zero)
        /// 当前项目在选择序列中的零基索引。
        var order = 0
        /// 根据媒体宽高比或导入占位计算的项目布局尺寸。
        var itemSize = IMessageChatMediaDraftLayoutPolicy.itemSize(for: nil)
        /// 用户点击本项目删除按钮时调用的闭包。
        var removeRequested: (() -> Void)?

        /// 使用指定初始边框创建 `DraftItemView`，并配置其子视图和默认外观。
        ///
        /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

            removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
            addSubview(removeButton)
        }

        /// 不支持从归档创建 `DraftItemView`。
        ///
        /// 请使用代码初始化方法创建此对象。
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 根据当前边界更新 `DraftItemView` 的子视图布局与图层几何。
        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
            activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
            removeButton.frame = CGRect(x: bounds.maxX - 44, y: 0, width: 44, height: 44)
            animatedBadgeView.frame = CGRect(x: 6, y: 6, width: 28, height: 28)
            animatedBadgeImageView.frame = animatedBadgeView.bounds.insetBy(dx: 5, dy: 5)
            videoBadge.frame = CGRect(x: 8, y: bounds.maxY - 26, width: 20, height: 18)
            durationLabel.sizeToFit()
            durationLabel.frame.origin = CGPoint(
                x: bounds.maxX - durationLabel.bounds.width - 7,
                y: bounds.maxY - durationLabel.bounds.height - 6
            )
        }

        /// 应用媒体导入状态、缩略图、序号及可访问的类型和位置说明。
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

        /// 将删除按钮事件转发给项目删除回调。
        @objc private func removeTapped() {
            removeRequested?()
        }

        /// 将秒数格式化为分钟和两位秒数的视频时长文本。
        private static func durationText(_ duration: TimeInterval) -> String {
            let seconds = max(0, Int(duration.rounded()))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }
}

/// 显示单张媒体或可横向切换的媒体堆叠的消息视图。
@available(iOS 26.0, *)
final class IMessageChatMediaMessageView: UIView, UIGestureRecognizerDelegate {
    /// 单张媒体气泡与多媒体堆叠共用的布局尺寸。
    private enum Metrics {
        /// 单张媒体允许的最大宽度，单位为点。
        static let singleMaximumWidth: CGFloat = 252
        /// 单张媒体允许的最大高度，单位为点。
        static let singleMaximumHeight: CGFloat = 360
        /// 单张媒体布局的最小边长约束，单位为点。
        static let singleMinimumEdge: CGFloat = 120
        /// 媒体堆叠中每张卡片的基准尺寸。
        static let groupCardSize = CGSize(width: 216, height: 300)
        /// 媒体堆叠相邻层的水平与垂直偏移量。
        static let groupOffset = CGPoint(x: 8, y: 6)
        /// 媒体数量标题行的高度，单位为点。
        static let titleHeight: CGFloat = 24
        /// 媒体数量标题与堆叠卡片之间的间距，单位为点。
        static let titleSpacing: CGFloat = 8
        /// 媒体卡片的圆角半径，单位为点。
        static let cornerRadius: CGFloat = 22
    }

    /// 持有单个媒体缩略图并校验异步加载身份的可复用卡片。
    private final class CardView: UIView {
        /// 绑定消息、媒体组、项目及封面位置的图像加载身份。
        struct BindingIdentity: Equatable, Sendable {
            /// 卡片当前所属消息的稳定标识符。
            let messageID: Int
            /// 卡片当前所属媒体组的稳定标识符。
            let groupID: UUID
            /// 卡片当前显示的媒体项目标识符。
            let itemID: UUID
            /// 本次绑定时的媒体组封面索引。
            let frontIndex: Int
        }

        /// 显示当前媒体图像的图像视图。
        let imageView = UIImageView()
        /// 视频播放符号背后的模糊材质容器。
        let playBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        /// 覆盖在视频缩略图上的播放符号。
        let playImageView = UIImageView(image: UIImage(systemName: "play.fill"))
        /// 卡片对应媒体项目在原始附件数组中的索引。
        var mediaIndex = 0
        /// 卡片结束拖动后恢复的基准边框。
        var restingFrame: CGRect = .zero
        /// 卡片结束拖动后恢复的堆叠变换。
        var restingTransform: CGAffineTransform = .identity
        /// 当前缩略图加载绑定的完整身份，用于丢弃旧请求结果。
        private var representedIdentity: BindingIdentity?
        /// 后台准备缩略图的可取消任务。
        private var imageTask: Task<Void, Never>?

        /// 返回卡片是否仍绑定指定消息、媒体组与媒体项目。
        func represents(
            messageID: Int,
            groupID: UUID,
            itemID: UUID
        ) -> Bool {
            representedIdentity?.messageID == messageID
                && representedIdentity?.groupID == groupID
                && representedIdentity?.itemID == itemID
        }

        /// 使用指定初始边框创建 `CardView`，并配置其子视图和默认外观。
        ///
        /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

        /// 不支持从归档创建 `CardView`。
        ///
        /// 请使用代码初始化方法创建此对象。
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 根据当前边界更新 `CardView` 的子视图布局与图层几何。
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

        /// 绑定媒体项目及完整加载身份，并在异步图像返回时校验身份后显示。
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
            // 同一媒体在堆叠中移动时保留现有图片；新请求只在完整绑定身份仍匹配时回填。
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

        /// 取消图像任务并清空绑定内容、动画及复用状态。
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

    /// 显示媒体组总项目数的标签。
    let itemCountLabel = UILabel()
    /// 与项目数量配套显示的媒体网格符号。
    private let itemCountIcon = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill"))
    /// 裁剪单张媒体气泡轮廓的形状遮罩。
    private let singleMaskLayer = CAShapeLayer()
    /// 用于显示有限媒体窗口的可复用卡片集合。
    private var cards: [CardView] = []
    /// 驱动媒体封面切换的水平拖动手势。
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    /// 打开被点击媒体项目预览的轻点手势。
    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

    /// 当前媒体消息的稳定标识符。
    private var messageID = 0
    /// 当前消息的接收或发出方向，用于确定气泡外观与语义对齐。
    private var direction: IMessageChatDirection = .incoming
    /// 当前显示的有序媒体组；未配置或重置后为 `nil`。
    private var group: IMessageChatMediaGroupAttachment?
    /// 当前媒体内容的本地化文字集合。
    private var strings: IMessageChatMediaStrings?
    /// 当前位于堆叠最前方的媒体项目索引。
    private(set) var frontMediaIndex = 0
    /// 指示封面切换动画尚未结束的布尔值，用于限制手势重入。
    private var isAnimating = false
    /// 根据当前单张媒体或堆叠内容计算的固有尺寸。
    private var resolvedSize = CGSize(width: 252, height: 252)

    /// 封面位置改变后调用的闭包，参数依次为消息身份与媒体索引。
    var frontIndexDidChange: ((Int, Int) -> Void)?
    /// 用户请求预览媒体时调用的闭包，参数为消息身份、媒体组与起始索引。
    var previewRequested: ((Int, IMessageChatMediaGroupAttachment, Int) -> Void)?

    /// 使用指定初始边框创建 `IMessageChatMediaMessageView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

    /// 不支持从归档创建 `IMessageChatMediaMessageView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `IMessageChatMediaMessageView` 在当前内容与布局约束下的固有尺寸。
    override var intrinsicContentSize: CGSize { resolvedSize }

    /// 根据当前边界更新 `IMessageChatMediaMessageView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCards()
    }

    /// 绑定有序媒体组与封面位置，更新卡片数量、固有尺寸和辅助功能信息。
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

    /// 清空媒体绑定、标题、遮罩和辅助功能状态，并重置全部卡片。
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

    /// 通过辅助功能递增操作切换到下一媒体项目。
    override func accessibilityIncrement() {
        move(to: frontMediaIndex + 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// 通过辅助功能递减操作切换到上一媒体项目。
    override func accessibilityDecrement() {
        move(to: frontMediaIndex - 1, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// 仅在有多个项目、没有切换动画且手势以水平运动为主时允许拖动。
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let group,
              group.items.count > 1,
              !isAnimating else { return false }
        let velocity = panGesture.velocity(in: self)
        return IMessageChatMediaStackPolicy.isHorizontalPan(velocity: velocity)
    }

    /// 按卡片层级解析点击的媒体项目，并请求从该位置打开预览。
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let group else { return }
        let location = gesture.location(in: self)
        let index = cards
            .sorted { $0.layer.zPosition > $1.layer.zPosition }
            .first(where: { !$0.isHidden && $0.frame.contains(location) })?
            .mediaIndex ?? frontMediaIndex
        previewRequested?(messageID, group, index)
    }

    /// 根据拖动阶段更新前景卡片变换，达到阈值时切换，否则恢复原位。
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

    /// 切换到指定媒体索引，并根据动画与减弱动态效果设置选择过渡方式。
    ///
    /// 越界请求恢复卡片并朗读首尾提示；切换不会改变附件原始顺序。
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

    /// 将前景卡片恢复到静止变换，按需使用弹簧动画。
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

    /// 为当前可见索引窗口匹配已有卡片，保留相同媒体身份并复用其他卡片。
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

    /// 将卡片池增减到所需数量，并清理移出窗口的多余卡片。
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

    /// 按封面位置布置卡片边框、旋转、层级及单图遮罩。
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
            let scale = min(1, bounds.width / max(1, resolvedSize.width))
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
                    x: CGFloat(visualPosition) * Metrics.groupOffset.x * scale,
                    y: cardY + CGFloat(depth) * Metrics.groupOffset.y * scale,
                    width: Metrics.groupCardSize.width * scale,
                    height: Metrics.groupCardSize.height * scale
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

    /// 根据当前封面的媒体类型与时长更新辅助功能描述。
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

    /// 根据媒体数量和原始宽高比返回单图气泡或堆叠视图的尺寸。
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

    /// 当前显示在堆叠最前方、响应拖动的卡片视图。
    private var frontCard: CardView? {
        cards.first { !$0.isHidden && $0.mediaIndex == frontMediaIndex }
    }

    /// 完成封面切换，解除动画状态并发布索引和辅助功能位置更新。
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

    /// 返回指定区域的媒体气泡轮廓，并按物理方向选择尾部位置。
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

/// 在时间线中显示媒体内容、发送状态和保存入口的自适应单元格。
@available(iOS 26.0, *)
final class IMessageChatMediaBubbleCell: QuickLayoutCollectionViewCell {
    /// 显示单图气泡或可切换媒体堆叠的视图。
    let mediaView = IMessageChatMediaMessageView()
    /// 显示发送进度、失败入口及送达文本的状态视图。
    let deliveryStatusView = IMessageChatDeliveryStatusView()
    /// 状态视图中用于显示本地化送达文本的标签。
    var deliveryLabel: UILabel { deliveryStatusView.label }
    /// 用于将收到的附件保存到系统位置的按钮。
    let saveButton = IMessageChatAttachmentSaveButton()
    /// 用户请求保存当前附件时调用的闭包。
    var saveRequested: (() -> Void)?
    /// 指示当前布局是否为附件保存入口保留空间的布尔值。
    private var showsSaveButton = false
    /// 媒体组标题区域预留的高度，单位为点。
    private var mediaHeaderHeight: CGFloat = 0
    /// 当前布局允许的媒体内容最大宽度，单位为点。
    private var maximumMediaWidth: CGFloat = 252
    /// 当前绑定的消息展示模型；未配置或复用清理后为 `nil`。
    private var message: IMessageChatMessagePresentation?
    // 估算行在动画事务内首次配置时，普通 UIView 的 intrinsic size 可能被 10 × 10
    // 占位测量吞掉。把已解析的媒体尺寸直接写进 Cell 布局值，确保第一次自适应测量
    // 就包含完整卡片栈，而不是只留下数量标题的高度。
    /// 媒体内容经过宽度限制后采用的布局尺寸。
    private var mediaSize = CGSize(width: 252, height: 252)

    /// 媒体封面变化时向时间线转发消息身份和索引的闭包。
    var frontIndexDidChange: ((Int, Int) -> Void)?
    /// 向页面请求媒体全屏预览的闭包，携带消息、媒体组和起始索引。
    var previewRequested: ((Int, IMessageChatMediaGroupAttachment, Int) -> Void)?

    /// 需要随单元格同步更新布局方向的内容视图。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [mediaView]
    }

    /// 定义 `IMessageChatMediaBubbleCell` 的布局层级、间距和对齐方式。
    @LayoutBuilder
    override var body: Layout {
        HStack(spacing: 0) {
            if message?.direction == .outgoing { Spacer() }
            VStack(
                alignment: message?.direction == .outgoing ? .trailing : .leading,
                spacing: 3
            ) {
                HStack(spacing: 8) {
                    mediaView.frame(width: mediaSize.width, height: mediaSize.height)
                    if showsSaveButton {
                        saveButton.frame(width: 44, height: 44).padding(.top, mediaHeaderHeight)
                    }
                }
                if message?.deliveryText != nil { deliveryStatusView }
            }
            if message?.direction != .outgoing { Spacer() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// 使用指定初始边框创建 `IMessageChatMediaBubbleCell`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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
        saveButton.addAction(UIAction { [weak self] _ in self?.saveRequested?() }, for: .touchUpInside)
        isAccessibilityElement = false
        mediaView.frontIndexDidChange = { [weak self] messageID, index in
            self?.frontIndexDidChange?(messageID, index)
        }
        mediaView.previewRequested = { [weak self] messageID, group, index in
            self?.previewRequested?(messageID, group, index)
        }
    }

    /// 不支持从归档创建 `IMessageChatMediaBubbleCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 配置媒体消息的内容、封面位置、本地化文字与附件保存状态。
    func configure(
        _ message: IMessageChatMessagePresentation,
        group: IMessageChatMediaGroupAttachment,
        frontIndex: Int,
        strings: IMessageChatMediaStrings,
        saveState: IMessageChatAttachmentSaveState = .available
    ) {
        self.message = message
        showsSaveButton = IMessageChatAttachmentSavePolicy.showsButton(for: message)
        mediaHeaderHeight = group.items.count > 1 ? 32 : 0
        saveButton.configure(saveState, isMedia: true)
        deliveryStatusView.configure(message)
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        mediaView.configure(
            messageID: message.id,
            direction: message.direction,
            group: group,
            frontIndex: frontIndex,
            strings: strings
        )
        resolveMediaSize()
        setNeedsQuickLayout()
    }

    /// 根据列表提供的宽度更新内容宽度限制，并返回自适应高度的布局属性。
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        maximumMediaWidth = max(1, attributes.size.width - 24 - (showsSaveButton ? 52 : 0))
        resolveMediaSize()
        setNeedsQuickLayout()
        return super.preferredLayoutAttributesFitting(attributes)
    }

    /// 根据当前媒体固有尺寸与单元格宽度限制计算媒体布局大小。
    private func resolveMediaSize() {
        let natural = mediaView.intrinsicContentSize
        let scale = min(1, maximumMediaWidth / max(1, natural.width))
        mediaSize = CGSize(width: natural.width * scale,
                           height: mediaHeaderHeight + (natural.height - mediaHeaderHeight) * scale)
    }

    /// 为复用清理 `IMessageChatMediaBubbleCell` 的内容与临时状态。
    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        showsSaveButton = false
        saveRequested = nil
        saveButton.configure(.hidden, isMedia: true)
        deliveryStatusView.configure(nil)
        deliveryStatusView.retryRequested = nil
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        mediaView.reset()
        mediaSize = CGSize(width: 252, height: 252)
        setNeedsQuickLayout()
    }
}

/// 分页预览媒体组，并通过系统播放器播放视频的全屏控制器。
@available(iOS 26.0, *)
final class IMessageChatMediaPreviewController:
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout {

    /// 支持图片缩放和视频播放入口的媒体预览单元格。
    private final class PreviewCell: UICollectionViewCell, UIScrollViewDelegate {
        /// 注册和出队媒体预览单元格时使用的复用标识符。
        static let reuseIdentifier = "IMessageChatMediaPreviewCell"
        /// 支持一至四倍图像缩放的滚动容器。
        let scrollView = UIScrollView()
        /// 显示当前媒体图像的图像视图。
        let imageView = UIImageView()
        /// 用于触发播放操作的按钮。
        let playButton = UIButton(type: .system)
        /// 用户点击视频播放入口时调用的闭包。
        var playRequested: (() -> Void)?
        /// 当前显示的媒体项目身份，用于拒绝复用前的图像加载结果。
        private var representedItemID: UUID?
        /// 异步降采样原始图像的可取消任务。
        private var imageTask: Task<Void, Never>?

        /// 使用指定初始边框创建 `PreviewCell`，并配置其子视图和默认外观。
        ///
        /// - Parameter frame: 在父视图坐标系中指定的初始边框。
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

        /// 不支持从归档创建 `PreviewCell`。
        ///
        /// 请使用代码初始化方法创建此对象。
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 根据当前边界更新 `PreviewCell` 的子视图布局与图层几何。
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

        /// 为复用清理 `PreviewCell` 的内容与临时状态。
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

        /// 先显示媒体缩略图，再为图片异步加载降采样原件；视频显示播放入口。
        ///
        /// 结果返回时检查项目身份和取消状态，避免复用后显示旧图片。
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

        /// 返回由滚动视图执行缩放的图像视图。
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// 将视频播放按钮事件转发给页面回调。
        @objc private func playTapped() { playRequested?() }

        /// 响应双击，在原始比例与两倍缩放之间切换。
        @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2, animated: true)
        }

        /// 从原始文件创建应用方向变换的降采样图像。
        ///
        /// - Parameters:
        ///   - url: 本地图片文件 URL。
        ///   - maximumPixelSize: 输出缩略图最长边的像素上限。
        /// - Returns: 解码后的图像；无法读取或解码时为 `nil`。
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

    /// 当前预览的有序媒体组。
    private let group: IMessageChatMediaGroupAttachment
    /// 首次布局时应显示的媒体索引，初始化时限制在有效范围内。
    private let initialIndex: Int
    /// 预览按钮与辅助功能使用的本地化文字。
    private let strings: IMessageChatMediaStrings
    /// 按水平方向整页滚动的媒体集合视图。
    private let collectionView: UICollectionView
    /// 当前展示的系统视频播放器控制器；弱引用由展示层级管理其生命周期。
    private weak var activePlayerController: AVPlayerViewController?
    /// 与音频控制器共享的页面播放互斥协调器。
    private let playbackCoordinator: IMessageChatPlaybackCoordinator
    /// 当前视频预览获取和释放播放所有权的稳定令牌。
    private let playbackOwner = UUID()

    /// 创建媒体组的全屏预览控制器。
    ///
    /// - Parameters:
    ///   - group: 保持原始选择顺序的媒体组。
    ///   - initialIndex: 起始媒体索引，超出范围时会修正。
    ///   - strings: 预览界面使用的本地化文字。
    ///   - playbackCoordinator: 页面共享的播放协调器；省略时创建独立实例。
    init(
        group: IMessageChatMediaGroupAttachment,
        initialIndex: Int,
        strings: IMessageChatMediaStrings,
        playbackCoordinator: IMessageChatPlaybackCoordinator? = nil
    ) {
        self.group = group
        self.playbackCoordinator = playbackCoordinator ?? IMessageChatPlaybackCoordinator()
        self.initialIndex = min(max(0, initialIndex), max(0, group.items.count - 1))
        self.strings = strings
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    /// 不支持从归档创建 `IMessageChatMediaPreviewController`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 配置黑色背景、分页集合视图与关闭按钮。
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

    /// 在集合视图获得有效宽度后应用指定起始媒体位置。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView.bounds.width > 0 else { return }
        let expectedOffset = CGFloat(initialIndex) * collectionView.bounds.width
        if collectionView.contentOffset == .zero, initialIndex > 0 {
            collectionView.setContentOffset(CGPoint(x: expectedOffset, y: 0), animated: false)
        }
    }

    /// 在预览页面真正关闭后停止并解除当前视频播放器。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }
        stopActivePlayer()
    }

    /// 返回当前媒体组中的项目数量。
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        group.items.count
    }

    /// 出队并配置对应媒体项目的预览单元格，绑定视频播放请求。
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

    /// 返回与集合视图可见区域等大的分页单元格尺寸。
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    /// 取得页面播放所有权后展示指定视频的系统播放器。
    ///
    /// 展示完成回调会校验播放器身份及应用前台状态，再开始播放。
    private func playVideo(at index: Int) {
        guard group.items.indices.contains(index), group.items[index].kind.isVideo,
              presentedViewController == nil else { return }
        stopActivePlayer()
        playbackCoordinator.acquire(owner: playbackOwner) { [weak self] in
            self?.stopActivePlayer(dismiss: true)
        }
        // 先由同一个协调器停止音频，再配置视频会话。
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            playbackCoordinator.release(owner: playbackOwner)
            return
        }
        let playerController = AVPlayerViewController()
        playerController.allowsPictureInPicturePlayback = false
        playerController.player = AVPlayer(url: group.items[index].originalFileURL)
        activePlayerController = playerController
        present(playerController, animated: true) { [weak self, weak playerController] in
            guard let self, let playerController,
                  self.activePlayerController === playerController,
                  UIApplication.shared.applicationState != .background else { return }
            playerController.presentationController?.delegate = self
            playerController.player?.play()
        }
    }

    /// 在返回预览页面时清理旧播放器，并重新订阅应用后台暂停事件。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 包含播放器的“完成”按钮及交互式关闭；回到媒体预览后不遗留声音。
        stopActivePlayer()
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pauseActiveVideo),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// 应用进入后台时暂停当前视频播放器。
    @objc private func pauseActiveVideo() {
        activePlayerController?.player?.pause()
    }

    /// 暂停并解除系统播放器，按当前令牌释放播放所有权。
    ///
    /// - Parameter dismiss: 是否同时无动画关闭仍在展示的播放器界面。
    private func stopActivePlayer(dismiss: Bool = false) {
        let controller = activePlayerController
        controller?.player?.pause()
        // 连同原生播放控件的 player 一起移除，旧视频不能重新启动后叠加音频。
        controller?.player = nil
        activePlayerController = nil
        playbackCoordinator.release(owner: playbackOwner)
        if dismiss, controller?.presentingViewController != nil {
            controller?.dismiss(animated: false)
        }
    }

    /// 停止当前视频并关闭全屏媒体预览。
    @objc private func closeTapped() {
        stopActivePlayer()
        dismiss(animated: true)
    }
}

/// 在系统播放器交互式关闭后清理视频播放状态。
@available(iOS 26.0, *)
extension IMessageChatMediaPreviewController: UIAdaptivePresentationControllerDelegate {
    /// 系统展示控制器关闭后停止并解除活动播放器。
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        stopActivePlayer()
    }
}
