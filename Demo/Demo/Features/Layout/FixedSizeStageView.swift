import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 保持卡片和滚动视图实例稳定；测量读数仅用于展示，不参与尺寸计算。
final class FixedSizeStageView: QuickLayoutView {
    let carouselScrollView = QuickLayoutScrollView(.horizontal, showsIndicators: false)
    let cards = (0..<4).map { FixedSizeLabCardView(index: $0) }
    private let stageTitleLabel = FixedSizeText.make(style: .subheadline, color: .secondaryLabel)
    private let stageValueLabel = FixedSizeText.make(style: .subheadline, color: .systemIndigo)
    private let rulerLine = UIView()
    private let metricsLabel = FixedSizeText.make(style: .caption1, color: .secondaryLabel)
    private var selectedScenario = FixedSizeScenario.equal
    private var needsLeadingPosition = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        carouselScrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        carouselScrollView.accessibilityIdentifier = "fixedSize.carousel"
        carouselScrollView.alwaysBounceHorizontal = true
        metricsLabel.accessibilityIdentifier = "fixedSize.metrics"
        rulerLine.backgroundColor = .separator
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        // 父布局会先改变视口并触发 UIKit 对偏移的调整，必须在此前判断是否位于起点。
        let previous = carouselGeometry
        let wasAtLeading = abs(carouselScrollView.contentOffset.x - previous.leadingOffset) < 1
        super.layoutSubviews()
        carouselScrollView.layoutIfNeeded()
        let current = carouselGeometry
        if current.width > 0, current.contentWidth > 0,
           !carouselScrollView.isTracking, !carouselScrollView.isDecelerating,
           needsLeadingPosition || (wasAtLeading && previous != current) {
            needsLeadingPosition = false
            carouselScrollView.scrollTo(.leading, animated: false)
        }
        updateMeasurements()
    }

    /// 只记录影响水平起点的几何值，垂直滚动和内容高度变化不会重置横向位置。
    private var carouselGeometry: CarouselGeometry {
        let scroll = carouselScrollView
        return CarouselGeometry(
            width: scroll.bounds.width,
            contentWidth: scroll.contentSize.width,
            leftInset: scroll.adjustedContentInset.left,
            rightInset: scroll.adjustedContentInset.right,
            isRTL: scroll.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }

    /// 本轮布局前后的水平滚动范围，不保留历史视图或测量缓存。
    private struct CarouselGeometry: Equatable {
        let width: CGFloat
        let contentWidth: CGFloat
        let leftInset: CGFloat
        let rightInset: CGFloat
        let isRTL: Bool

        var leadingOffset: CGFloat {
            isRTL ? max(-leftInset, contentWidth - width + rightInset) : -leftInset
        }
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stageTitleLabel
                Spacer()
                stageValueLabel
            }
            .safeAreaPadding(.horizontal, 20)
            carousel
            VStack(alignment: .leading, spacing: 8) {
                rulerLine.resizable(axis: .horizontal).frame(height: 1)
                metricsLabel
            }
            .safeAreaPadding(.horizontal, 20)
        }
    }

    func selectScenario(_ scenario: FixedSizeScenario) {
        guard selectedScenario != scenario else { return }
        selectedScenario = scenario
        setNeedsQuickLayout()
    }

    func reloadLocalizedContent() {
        stageTitleLabel.text = Localization.text("fixedSize.stage")
        for (index, card) in cards.enumerated() {
            card.configure(
                title: Localization.text("fixedSize.card.\(index).title"),
                detail: Localization.text("fixedSize.card.\(index).detail")
            )
        }
        setNeedsQuickLayout()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        let semantic = direction.appLayoutDirection.semanticContentAttribute
        semanticContentAttribute = semantic
        carouselScrollView.semanticContentAttribute = semantic
        cards.forEach {
            $0.semanticContentAttribute = semantic
            $0.setNeedsQuickLayout()
        }
        needsLeadingPosition = true
        setNeedsQuickLayout()
    }

    private var row: StackElement {
        HStack(alignment: .top, spacing: 16) {
            ForEach(cards) { card in
                cardLayout(card)
                    .containerRelativeFrame(.horizontal) { width, _ in
                        min(300, width * 0.78)
                    }
            }
        }
    }

    private func cardLayout(_ card: FixedSizeLabCardView) -> Layout {
        if selectedScenario == .natural {
            return card.fixedSize(axis: .vertical)
        }
        return card.resizable(axis: .vertical)
            .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var carousel: Layout {
        ScrollView(carouselScrollView, .horizontal, showsIndicators: false) {
            if selectedScenario == .equal {
                // 接收者保持 StackElement 类型，命中 QuickLayoutKit 的专用重载。
                row.fixedSize(axis: .vertical)
            } else if selectedScenario == .fill {
                // 横向滚动视图先按内容测量自然高度；在内容容器上明确提供有限高度。
                row.frame(height: 420)
            } else {
                row
            }
        }
        .resizable(axis: .horizontal)
        .contentMargins(.horizontal, 20)
    }

    private func updateMeasurements() {
        let heights = cards.map { $0.bounds.height }
        guard heights.allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
        let summary = String(format: "%.0f pt", carouselScrollView.bounds.height)
        let values = heights.enumerated().map { index, height in
            String(format: "%02d · %.0f pt", index + 1, height)
        }.joined(separator: "    ")
        guard stageValueLabel.text != summary || metricsLabel.text != values else { return }
        stageValueLabel.text = summary
        metricsLabel.text = values
        // 仅在读数改变时刷新文本；读数不会用于设置卡片或容器高度。
        setNeedsQuickLayout()
    }

}

final class FixedSizeLabCardView: QuickLayoutView {
    let titleLabel = UILabel()
    let detailLabel = UILabel()
    private let numberLabel = UILabel()
    private let symbolView = UIImageView()

    init(index: Int) {
        super.init(frame: .zero)
        let accent: UIColor = [.systemBlue, .systemPurple, .systemTeal, .systemOrange][index]
        backgroundColor = UIColor { traits in
            accent.resolvedColor(with: traits).withAlphaComponent(
                traits.userInterfaceStyle == .dark ? 0.22 : 0.11
            )
        }
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "fixedSize.card.\(index)"
        numberLabel.text = String(format: "%02d", index + 1)
        numberLabel.font = .preferredFont(forTextStyle: .headline)
        numberLabel.textColor = accent
        symbolView.image = UIImage(systemName: ["sparkle", "text.alignleft", "square.stack", "arrow.up.and.down"][index])
        symbolView.tintColor = accent
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .label
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabel
        for label in [numberLabel, titleLabel, detailLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                numberLabel
                Spacer()
                symbolView.resizable().scaledToFit().frame(width: 24, height: 24)
            }
            titleLabel
            detailLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
        setNeedsQuickLayout()
    }
}

