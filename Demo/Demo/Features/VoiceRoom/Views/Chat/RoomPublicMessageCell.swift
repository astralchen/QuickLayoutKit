import QuickLayout
import QuickLayoutKit
import UIKit

/// 富文本中的徽标、昵称和正文共享基线及换行，避免长昵称挤压正文。
final class RoomPublicMessageCell: QuickLayoutCollectionViewCell {
    private let messageLabel = UILabel()
    private var presentation: RoomPublicMessagePresentation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 集合单元格的 fixedSize 表示测量时使用列表给定宽度；fullyFlexible 会按无限宽测量。
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .natural
        messageLabel.adjustsFontForContentSizeCategory = true
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { return nil }

    override var body: Layout {
        messageLabel
            .resizable(axis: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    func configure(_ presentation: RoomPublicMessagePresentation, identifier: String) {
        self.presentation = presentation
        messageLabel.accessibilityIdentifier = identifier
        messageLabel.accessibilityLabel = presentation.accessibilityText
        renderText()
        setNeedsQuickLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            renderText()
        }
    }

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
        if reason.contains(.layoutDirection) { renderText() }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = ceil(sizeThatFits(CGSize(width: attributes.size.width, height: .greatestFiniteMagnitude)).height)
        return attributes
    }

    private func renderText() {
        guard let presentation else { return }
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14), compatibleWith: traitCollection
        )
        let nameColor = UIColor(red: 0.63, green: 0.81, blue: 1, alpha: 1)
        let gold = UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 1)
        let lavender = UIColor(red: 0.81, green: 0.72, blue: 1, alpha: 1)
        let bodyColor: UIColor = switch presentation.style {
        case .text: .white.withAlphaComponent(0.94)
        case .system, .gift: gold
        case .arrival: lavender
        }
        contentView.backgroundColor = switch presentation.style {
        case .system: gold.withAlphaComponent(0.08)
        case .gift: UIColor.systemPink.withAlphaComponent(0.09)
        case .text, .arrival: .clear
        }
        let text = NSMutableAttributedString(string: "")
        if let badge = presentation.badge {
            let badgeFont = UIFont.systemFont(ofSize: font.pointSize * 0.71, weight: .semibold)
            let size = (badge as NSString).size(withAttributes: [.font: badgeFont])
            let image = UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4)).image { _ in
                UIColor.systemPink.withAlphaComponent(0.9).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4)), cornerRadius: 4).fill()
                (badge as NSString).draw(at: CGPoint(x: 4, y: 2), withAttributes: [.font: badgeFont, .foregroundColor: UIColor.white])
            }
            append(image: image, to: text, font: font)
        }
        if let name = presentation.symbolName,
           let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: font.pointSize - 1))?.withTintColor(bodyColor, renderingMode: .alwaysOriginal) {
            append(image: image, to: text, font: font)
        }
        for run in presentation.runs {
            text.append(NSAttributedString(string: run.text, attributes: [
                .font: run.kind == .accent ? UIFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font,
                .foregroundColor: run.kind == .name ? nameColor : bodyColor,
            ]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        // 富文本开头可能是中性的附件；按容器方向对齐，文字内部仍使用 Unicode 双向排版。
        paragraph.alignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        messageLabel.font = font
        messageLabel.attributedText = text
    }

    private func append(image: UIImage, to text: NSMutableAttributedString, font: UIFont) {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: " ", attributes: [.font: font]))
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("公屏消息 · 富文本") {
    let cell = RoomPublicMessageCell(frame: .zero)
    cell.configure(RoomPublicMessagePresentation(message: VoiceRoomPreviewData.messages[1]), identifier: "preview.message")
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            cell.resizable(axis: .horizontal).fixedSize(axis: .vertical).padding(14)
        }.frame(width: 390, height: 120)
    }
}
#endif
