import QuickLayoutKit
import UIKit

@MainActor
final class AlertExampleTextView: QuickLayoutScrollView {
    static var plainText: String {
        document.map { "\($0.heading)\n\n\($0.body)" }.joined(separator: "\n\n")
    }

    private weak var presentingView: UIView?
    private let sections: QuickLayoutView

    init(presentingView: UIView, usesMessageStyle: Bool = false) {
        self.presentingView = presentingView
        let document = Self.document
        let headingFont = UIFont.preferredFont(forTextStyle: usesMessageStyle ? .subheadline : .headline)
        let bodyFont = UIFont.preferredFont(forTextStyle: usesMessageStyle ? .subheadline : .body)
        let paragraphSpacing = usesMessageStyle ? bodyFont.lineHeight : 8
        let sectionSpacing = usesMessageStyle ? bodyFont.lineHeight : 20
        let textColor: UIColor = usesMessageStyle ? .secondaryLabel : .label
        let labels = document.enumerated().map { index, section in
            let heading = LocalizedLabel()
            heading.font = headingFont
            heading.textColor = textColor
            heading.adjustsFontForContentSizeCategory = true
            heading.numberOfLines = 0
            heading.text = section.heading
            heading.accessibilityTraits.insert(.header)

            let body = LocalizedLabel()
            body.font = bodyFont
            body.textColor = textColor
            body.adjustsFontForContentSizeCategory = true
            body.numberOfLines = 0
            body.text = section.body
            if index == document.count - 1 { body.accessibilityIdentifier = "alerts.text.end" }
            return (heading: heading, body: body)
        }
        sections = QuickLayoutView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                for section in labels {
                    VStack(alignment: .leading, spacing: paragraphSpacing) {
                        section.heading.resizable(axis: .horizontal)
                        section.body.resizable(axis: .horizontal)
                    }
                }
            }
            .padding(.horizontal, usesMessageStyle ? 14 : 0)
        }
        super.init(frame: .zero)
        accessibilityIdentifier = "alerts.text.content"
        contentInsetAdjustmentBehavior = .never
    }

    override var body: Layout {
        sections.resizable(axis: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: viewportHeightLimit)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let height = sections.sizeThatFits(
            CGSize(width: size.width, height: .greatestFiniteMagnitude)
        ).height
        return CGSize(width: size.width, height: min(ceil(height), size.height, viewportHeightLimit))
    }

    private var viewportHeightLimit: CGFloat {
        let host = presentingView?.window ?? presentingView
        guard let host else { return 300 }
        let height = host.bounds.inset(by: host.safeAreaInsets).height
        guard height > 0 else { return 300 }
        // 给标题和操作区留出空间，长文只在自己的视口内滚动。
        return min(300, floor(height * 0.42))
    }

    private static var document: [(heading: String, body: String)] {
        ["displays", "headings", "position", "textSize", "foldable", "end"].map { section in
            let key = "demo.alertExamples.document." + section
            return (Localization.text(key + ".heading"), Localization.text(key + ".body"))
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("长文阅读") {
    AlertExamplesViewController.preview(.text)
}
#endif
