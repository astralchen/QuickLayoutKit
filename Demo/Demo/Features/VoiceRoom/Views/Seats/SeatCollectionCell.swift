//
//  SeatCollectionCell.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// CollectionView 复用麦位单元格。
///
/// 几何过渡只短暂保留 source/destination 两个真实麦位 View 做交叉淡变；完成后
/// 立即收敛为一个 View，不创建位图快照，也不保存第二份业务状态。
final class SeatCollectionCell: QuickLayoutCollectionViewCell {

    private var currentSeatView = SeatView(frame: .zero)
    private var destinationSeatView: SeatView?
    private var currentItem: SeatCollectionItem?
    private var destinationItem: SeatCollectionItem?
    private var seatDidSelect: ((SeatAssignment) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        isAccessibilityElement = false
        configureSelection(for: currentSeatView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var body: Layout {
        ZStack {
            currentSeatView.resizable()
            if let destinationSeatView {
                destinationSeatView.resizable()
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        destinationSeatView?.removeFromSuperview()
        destinationSeatView = nil
        currentItem = nil
        destinationItem = nil
        seatDidSelect = nil
        alpha = 1
        transform = .identity
    }

    func configure(
        item: SeatCollectionItem,
        metrics: SeatLayoutMetrics,
        seatDidSelect: @escaping (SeatAssignment) -> Void
    ) {
        self.seatDidSelect = seatDidSelect
        currentItem = item
        destinationItem = nil
        destinationSeatView?.removeFromSuperview()
        destinationSeatView = nil
        configure(
            currentSeatView,
            item: item,
            metrics: metrics
        )
        accessibilityElements = [currentSeatView]
        setNeedsQuickLayout()
    }

    func prepareTransition(
        to item: SeatCollectionItem,
        metrics: SeatLayoutMetrics
    ) {
        destinationItem = item
        let destinationView = SeatView(frame: .zero)
        configureSelection(for: destinationView)
        configure(destinationView, item: item, metrics: metrics)
        destinationView.alpha = 0
        destinationSeatView?.removeFromSuperview()
        destinationSeatView = destinationView
        accessibilityElements = []
        setNeedsQuickLayout()
        layoutIfNeeded()
    }

    /// 将不改变几何身份的数据更新合并到当前或目标麦位内容。
    func refresh(
        item: SeatCollectionItem,
        metrics: SeatLayoutMetrics
    ) {
        if let destinationSeatView {
            destinationItem = item
            configure(destinationSeatView, item: item, metrics: metrics)
        } else {
            currentItem = item
            configure(currentSeatView, item: item, metrics: metrics)
        }
        setNeedsQuickLayout()
    }

    func animateToDestination() {
        guard let destinationSeatView else { return }
        currentSeatView.alpha = 0
        destinationSeatView.alpha = 1
    }

    func completeTransition() {
        guard let destinationSeatView, let destinationItem else {
            currentSeatView.alpha = 1
            accessibilityElements = [currentSeatView]
            return
        }
        currentSeatView.removeFromSuperview()
        currentSeatView = destinationSeatView
        currentSeatView.alpha = 1
        currentItem = destinationItem
        self.destinationSeatView = nil
        self.destinationItem = nil
        accessibilityElements = [currentSeatView]
        setNeedsQuickLayout()
    }

    func giftTargetPoint(in view: UIView) -> CGPoint? {
        layoutIfNeeded()
        guard let pointInCell = visibleGiftTargetPointInCell() else {
            return nil
        }
        let sourceLayer = layer.presentation() ?? layer
        let destinationLayer = view.layer.presentation() ?? view.layer
        return sourceLayer.convert(pointInCell, to: destinationLayer)
    }

    /// 使用当前原生配置的样式展示到达反馈；省略时采用礼物默认样式。
    func playGiftArrival(gift: Gift, color: UIColor, style: GiftEffectStyle? = nil) {
        (destinationSeatView ?? currentSeatView).playGiftArrival(
            gift: gift,
            color: color,
            style: style
        )
    }

    private func configure(
        _ seatView: SeatView,
        item: SeatCollectionItem,
        metrics: SeatLayoutMetrics
    ) {
        seatView.setSizeClass(metrics.sizeClass)
        seatView.configure(presentation: item.slot)
    }

    private func configureSelection(for seatView: SeatView) {
        seatView.seatDidSelect = { [weak self] assignment in
            self?.seatDidSelect?(assignment)
        }
    }

    /// 内容交叉淡变时按两个真实 SeatView 的可见度插值头像锚点。
    ///
    /// 直接选 destination 会在动画开始时跳到仍完全透明的大头像中心；按
    /// presentation opacity 插值后，飞行礼物与用户当前实际看到的头像保持连续。
    private func visibleGiftTargetPointInCell() -> CGPoint? {
        guard
            let currentPoint = giftTargetPointInCell(for: currentSeatView),
            let destinationSeatView,
            let destinationPoint = giftTargetPointInCell(
                for: destinationSeatView
            )
        else {
            return giftTargetPointInCell(for: currentSeatView)
        }
        let currentOpacity = CGFloat(
            currentSeatView.layer.presentation()?.opacity
                ?? currentSeatView.layer.opacity
        )
        let destinationOpacity = CGFloat(
            destinationSeatView.layer.presentation()?.opacity
                ?? destinationSeatView.layer.opacity
        )
        let totalOpacity = currentOpacity + destinationOpacity
        guard totalOpacity > 0.001 else { return destinationPoint }
        let progress = destinationOpacity / totalOpacity
        return CGPoint(
            x: currentPoint.x
                + (destinationPoint.x - currentPoint.x) * progress,
            y: currentPoint.y
                + (destinationPoint.y - currentPoint.y) * progress
        )
    }

    private func giftTargetPointInCell(
        for seatView: SeatView
    ) -> CGPoint? {
        guard let point = seatView.giftTargetPointInBounds() else {
            return nil
        }
        return seatView.convert(point, to: self)
    }
}

#if DEBUG
@MainActor
private func makeSeatCollectionCellPreview(
    seat: SeatAssignment,
    styleID: SeatVisualStyleID
) -> UIViewController {
    let metrics = SeatLayoutMetrics.regular
    let cell = SeatCollectionCell()
    let slot = SeatSlotPresentation(
        slotID: seat.slotID,
        position: seat.position,
        assignment: seat.isOccupied ? seat : nil,
        role: .roomSeat(at: seat.position),
        styleID: styleID,
        isVisible: true,
        interaction: seat.isOccupied ? .showUserCard : .none
    )
    let size = SeatView.fittingSize(
        styleID: styleID,
        sizeClass: metrics.sizeClass,
        width: metrics.standardSeatWidth
    )
    cell.configure(
        item: SeatCollectionItem(slot: slot),
        metrics: metrics,
        seatDidSelect: { _ in }
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            cell.resizable().frame(width: size.width, height: size.height)
        }
        .padding(16)
        .frame(width: size.width + 32, height: size.height + 32)
    }
}

@available(iOS 17.0, *)
#Preview("麦位 Cell · 已上麦") {
    makeSeatCollectionCellPreview(
        seat: VoiceRoomPreviewData.seats[2],
        styleID: .standardGuest
    )
}

@available(iOS 17.0, *)
#Preview("麦位 Cell · 空麦") {
    makeSeatCollectionCellPreview(
        seat: VoiceRoomPreviewData.seats[5],
        styleID: .standardGuest
    )
}
#endif
