//
//  MediaDraftStripView.swift
//  Demo
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

/// Composer 媒体预览项的尺寸规则。
///
/// 设计图固定预览高度，并让宽度跟随附件像素比例。极窄或极宽资源会被限制在
/// 合理范围，避免删除按钮相互覆盖或单个横图占满整条输入栏。
nonisolated enum MediaDraftLayoutPolicy {
    /// 按 iPhone 16 Pro 参考图换算的媒体草稿高度，单位为点。
    static let itemHeight: CGFloat = 156
    /// 媒体草稿预览项的最小宽度，单位为点。
    static let minimumWidth: CGFloat = 80
    /// 媒体草稿预览项的最大宽度，单位为点。
    static let maximumWidth: CGFloat = 208

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

/// 按选择顺序显示可删除媒体草稿的横向滚动视图。
final class MediaDraftStripView: UIView {
    /// 媒体草稿条带的布局常量。
    private enum Metrics {
        /// 相邻媒体草稿卡片之间的间距，单位为点。
        static let spacing: CGFloat = 6
    }

    /// 承载媒体草稿条带的水平滚动容器。
    let scrollView = UIScrollView()
    /// 按序排列媒体草稿项目的内容视图。
    private let contentView = UIView()
    /// 按稳定身份复用的媒体草稿项目视图。
    private var itemViews: [UUID: DraftItemView] = [:]
    /// 当前媒体草稿的本地化文字；尚未配置时为 `nil`。
    private var strings: MediaStrings?

    /// 用户请求删除草稿项目时调用的闭包，参数为项目身份。
    var removeRequested: ((UUID) -> Void)?
    /// 请求打开已完成导入的照片草稿。
    var previewRequested: ((UUID) -> Void)?
    /// 按草稿稳定身份返回当前缩略图来源。
    func previewSource(id: UUID) -> UIView? { itemViews[id] }


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

    /// 使用指定初始边框创建 `MediaDraftStripView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        accessibilityIdentifier = "imessage.composer.mediaStrip"
    }

    /// 不支持从归档创建 `MediaDraftStripView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据当前边界更新 `MediaDraftStripView` 的子视图布局与图层几何。
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
            height: MediaDraftLayoutPolicy.itemHeight
        )
        scrollView.contentSize = contentView.bounds.size
    }

    /// 按草稿身份增删和复用项目视图，应用有序内容及本地化标签。
    func configure(
        _ draft: MediaDraftPresentation?,
        strings: MediaStrings
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
            itemView.previewRequested = { [weak self] in self?.previewRequested?(item.id) }
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
        /// 视频时长的深色半透明底衬，使白色文字在明亮封面上保持可读。
        let durationBackgroundView = UIView()
        /// 显示视频时长的标签。
        let durationLabel = UILabel()
        /// 动态图像标记的背景容器。
        let animatedBadgeView = UIView()
        /// 标示动态图像或 Live Photo 的符号视图。
        let animatedBadgeImageView = UIImageView()
        /// 删除当前媒体草稿项目的按钮。
        let removeButton = DraftRemoveButton(frame: .zero)
        /// 当前项目在选择序列中的零基索引。
        var order = 0
        /// 根据媒体宽高比或导入占位计算的项目布局尺寸。
        var itemSize = MediaDraftLayoutPolicy.itemSize(for: nil)
        /// 用户点击本项目删除按钮时调用的闭包。
        var removeRequested: (() -> Void)?
        /// 已就绪项目的打开动作；导入期间不触发。
        var previewRequested: (() -> Void)?
        private var isReady = false


        /// 使用指定初始边框创建 `DraftItemView`，并配置其子视图和默认外观。
        ///
        /// - Parameter frame: 在父视图坐标系中指定的初始边框。
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.cornerRadius = 14
            layer.cornerCurve = .continuous
            backgroundColor = .secondarySystemFill

            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = true
            imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(previewTapped)))
            addSubview(imageView)

            activityIndicator.hidesWhenStopped = true
            addSubview(activityIndicator)

            videoBadge.image = UIImage(systemName: "video.fill")
            videoBadge.tintColor = .white
            videoBadge.contentMode = .scaleAspectFit
            addSubview(videoBadge)

            durationBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            durationBackgroundView.layer.cornerRadius = 5
            durationBackgroundView.layer.cornerCurve = .continuous
            durationBackgroundView.isUserInteractionEnabled = false
            addSubview(durationBackgroundView)

            durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            durationLabel.textColor = .white
            addSubview(durationLabel)

            animatedBadgeView.backgroundColor = .white
            animatedBadgeView.layer.cornerRadius = 13
            animatedBadgeView.layer.cornerCurve = .continuous
            animatedBadgeImageView.image = UIImage(
                systemName: "livephoto",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 18,
                    weight: .regular
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
            animatedBadgeView.frame = CGRect(x: 6, y: 4, width: 26, height: 26)
            animatedBadgeImageView.frame = animatedBadgeView.bounds.insetBy(dx: 4, dy: 4)
            videoBadge.frame = CGRect(x: 12, y: bounds.maxY - 24, width: 17, height: 12)
            durationLabel.sizeToFit()
            durationLabel.frame.origin = CGPoint(
                x: bounds.maxX - durationLabel.bounds.width - 8,
                y: bounds.maxY - durationLabel.bounds.height - 10
            )
            durationBackgroundView.frame = durationLabel.frame.insetBy(dx: -4, dy: -2)
        }

        /// 应用媒体导入状态、缩略图、序号及可访问的类型和位置说明。
        func configure(
            _ item: MediaDraftItemPresentation,
            order: Int,
            totalCount: Int,
            strings: MediaStrings
        ) {
            self.order = order
            imageView.image = nil
            videoBadge.isHidden = true
            durationLabel.isHidden = true
            durationBackgroundView.isHidden = true
            animatedBadgeView.isHidden = true
            itemSize = MediaDraftLayoutPolicy.itemSize(for: nil)
            isReady = false
            switch item.content {
            case .importing:
                activityIndicator.startAnimating()
                accessibilityLabel = strings.importing
            case .ready(let media):
                isReady = true
                imageView.isAccessibilityElement = true
                imageView.accessibilityTraits = .button
                imageView.accessibilityIdentifier = "imessage.composer.media.preview.\(item.id.uuidString)"
                imageView.accessibilityLabel = strings.openPreview
                activityIndicator.stopAnimating()
                imageView.image = UIImage(contentsOfFile: media.thumbnailFileURL.path)
                itemSize = MediaDraftLayoutPolicy.itemSize(
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
                    durationBackgroundView.isHidden = false
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
        /// 打开当前媒体，保留独立删除按钮的命中区域。
        @objc private func previewTapped() { if isReady { previewRequested?() } }
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
