//
//  MediaMessageView+CardView.swift
//  Demo
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

/// 定义媒体堆叠使用的内部卡片视图。
extension MediaMessageView {

    /// 持有单个媒体缩略图并校验异步加载身份的可复用卡片。
    final class CardView: UIView {
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
            _ item: MediaItem,
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
}
