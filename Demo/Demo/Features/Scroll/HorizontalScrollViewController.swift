//
//  HorizontalScrollViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

struct HorizontalCarouselLayoutMetrics: Sendable {

    nonisolated static let spacing: CGFloat = 16
    nonisolated static let preferredMinimumCardWidth: CGFloat = 280
    nonisolated static let nextCardPreviewWidth: CGFloat = 32
    nonisolated static let maximumVisibleCardCount = 3

    nonisolated static func visibleCardCount(
        for containerWidth: CGFloat
    ) -> Int {
        guard containerWidth.isFinite, containerWidth > 0 else { return 1 }
        let count = Int(
            (containerWidth + spacing)
                / (preferredMinimumCardWidth + spacing)
        )
        return min(maximumVisibleCardCount, max(1, count))
    }

    nonisolated static func cardWidth(for containerWidth: CGFloat) -> CGFloat {
        let count = visibleCardCount(for: containerWidth)
        if count == 1 {
            return max(
                0,
                containerWidth - spacing - nextCardPreviewWidth
            )
        }
        let totalSpacing = spacing * CGFloat(count - 1)
        return max(0, (containerWidth - totalSpacing) / CGFloat(count))
    }
}

final class HorizontalScrollViewViewController:
    DemoQuickLayoutHostingController,
    UIScrollViewDelegate {

    override var localizedTitleKey: String? { "demo.horizontalScroll.title" }

    let pageScrollView = QuickLayoutScrollView()
    let scrollView = QuickLayoutScrollView(.horizontal, showsIndicators: false)

    private let eyebrowLabel = UILabel()
    private let headlineLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let gestureIconView = UIImageView()
    private let gestureLabel = UILabel()
    private let pageLabel = UILabel()

    let views: [HorizontalDestinationCardView] =
        HorizontalDestinationCardView.Palette.allCases.map {
            HorizontalDestinationCardView(palette: $0)
        }

    private var currentPage = 0
    private var needsLeadingScrollPosition = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        reloadLocalizedContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        prepareInitialScrollPosition()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPendingLeadingScrollPositionIfNeeded()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()

        eyebrowLabel.text = DemoLocalization.text("horizontal.explore.eyebrow")
        headlineLabel.text = DemoLocalization.text("horizontal.explore.headline")
        subtitleLabel.text = DemoLocalization.text("horizontal.explore.subtitle")
        gestureLabel.text = DemoLocalization.text("horizontal.explore.hint")

        zip(views, HorizontalDestinationCardView.Palette.allCases)
            .forEach { cardView, palette in
                let prefix = palette.localizationKeyPrefix
                cardView.configure(
                    .init(
                        tag: DemoLocalization.text("horizontal.explore.tag"),
                        title: DemoLocalization.text("\(prefix).title"),
                        location: DemoLocalization.text("\(prefix).location"),
                        summary: DemoLocalization.text("\(prefix).summary"),
                        rating: palette.rating,
                        price: DemoLocalization.text("\(prefix).price"),
                        priceCaption: DemoLocalization.text(
                            "horizontal.explore.priceCaption"
                        ),
                        accessibilityHint: DemoLocalization.text(
                            "horizontal.explore.card.accessibilityHint"
                        )
                    )
                )
            }

        updatePageLabel()
        setNeedsQuickLayout()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        pageScrollView.semanticContentAttribute = semanticContentAttribute
        scrollView.semanticContentAttribute = semanticContentAttribute
        views.forEach {
            $0.semanticContentAttribute = semanticContentAttribute
            $0.setNeedsQuickLayout()
        }
        // 语义方向变化可能在父级布局过程中重建横向内容。布局完成后重新定位到逻辑
        // leading 边，避免旧的 LTR 数值偏移残留到 RTL 布局中。
        needsLeadingScrollPosition = true
        view.setNeedsLayout()
        currentPage = 0
        updatePageLabel()
    }

    override var body: Layout {
        ScrollView(pageScrollView) {
            regularHeightContent
        }
    }

    private var regularHeightContent: Layout {
        VStack(alignment: .leading, spacing: 20) {
            headerLayout
                .safeAreaPadding(.horizontal, 20)

            carouselLayout(
                spacing: HorizontalCarouselLayoutMetrics.spacing
            )

            footerLayout
                .safeAreaPadding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    private var headerLayout: Layout {
        VStack(alignment: .leading, spacing: 8) {
            eyebrowLabel
            headlineLabel
            subtitleLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerLayout: Layout {
        HStack(spacing: 8) {
            gestureIconView
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            gestureLabel
            Spacer()
            pageLabel
        }
    }

    private func carouselLayout(spacing: CGFloat) -> Layout {
        ScrollView(scrollView, .horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(views) { cardView in
                    cardView
                        // 卡片高度不受约束时由内容决定；随后由理想尺寸栈在第二轮测量中，
                        // 把最高卡片的高度重新提议给每一张卡片。
                        .resizable(axis: [.horizontal, .vertical])
                        .containerRelativeFrame(.horizontal) {
                            containerWidth,
                            _ in
                            HorizontalCarouselLayoutMetrics.cardWidth(
                                for: containerWidth
                            )
                        }
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            min(24, max(12, geometry.size.width * 0.08))
                        } action: { [weak cardView] cornerRadius in
                            cardView?.updateCornerRadius(cornerRadius)
                        }
                }
            }
            // 先按各卡片的理想高度测量，再使用其中最大值重新测量可垂直伸缩的卡片。
            .idealLayout()
            // 页面垂直滚动视图必须获得完整的理想高度。不要把等高卡片限制在当前横屏
            // 可视区域内；超出部分应交给页面滚动。
            .fixedSize(axis: .vertical)
        }
        .resizable(axis: .horizontal)
        // QuickLayoutScrollView 会在这些边距上叠加当前水平方向安全区域；因此
        // containerRelativeFrame 以安全可视区域测量卡片，但不限制滚动视图自身的 frame。
        .contentMargins(.horizontal, 16)
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        pageScrollView.backgroundColor = .systemGroupedBackground
        pageScrollView.showsVerticalScrollIndicator = false
        pageScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = .fast
        scrollView.delegate = self
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        eyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
        eyebrowLabel.adjustsFontForContentSizeCategory = true
        eyebrowLabel.textColor = .systemBlue

        headlineLabel.font = .preferredFont(forTextStyle: .title2)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        gestureIconView.image = UIImage(systemName: "hand.draw.fill")
        gestureIconView.tintColor = .secondaryLabel
        gestureIconView.contentMode = .scaleAspectFit

        gestureLabel.font = .preferredFont(forTextStyle: .footnote)
        gestureLabel.adjustsFontForContentSizeCategory = true
        gestureLabel.textColor = .secondaryLabel

        pageLabel.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .semibold
        )
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.textColor = .label

        views.enumerated().forEach { index, cardView in
            cardView.onSelect = { [weak self] in
                self?.presentDestination(at: index)
            }
        }
    }

    private func prepareInitialScrollPosition() {
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            scrollView.scrollTo(.leading, animated: false)
            scrollView.layoutIfNeeded()
            needsLeadingScrollPosition = false
            currentPage = 0
            updatePageLabel()
        }
    }

    private func applyPendingLeadingScrollPositionIfNeeded() {
        guard needsLeadingScrollPosition else { return }
        scrollView.layoutIfNeeded()
        scrollView.scrollTo(.leading, animated: false)
        needsLeadingScrollPosition = false
    }

    private func presentDestination(at index: Int) {
        guard views.indices.contains(index) else { return }
        let cardView = views[index]
        let alertController = UIAlertController(
            title: cardView.destinationTitle,
            message: cardView.destinationSummary,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(
                title: DemoLocalization.text("common.close"),
                style: .cancel
            )
        )
        present(alertController, animated: true)
    }

    private func updatePageLabel() {
        pageLabel.text = DemoLocalization.text(
            "horizontal.explore.page",
            currentPage + 1,
            views.count
        )
        pageLabel.accessibilityLabel = pageLabel.text
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView,
              scrollView.bounds.width > 0,
              !views.isEmpty else {
            return
        }

        let viewportCenter = CGPoint(
            x: scrollView.bounds.midX,
            y: scrollView.bounds.midY
        )
        let nearestIndex = views.indices.min { lhs, rhs in
            let lhsFrame = views[lhs].convert(views[lhs].bounds, to: scrollView)
            let rhsFrame = views[rhs].convert(views[rhs].bounds, to: scrollView)
            return abs(lhsFrame.midX - viewportCenter.x)
                < abs(rhsFrame.midX - viewportCenter.x)
        }

        guard let nearestIndex, nearestIndex != currentPage else { return }
        currentPage = nearestIndex
        updatePageLabel()
    }
}

#Preview {
    UINavigationController(
        rootViewController: HorizontalScrollViewViewController()
    )
}
