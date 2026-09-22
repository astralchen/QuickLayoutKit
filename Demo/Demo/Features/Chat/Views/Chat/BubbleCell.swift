//
//  BubbleCell.swift
//  Demo
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 在时间线中显示文本气泡和发送状态的自适应单元格。
final class BubbleCell: QuickLayoutCollectionViewCell {
    /// 随 Cell 复用重置的菜单辅助功能绑定。
    let messageMenu = MessageMenuAccessibility()


    /// 呈现消息正文与收发方向外观的文本气泡视图。
    let bubbleView = BubbleView(frame: .zero)
    /// 显示发送进度、失败入口及送达文本的状态视图。
    let deliveryStatusView = DeliveryStatusView()
    /// 状态视图中用于显示本地化送达文本的标签。
    var deliveryLabel: UILabel { deliveryStatusView.label }
    /// 当前绑定的消息展示模型；未配置或复用清理后为 `nil`。
    private var message: MessagePresentation?
    /// 当前布局允许的消息气泡最大宽度，单位为点。
    private var maximumBubbleWidth: CGFloat = 280

    /// 需要随单元格同步更新布局方向的内容视图。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [bubbleView]
    }

    /// 定义 `BubbleCell` 的布局层级、间距和对齐方式。
    @LayoutBuilder
    override var body: Layout {
        HStack(spacing: 0) {
            if message?.direction == .outgoing {
                Spacer()
            }
            VStack(
                alignment: message?.direction == .outgoing
                    ? .trailing
                    : .leading,
                spacing: 3
            ) {
                bubbleView
                    .frame(
                        maxWidth: maximumBubbleWidth,
                        alignment: message?.direction == .outgoing
                            ? .trailing
                            : .leading
                    )
                if message?.deliveryText != nil {
                    deliveryStatusView
                }
            }
            if message?.direction != .outgoing {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    /// 使用指定初始边框创建 `BubbleCell`，并配置其子视图和默认外观。
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
        isAccessibilityElement = false
    }

    /// 不支持从归档创建 `BubbleCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Cell 的移动由列表动画负责，内部气泡不能从复用或估算尺寸展开后再显示正文。
    override func layoutSubviews() {
        UIView.performWithoutAnimation {
            super.layoutSubviews()
            bubbleView.layoutIfNeeded()
            deliveryStatusView.layoutIfNeeded()
        }
    }

    /// 根据列表提供的宽度更新内容宽度限制，并返回自适应高度的布局属性。
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let resolvedWidth = max(140, layoutAttributes.size.width * 0.75)
        if abs(resolvedWidth - maximumBubbleWidth) > 0.5 {
            maximumBubbleWidth = resolvedWidth
            setNeedsQuickLayout()
        }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// 绑定文本消息，更新气泡、发送状态和单元格布局。
    func configure(_ message: MessagePresentation) {
        self.message = message
        bubbleView.configure(message)
        deliveryStatusView.configure(message)
        deliveryLabel.text = message.deliveryText
        deliveryLabel.accessibilityLabel = message.deliveryText
        setNeedsQuickLayout()
    }

    /// 为复用清理 `BubbleCell` 的内容与临时状态。
    override func prepareForReuse() {
        super.prepareForReuse()
        messageMenu.reset()
        message = nil
        bubbleView.reset()
        deliveryStatusView.configure(nil)
        deliveryStatusView.retryRequested = nil
        deliveryLabel.text = nil
        deliveryLabel.accessibilityLabel = nil
        setNeedsQuickLayout()
    }
}
