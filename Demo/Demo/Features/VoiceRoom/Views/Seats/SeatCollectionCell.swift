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
/// 单个真实 SeatView 展示最新内容；几何与增删动画由 CollectionView Layout 负责。
final class SeatCollectionCell: QuickLayoutCollectionViewCell {

    /// 当前显示的真实麦位视图。
    private let currentSeatView = SeatView(frame: .zero)
    /// 用户选择可交互麦位时调用的回调；参数为当前麦位绑定。
    private var seatDidSelect: ((SeatAssignment) -> Void)?

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        isAccessibilityElement = false
        configureSelection(for: currentSeatView)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 与工程内其他 CollectionView Cell 一样，同步已经物化的内容宿主。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [currentSeatView]
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        currentSeatView.resizable()
    }

    /// 清理点击回调并恢复默认外观。
    override func prepareForReuse() {
        super.prepareForReuse()
        seatDidSelect = nil
        alpha = 1
        transform = .identity
    }

    /// 将条目的麦位展示状态和尺寸等级应用到视图。
    func configure(
        item: SeatCollectionItem,
        metrics: SeatLayoutMetrics,
        seatDidSelect: @escaping (SeatAssignment) -> Void
    ) {
        self.seatDidSelect = seatDidSelect
        configure(
            currentSeatView,
            item: item,
            metrics: metrics
        )
        accessibilityElements = [currentSeatView]
        setNeedsQuickLayout()
    }

    /// 纯内容更新不启动快照或打断正在运行的 Cell 几何动画。
    func refresh(item: SeatCollectionItem, metrics: SeatLayoutMetrics) {
        configure(currentSeatView, item: item, metrics: metrics)
        setNeedsQuickLayout()
    }

    /// 返回当前可见头像在指定视图坐标系中的实时送礼锚点。
    func giftTargetPoint(in view: UIView) -> CGPoint? {
        layoutIfNeeded()
        return currentSeatView.giftTargetPoint(in: view)
    }

    /// 使用当前原生配置的样式展示到达反馈；省略时采用礼物默认样式。
    func playGiftArrival(gift: Gift, color: UIColor, style: GiftEffectStyle? = nil) {
        currentSeatView.playGiftArrival(
            gift: gift,
            color: color,
            style: style
        )
    }

    /// 将条目的麦位展示状态和尺寸等级应用到视图。
    private func configure(
        _ seatView: SeatView,
        item: SeatCollectionItem,
        metrics: SeatLayoutMetrics
    ) {
        seatView.setSizeClass(metrics.sizeClass)
        seatView.configure(presentation: item.slot)
    }

    /// 将麦位视图的选择事件转发给单元格当前回调。
    private func configureSelection(for seatView: SeatView) {
        seatView.seatDidSelect = { [weak self] assignment in
            self?.seatDidSelect?(assignment)
        }
    }
}

#if DEBUG
/// 创建展示指定样式的麦位单元格的预览控制器。
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
