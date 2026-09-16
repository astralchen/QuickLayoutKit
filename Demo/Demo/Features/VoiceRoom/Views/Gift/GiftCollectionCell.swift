//
//  GiftCollectionCell.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示单个礼物图标、名称、单价和选择状态的按钮。
private final class GiftItemButton: QuickLayoutButton {

    /// 显示组件符号图像的视图。
    private let imageView = UIImageView()
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示单份礼物金币价格的标签。
    private let priceLabel = UILabel()
    /// 礼物图标的边长，单位为点。
    private var imageSide: CGFloat = 20

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
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

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 应用礼物显示内容，并更新选中状态和辅助功能信息。
    func configure(gift: Gift, isSelected: Bool) {
        let color = VoiceRoomTheme.giftColor(at: gift.themeIndex)
        imageSide = gift.effectStyle == .celebration ? 23 : 20
        imageView.image = UIImage(systemName: gift.symbolName)
        imageView.tintColor = color
        titleLabel.text = gift.localizedTitle
        priceLabel.text = Localization.text("liveRoom.gift.price", gift.price)
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
        accessibilityLabel = gift.localizedTitle
        accessibilityValue = isSelected
            ? Localization.text("liveRoom.gift.selected")
            : Localization.text("liveRoom.gift.price", gift.price)
        setNeedsQuickLayout()
    }

    /// 在按钮状态变化时刷新对应的文字、颜色和交互外观。
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

/// 将礼物选择按钮接入集合视图复用机制的单元格。
final class GiftCollectionCell: QuickLayoutCollectionViewCell {

    /// 集合视图注册和复用此单元格时使用的标识。
    static let reuseIdentifier = "VoiceRoomGiftCollectionCell"

    /// 承载礼物内容和点击操作的按钮。
    private let button = GiftItemButton(frame: .zero)
    /// 用户点击此礼物条目时调用的回调。
    private var giftDidTap: (() -> Void)?

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        button.resizable()
    }

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        // 礼物网格的列数和 itemSize 由父级 FlowLayout 根据容器宽度统一计算；
        // 固定两个轴，避免 preferredLayoutAttributesFitting 反向改变网格尺寸。
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        button.action = { [weak self] in self?.giftDidTap?() }
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 复用前清除旧点击回调、辅助功能标识和选中阴影。
    override func prepareForReuse() {
        super.prepareForReuse()
        giftDidTap = nil
        button.accessibilityIdentifier = nil
        button.layer.shadowOpacity = 0
    }

    /// 更新礼物内容及选择外观，并替换该条目的点击回调。
    func configure(
        gift: Gift,
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
/// 创建展示指定选择状态的礼物单元格的预览控制器。
@MainActor
private func makeGiftCollectionCellPreview(
    selected: Bool
) -> UIViewController {
    let cell = GiftCollectionCell()
    cell.configure(
        gift: VoiceRoomPreviewData.gifts[6],
        isSelected: selected,
        giftDidTap: {}
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            cell.resizable().padding(16)
        }
        .frame(width: 124, height: 124)
    }
}

@available(iOS 17.0, *)
#Preview("礼物 Item · 未选择") {
    makeGiftCollectionCellPreview(selected: false)
}

@available(iOS 17.0, *)
#Preview("礼物 Item · 已选择") {
    makeGiftCollectionCellPreview(selected: true)
}
#endif
