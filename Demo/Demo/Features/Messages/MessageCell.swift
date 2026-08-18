//
//  MessageCell.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class MessageContentView: QuickLayoutView {

    let avatarView = UIImageView()
    let titleLabel = UILabel()
    let messageLabel = UILabel()

    override var body: Layout {
        HStack(alignment: .top, spacing: 8) {
            avatarView
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                messageLabel
            }
            Spacer()
        }
        .padding(12)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.backgroundColor = .systemPink.withAlphaComponent(0.2)
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        titleLabel.text = model.title
        messageLabel.text = model.message
        avatarView.image = UIImage(systemName: model.imageName)
        avatarView.tintColor = model.themeColor
        setNeedsQuickLayout()
    }

    func reset() {
        titleLabel.text = nil
        messageLabel.text = nil
        avatarView.image = nil
        avatarView.tintColor = nil
        alpha = 1
        setNeedsQuickLayout()
    }
}

final class MessageCell: QuickLayoutCollectionViewCell {

    let messageContentView = MessageContentView(frame: .zero)
    private var lastDiagnosticLayoutSignature: String?

    // semanticContentAttribute 不会可靠地逐层复制给已物化的 reusable
    // 子视图；声明实际 QuickLayout host，由框架跟随 collection 统一同步。
    override var quickLayoutDirectionViews: [UIView] {
        super.quickLayoutDirectionViews + [messageContentView]
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateVisualState()
        }
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            updateVisualState()
        }
    }

    override var body: Layout {
        ZStack {
            messageContentView
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        updateVisualState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MessageModel) {
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.configure.before",
            cell: self,
            note: "title=\(model.title)"
        )
        messageContentView.configure(model)
        setNeedsQuickLayout()
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.configure.after",
            cell: self,
            note: "title=\(model.title)"
        )
    }

    override func apply(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) {
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.apply.before",
            cell: self,
            layoutAttributes: layoutAttributes
        )
        super.apply(layoutAttributes)
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.apply.after",
            cell: self,
            layoutAttributes: layoutAttributes
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.didMoveToWindow",
            cell: self,
            note: "window=\(window == nil ? "nil" : "attached")"
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let signature = MessageCollectionDirectionDiagnostics.layoutSignature(
            for: self
        )
        guard signature != lastDiagnosticLayoutSignature else { return }
        lastDiagnosticLayoutSignature = signature
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.layoutSubviews.changed",
            cell: self
        )
    }

    override func prepareForReuse() {
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.prepareForReuse.before",
            cell: self
        )
        super.prepareForReuse()
        messageContentView.reset()
        isHighlighted = false
        isSelected = false
        updateVisualState()
        lastDiagnosticLayoutSignature = nil
        MessageCollectionDirectionDiagnostics.logCell(
            "cell.prepareForReuse.after",
            cell: self
        )
    }

    private func updateVisualState() {
        contentView.backgroundColor = isSelected
            ? .tertiarySystemGroupedBackground
            : .secondarySystemGroupedBackground
        messageContentView.alpha = isHighlighted || isSelected ? 0.72 : 1
    }
}

#Preview("简短") {
    previewContent(MessageModel.mockData[0])
}

#Preview("节选") {
    previewContent(MessageModel.mockData[8])
}

private func previewContent(
    _ model: MessageModel
) -> QuickLayoutHostingController {
    let contentView = MessageContentView(frame: .zero)
    contentView.configure(model)
    contentView.backgroundColor = .secondarySystemFill
    contentView.layer.cornerRadius = 8

    return QuickLayoutHostingController {
        contentView
            .padding(16)
    }
}

@MainActor
enum MessageCollectionDirectionDiagnostics {

    private static var sequence = 0

    static func logCollection(
        _ event: String,
        collectionView: UICollectionView?,
        note: String? = nil
    ) {
#if DEBUG
        sequence &+= 1
        let prefix = "[MessageCollectionRTL][\(sequence)][\(event)]"
        print("\(prefix) locale=\(DemoLocalization.localizationController.currentLocale.identifier) \(note ?? "")")

        guard let collectionView else {
            print("\(prefix) collection=nil")
            return
        }

        print("\(prefix) \(viewState("collection", collectionView)) contentOffset=\(NSCoder.string(for: collectionView.contentOffset)) contentSize=\(NSCoder.string(for: collectionView.contentSize)) layout=\(type(of: collectionView.collectionViewLayout))")
        if let superview = collectionView.superview {
            print("\(prefix) \(viewState("collection.superview", superview))")
        }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted()
        print("\(prefix) visible=\(visibleIndexPaths)")
        for indexPath in visibleIndexPaths {
            guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCell else {
                continue
            }
            logCell(
                "\(event).visible[\(indexPath.section),\(indexPath.item)]",
                cell: cell
            )
        }
#endif
    }

    static func logCell(
        _ event: String,
        cell: MessageCell,
        layoutAttributes: UICollectionViewLayoutAttributes? = nil,
        note: String? = nil
    ) {
#if DEBUG
        sequence &+= 1
        let prefix = "[MessageCollectionRTL][\(sequence)][\(event)]"
        let indexPath = cell.enclosingCollectionView?.indexPath(for: cell)
        print("\(prefix) locale=\(DemoLocalization.localizationController.currentLocale.identifier) indexPath=\(String(describing: indexPath)) \(note ?? "")")
        if let layoutAttributes {
            print("\(prefix) \(layoutAttributesState(layoutAttributes))")
        }
        print("\(prefix) \(viewState("cell", cell))")
        print("\(prefix) \(viewState("contentView", cell.contentView))")
        print("\(prefix) \(viewState("messageContent", cell.messageContentView))")
        print("\(prefix) \(viewState("avatar", cell.messageContentView.avatarView))")
        print("\(prefix) \(viewState("title", cell.messageContentView.titleLabel)) text=\(cell.messageContentView.titleLabel.text ?? "nil")")
        print("\(prefix) \(viewState("message", cell.messageContentView.messageLabel))")

        var ancestor = cell.superview
        var depth = 0
        while let view = ancestor, depth < 8 {
            print("\(prefix) \(viewState("ancestor[\(depth)]", view))")
            if view is UICollectionView { break }
            ancestor = view.superview
            depth += 1
        }
#endif
    }

    static func layoutSignature(for cell: MessageCell) -> String {
#if DEBUG
        return [
            cell.semanticContentAttribute.diagnosticName,
            cell.effectiveUserInterfaceLayoutDirection.diagnosticName,
            NSCoder.string(for: cell.frame),
            NSCoder.string(for: cell.transform),
            cell.contentView.semanticContentAttribute.diagnosticName,
            NSCoder.string(for: cell.contentView.transform),
            cell.messageContentView.semanticContentAttribute.diagnosticName,
            cell.messageContentView.effectiveUserInterfaceLayoutDirection.diagnosticName,
            NSCoder.string(for: cell.messageContentView.avatarView.frame),
            NSCoder.string(for: cell.messageContentView.titleLabel.frame),
            NSCoder.string(for: cell.messageContentView.transform),
            NSCoder.string(for: cell.messageContentView.titleLabel.transform),
        ].joined(separator: "|")
#else
        return ""
#endif
    }

#if DEBUG
    private static func viewState(_ name: String, _ view: UIView) -> String {
        let presentationTransform = view.layer.presentation()?.transform
        let windowFrame = view.window.map { window in
            NSCoder.string(for: view.convert(view.bounds, to: window))
        } ?? "nil"
        return "\(name){type=\(type(of: view)),id=\(ObjectIdentifier(view)),semantic=\(view.semanticContentAttribute.diagnosticName),effective=\(view.effectiveUserInterfaceLayoutDirection.diagnosticName),frame=\(NSCoder.string(for: view.frame)),bounds=\(NSCoder.string(for: view.bounds)),windowFrame=\(windowFrame),transform=\(affineState(view.transform)),layer=\(transform3DState(view.layer.transform)),sublayer=\(transform3DState(view.layer.sublayerTransform)),presentation=\(transform3DState(presentationTransform)),geometryFlipped=\(view.layer.isGeometryFlipped)}"
    }

    private static func layoutAttributesState(
        _ attributes: UICollectionViewLayoutAttributes
    ) -> String {
        "attributes{frame=\(NSCoder.string(for: attributes.frame)),center=\(NSCoder.string(for: attributes.center)),size=\(NSCoder.string(for: attributes.size)),transform=\(affineState(attributes.transform)),transform3D=\(transform3DState(attributes.transform3D)),alpha=\(attributes.alpha),hidden=\(attributes.isHidden),zIndex=\(attributes.zIndex)}"
    }

    private static func affineState(_ transform: CGAffineTransform) -> String {
        String(
            format: "[%.3f %.3f %.3f %.3f %.3f %.3f]",
            transform.a,
            transform.b,
            transform.c,
            transform.d,
            transform.tx,
            transform.ty
        )
    }

    private static func transform3DState(_ transform: CATransform3D?) -> String {
        guard let transform else { return "nil" }
        return String(
            format: "[m11=%.3f,m12=%.3f,m21=%.3f,m22=%.3f,m31=%.3f,m32=%.3f,m41=%.3f,m42=%.3f,m44=%.3f]",
            transform.m11,
            transform.m12,
            transform.m21,
            transform.m22,
            transform.m31,
            transform.m32,
            transform.m41,
            transform.m42,
            transform.m44
        )
    }
#endif
}

private extension UIView {

    var enclosingCollectionView: UICollectionView? {
        var candidate = superview
        while let view = candidate {
            if let collectionView = view as? UICollectionView {
                return collectionView
            }
            candidate = view.superview
        }
        return nil
    }
}

extension UIUserInterfaceLayoutDirection {

    var diagnosticName: String {
        switch self {
        case .leftToRight:
            return "LTR"
        case .rightToLeft:
            return "RTL"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}

private extension UISemanticContentAttribute {

    var diagnosticName: String {
        switch self {
        case .unspecified:
            return "unspecified"
        case .playback:
            return "playback"
        case .spatial:
            return "spatial"
        case .forceLeftToRight:
            return "forceLTR"
        case .forceRightToLeft:
            return "forceRTL"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}
