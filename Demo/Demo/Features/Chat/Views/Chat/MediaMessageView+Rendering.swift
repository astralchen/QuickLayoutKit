//
//  MediaMessageView+Rendering.swift
//  Demo
//

import AVKit
import ImageIO
import QuickLayout
import QuickLayoutKit
import UIKit

/// 更新界面内容与展示状态。
extension MediaMessageView {

    /// 为当前可见索引窗口匹配已有卡片，保留相同媒体身份并复用其他卡片。
    func bindCards() {
        guard let group, !group.items.isEmpty else { return }
        let visibleIndices = MediaStackPolicy.visibleIndices(
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
                // 返回上一窗口时，新首项不能抢走后续仍需保留的卡片身份。
                let spareIndex = reusableCards.firstIndex { candidate in
                    !visibleIndices.contains { requiredIndex in
                        candidate.represents(
                            messageID: messageID, groupID: group.id,
                            itemID: group.items[requiredIndex].id
                        )
                    }
                }!
                card = reusableCards.remove(at: spareIndex)
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
        reusableCards.forEach { $0.reset(); $0.isHidden = true }
    }

    /// 将卡片池增减到所需数量，并清理移出窗口的多余卡片。
    func ensureCardCount(_ count: Int) {
        while cards.count < count {
            let card = CardView()
            cards.append(card)
        }
        while cards.count > count {
            let card = cards.removeLast()
            card.reset()
        }
    }

    /// 按封面位置计算 QuickLayout 使用的静止边框，并更新旋转和层级。
    func updateCardGeometry() {
        guard let group, !group.items.isEmpty else { return }
        let isGroup = group.items.count > 1
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let outwardSign: CGFloat = direction == .outgoing
            ? (isRTL ? -1 : 1)
            : (isRTL ? 1 : -1)

        if isGroup {
            let cardY = Metrics.titleHeight + Metrics.titleSpacing
            let scale = min(1, bounds.width / max(1, resolvedSize.width))
            let visibleIndices = MediaStackPolicy.visibleIndices(
                frontIndex: frontMediaIndex,
                itemCount: group.items.count
            )
            for card in cards where !card.isHidden {
                // 收尾阶段仍保留原窗口；离开窗口的卡片也连续移动到新封面背后。
                let position = card.mediaIndex - (visibleIndices.first ?? 0)
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
                let rotationAngle = -physicalSide * Metrics.groupRotationAngle(depth: depth)
                card.mask = nil
                let restingFrame = CGRect(
                    x: CGFloat(visualPosition) * Metrics.groupOffset.x * scale,
                    y: cardY + CGFloat(depth) * Metrics.groupOffset.y * scale,
                    width: Metrics.groupCardSize.width * scale,
                    height: Metrics.groupCardSize.height * scale
                )
                card.restingFrame = restingFrame
                card.restingTransform = CGAffineTransform(
                    rotationAngle: rotationAngle
                )
                card.transform = card.restingTransform
                card.layer.zPosition = CGFloat(30 - depth)
            }
        } else {
            let card = cards[0]
            card.transform = .identity
            card.restingFrame = bounds
            card.restingTransform = .identity
        }
    }

    /// 在卡片完成布局后，将单图轮廓交给框架形状视图生成。
    func updateSingleMask() {
        guard group?.items.count == 1, let card = cards.first else { return }
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let tailOnRight = direction == .outgoing ? !isRTL : isRTL
        card.mask = singleMaskView
        singleMaskView.frame = card.bounds
        singleMaskView.shape = QuickLayoutAnyShape { rect in
            Self.bubblePath(in: rect, tailOnRight: tailOnRight)
        }
        singleMaskView.layoutIfNeeded()
    }

    /// 根据当前封面的媒体类型与时长更新辅助功能描述。
    func updateAccessibilityLabel() {
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
    static func size(for group: MediaGroupAttachment) -> CGSize {
        guard group.items.count == 1, let item = group.items.first else {
            let backCardCount = min(
                group.items.count,
                MediaStackPolicy.maximumVisibleCardCount
            ) - 1
            let angle = Metrics.groupRotationAngle(depth: max(0, backCardCount))
            let rotatedHeight = Metrics.groupCardSize.width * sin(angle)
                + Metrics.groupCardSize.height * cos(angle)
            // 保持封面与卡片偏移不变，只为旋转后向下伸出的边缘预留真实高度。
            // 按整个可见窗口的最大深度测量，切换封面时消息行不会跟着变高变矮。
            let bottomOverflow = ceil(max(0, (rotatedHeight - Metrics.groupCardSize.height) / 2))
            return CGSize(
                width: Metrics.groupCardSize.width
                    + Metrics.groupOffset.x * CGFloat(backCardCount),
                height: Metrics.titleHeight + Metrics.titleSpacing
                    + Metrics.groupCardSize.height
                    + Metrics.groupOffset.y * CGFloat(backCardCount)
                    + bottomOverflow
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

    /// 当前显示在堆叠最前方、响应拖动的卡片视图。
    var frontCard: CardView? {
        cards.first { !$0.isHidden && $0.mediaIndex == frontMediaIndex }
    }

    /// 返回指定区域的媒体气泡轮廓，并按物理方向选择尾部位置。
    nonisolated private static func bubblePath(in rect: CGRect, tailOnRight: Bool) -> CGPath {
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
