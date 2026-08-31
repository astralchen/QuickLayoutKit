//
//  LiveRoomSeatCollectionCell.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// CollectionView 复用麦位单元格。
///
/// 几何过渡只短暂保留 source/destination 两个真实麦位 View 做交叉淡变；完成后
/// 立即收敛为一个 View，不创建位图快照，也不保存第二份业务状态。
final class LiveRoomSeatCollectionCell: QuickLayoutCollectionViewCell {

    private var currentSeatView = LiveRoomSeatView(frame: .zero)
    private var destinationSeatView: LiveRoomSeatView?
    private var currentItem: LiveRoomSeatCollectionItem?
    private var destinationItem: LiveRoomSeatCollectionItem?
    private var seatDidSelect: ((LiveRoomSeatAssignment) -> Void)?

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
        item: LiveRoomSeatCollectionItem,
        metrics: LiveRoomSeatLayoutMetrics,
        seatDidSelect: @escaping (LiveRoomSeatAssignment) -> Void
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
        to item: LiveRoomSeatCollectionItem,
        metrics: LiveRoomSeatLayoutMetrics
    ) {
        destinationItem = item
        let destinationView = LiveRoomSeatView(frame: .zero)
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
        item: LiveRoomSeatCollectionItem,
        metrics: LiveRoomSeatLayoutMetrics
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

    func playGiftArrival(gift: LiveRoomGift, color: UIColor) {
        (destinationSeatView ?? currentSeatView).playGiftArrival(
            gift: gift,
            color: color
        )
    }

    private func configure(
        _ seatView: LiveRoomSeatView,
        item: LiveRoomSeatCollectionItem,
        metrics: LiveRoomSeatLayoutMetrics
    ) {
        seatView.setPresentation(metrics.presentation)
        seatView.configure(
            assignment: item.slot.assignment,
            presentation: item.slot
        )
    }

    private func configureSelection(for seatView: LiveRoomSeatView) {
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
        for seatView: LiveRoomSeatView
    ) -> CGPoint? {
        guard let point = seatView.giftTargetPointInBounds() else {
            return nil
        }
        return seatView.convert(point, to: self)
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomSeatCollectionCellPreview(
    seat: LiveRoomSeat,
    styleID: LiveRoomSeatVisualStyleID
) -> UIViewController {
    let metrics = LiveRoomSeatLayoutMetrics.regular
    let cell = LiveRoomSeatCollectionCell()
    let slot = LiveRoomSeatSlotPresentation(
        slotID: seat.slotID,
        position: seat.position,
        assignment: seat.isOccupied ? seat : nil,
        role: seat.position.rawValue == 0
            ? .host
            : .guest(index: seat.position.rawValue),
        styleID: styleID,
        isVisible: true,
        interaction: seat.isOccupied ? .showUserCard : .none
    )
    let size = LiveRoomSeatView.fittingSize(
        styleID: styleID,
        presentation: metrics.presentation,
        width: metrics.standardSeatWidth
    )
    cell.configure(
        item: LiveRoomSeatCollectionItem(slot: slot),
        metrics: metrics,
        seatDidSelect: { _ in }
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            cell.resizable().frame(width: size.width, height: size.height)
        }
        .padding(16)
        .frame(width: size.width + 32, height: size.height + 32)
    }
}

#Preview("麦位 Cell · 已上麦") {
    makeLiveRoomSeatCollectionCellPreview(
        seat: LiveRoomPreviewData.seats[2],
        styleID: .standardGuest
    )
}

#Preview("麦位 Cell · 空麦") {
    makeLiveRoomSeatCollectionCellPreview(
        seat: LiveRoomPreviewData.seats[5],
        styleID: .standardGuest
    )
}
#endif
