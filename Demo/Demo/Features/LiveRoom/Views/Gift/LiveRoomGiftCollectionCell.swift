//
//  LiveRoomGiftCollectionCell.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

private final class LiveRoomGiftItemButton: QuickLayoutButton {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private var imageSide: CGFloat = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        priceLabel.textAlignment = .center
        priceLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .medium)
        priceLabel.adjustsFontSizeToFitWidth = true
        priceLabel.minimumScaleFactor = 0.72
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var body: Layout {
        VStack(spacing: 3) {
            imageView
                .resizable()
                .scaledToFit()
                .frame(width: imageSide, height: imageSide)
            titleLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity)
            priceLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }

    func configure(gift: LiveRoomGift, isSelected: Bool) {
        let color = LiveRoomTheme.giftColor(at: gift.themeIndex)
        imageSide = gift.effectStyle == .celebration ? 23 : 20
        imageView.image = UIImage(systemName: gift.symbolName)
        imageView.tintColor = color
        titleLabel.text = DemoLocalization.text(gift.titleKey)
        priceLabel.text = DemoLocalization.text("liveRoom.gift.price", gift.price)
        priceLabel.textColor = isSelected
            ? .systemYellow
            : UIColor.white.withAlphaComponent(0.42)
        backgroundColor = isSelected
            ? UIColor.white.withAlphaComponent(0.10)
            : .clear
        layer.borderWidth = isSelected
            ? (gift.effectStyle == .celebration ? 2.5 : 2)
            : 0
        layer.borderColor = (isSelected
            ? UIColor.systemYellow
            : UIColor.clear).cgColor
        layer.shadowColor = UIColor.systemYellow.cgColor
        layer.shadowOpacity = isSelected && gift.effectStyle != .trail ? 0.55 : 0
        layer.shadowRadius = gift.effectStyle == .celebration ? 9 : 5
        self.isSelected = isSelected
        accessibilityLabel = DemoLocalization.text(gift.titleKey)
        accessibilityValue = isSelected
            ? DemoLocalization.text("liveRoom.gift.selected")
            : DemoLocalization.text("liveRoom.gift.price", gift.price)
        setNeedsQuickLayout()
    }

    override func quickLayoutButtonStateDidChange(
        _ state: QuickLayoutButtonState
    ) {
        super.quickLayoutButtonStateDidChange(state)
        transform = state.isPressed
            ? CGAffineTransform(scaleX: 0.96, y: 0.96)
            : .identity
        alpha = state.isPressed ? 0.84 : (state.isEnabled ? 1 : 0.56)
    }
}

final class LiveRoomGiftCollectionCell: QuickLayoutCollectionViewCell {

    static let reuseIdentifier = "LiveRoomGiftCollectionCell"

    private let button = LiveRoomGiftItemButton(frame: .zero)
    private var giftDidTap: (() -> Void)?

    override var body: Layout {
        button.resizable()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 礼物网格的列数和 itemSize 由父级 FlowLayout 根据容器宽度统一计算；
        // 固定两个轴，避免 preferredLayoutAttributesFitting 反向改变网格尺寸。
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        button.action = { [weak self] in self?.giftDidTap?() }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        giftDidTap = nil
        button.accessibilityIdentifier = nil
        button.layer.shadowOpacity = 0
    }

    func configure(
        gift: LiveRoomGift,
        isSelected: Bool,
        giftDidTap: @escaping () -> Void
    ) {
        self.giftDidTap = giftDidTap
        button.configure(gift: gift, isSelected: isSelected)
        button.accessibilityIdentifier = "liveRoom.gift.item.\(gift.id)"
        setNeedsQuickLayout()
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomGiftCollectionCellPreview(
    selected: Bool
) -> UIViewController {
    let cell = LiveRoomGiftCollectionCell()
    cell.configure(
        gift: LiveRoomPreviewData.gifts[6],
        isSelected: selected,
        giftDidTap: {}
    )
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            cell.resizable().padding(16)
        }
        .frame(width: 124, height: 124)
    }
}

#Preview("礼物 Item · 未选择") {
    makeLiveRoomGiftCollectionCellPreview(selected: false)
}

#Preview("礼物 Item · 已选择") {
    makeLiveRoomGiftCollectionCellPreview(selected: true)
}
#endif
