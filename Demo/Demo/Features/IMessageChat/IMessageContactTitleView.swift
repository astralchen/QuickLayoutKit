//
//  IMessageContactTitleView.swift
//  Demo
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class IMessageContactTitleView: QuickLayoutView {

    private static let maximumTitleWidth: CGFloat = 220
    private static let navigationBarHeight: CGFloat = 44

    let avatarView = UIImageView()
    let nameLabel = UILabel()
    let subtitleLabel = UILabel()

    override var body: Layout {
        HStack(spacing: 7) {
            avatarView.resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                nameLabel
                subtitleLabel
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarView.tintColor = .systemGray
        avatarView.contentMode = .scaleAspectFit

        nameLabel.text = "Alex"
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textAlignment = .natural
        nameLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .natural
        subtitleLabel.lineBreakMode = .byTruncatingTail
        isAccessibilityElement = true
    }

    override var intrinsicContentSize: CGSize {
        fittingTitleSize(
            in: CGSize(
                width: Self.maximumTitleWidth,
                height: Self.navigationBarHeight
            )
        )
    }

    /// 导航栏可能在标题仍为零尺寸时先询问 fitting size；此时使用受控上限向
    /// QuickLayout 提案，避免首次测量只得到头像或空内容宽度。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        fittingTitleSize(
            in: CGSize(
                width: size.width > 0
                    ? min(size.width, Self.maximumTitleWidth)
                    : Self.maximumTitleWidth,
                height: size.height > 0
                    ? min(size.height, Self.navigationBarHeight)
                    : Self.navigationBarHeight
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(subtitle: String) {
        subtitleLabel.text = subtitle
        accessibilityLabel = "Alex, \(subtitle)"
        invalidateIntrinsicContentSize()
        setNeedsQuickLayout()
        superview?.setNeedsLayout()
    }

    private func fittingTitleSize(in proposal: CGSize) -> CGSize {
        let measuredSize = super.sizeThatFits(proposal)
        return CGSize(
            width: min(Self.maximumTitleWidth, ceil(measuredSize.width)),
            height: min(
                Self.navigationBarHeight,
                max(30, ceil(measuredSize.height))
            )
        )
    }
}

#if DEBUG
@MainActor
private func makeIMessageContactTitlePreview(
    direction: UIUserInterfaceLayoutDirection
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemBackground
    let titleView = IMessageContactTitleView(frame: .zero)
    titleView.semanticContentAttribute = direction == .rightToLeft
        ? .forceRightToLeft
        : .forceLeftToRight
    titleView.configure(subtitle: IMessageChatPreviewData.contactSubtitle)
    titleView.sizeToFit()
    return QuickLayoutHostingController {
        ZStack {
            backgroundView.resizable()
            titleView.frame(width: 220, height: 44)
        }
        .frame(width: 280, height: 88)
    }
}

#Preview("联系人导航标题") {
    makeIMessageContactTitlePreview(direction: .leftToRight)
}

#Preview("联系人导航标题 · RTL") {
    makeIMessageContactTitlePreview(direction: .rightToLeft)
}
#endif
