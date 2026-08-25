//
//  PositionAndZIndexDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/24.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class PositionAndZIndexDemoViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? {
        "demo.positionAndZIndex.title"
    }

    private let scrollView = QuickLayoutScrollView()
    private let introLabel = UILabel()
    private let positionTitleLabel = UILabel()
    private let positionDescriptionLabel = UILabel()
    private let positionCodeLabel = UILabel()
    let positionCanvas = PositionDemoCanvas()
    private let zIndexTitleLabel = UILabel()
    private let zIndexDescriptionLabel = UILabel()
    private let zIndexCodeLabel = UILabel()
    let zIndexCanvas = ZIndexDemoCanvas()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground

        configureBodyLabel(introLabel)
        configureSectionTitle(positionTitleLabel, text: "position(_:)")
        configureBodyLabel(positionDescriptionLabel)
        configureCodeLabel(positionCodeLabel)
        positionCodeLabel.text = "position(x: 144, y: 100)"

        configureSectionTitle(zIndexTitleLabel, text: "zIndex(_:)")
        configureBodyLabel(zIndexDescriptionLabel)
        configureCodeLabel(zIndexCodeLabel)
        zIndexCodeLabel.text = "A.zIndex(0)  C.zIndex(1)  B.zIndex(3)"
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        introLabel.text = DemoLocalization.text("positionAndZIndex.intro")
        positionDescriptionLabel.text = DemoLocalization.text(
            "positionAndZIndex.position.description"
        )
        zIndexDescriptionLabel.text = DemoLocalization.text(
            "positionAndZIndex.zIndex.description"
        )
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

        let semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        [scrollView, positionCanvas, zIndexCanvas].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
            $0.setNeedsLayout()
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 20) {
                introLabel

                VStack(alignment: .leading, spacing: 10) {
                    positionTitleLabel
                    positionDescriptionLabel
                    positionCodeLabel
                    positionCanvas
                        .resizable(axis: .horizontal)
                        .frame(height: 200)
                }

                VStack(alignment: .leading, spacing: 10) {
                    zIndexTitleLabel
                    zIndexDescriptionLabel
                    zIndexCodeLabel
                    zIndexCanvas
                        .resizable(axis: .horizontal)
                        .frame(height: 210)
                }
            }
            .padding(.vertical, 16)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollIndicators)
    }

    private func configureBodyLabel(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
    }

    private func configureSectionTitle(_ label: UILabel, text: String) {
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
    }

    private func configureCodeLabel(_ label: UILabel) {
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .systemIndigo
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
    }
}

@QuickLayout
final class PositionDemoCanvas: UIView {

    private let backgroundView = UIView()
    private let horizontalGuideView = UIView()
    private let verticalGuideView = UIView()
    let firstBadge = UILabel()
    let centerBadge = UILabel()
    let lastBadge = UILabel()
    private let firstBadgeBackground = UIView()
    private let centerBadgeBackground = UIView()
    private let lastBadgeBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundView.backgroundColor = .secondarySystemGroupedBackground
        backgroundView.layer.cornerRadius = 16
        horizontalGuideView.backgroundColor = .separator
        verticalGuideView.backgroundColor = .separator

        configureBadge(
            firstBadge,
            backgroundView: firstBadgeBackground,
            text: "A\n(60, 54)",
            color: .systemOrange
        )
        configureBadge(
            centerBadge,
            backgroundView: centerBadgeBackground,
            text: "B\n(144, 100)",
            color: .systemBlue
        )
        configureBadge(
            lastBadge,
            backgroundView: lastBadgeBackground,
            text: "C\n(228, 146)",
            color: .systemGreen
        )

        accessibilityIdentifier = "positionAndZIndex.position.canvas"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        ZStack(alignment: .topLeading) {
            backgroundView.resizable()

            horizontalGuideView
                .frame(width: 240, height: 1)
                .position(x: 144, y: 100)

            verticalGuideView
                .frame(width: 1, height: 160)
                .position(CGPoint(x: 144, y: 100))

            firstBadge
                .expand(by: CGSize(width: 28, height: 16))
                .background { firstBadgeBackground }
                .position(x: 60, y: 54)

            centerBadge
                .expand(by: CGSize(width: 28, height: 16))
                .background { centerBadgeBackground }
                .position(CGPoint(x: 144, y: 100))

            lastBadge
                .expand(by: CGSize(width: 28, height: 16))
                .background { lastBadgeBackground }
                .position(x: 228, y: 146)
        }
    }

    private func configureBadge(
        _ label: UILabel,
        backgroundView: UIView,
        text: String,
        color: UIColor
    ) {
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.accessibilityLabel = text.replacingOccurrences(of: "\n", with: " ")
        backgroundView.backgroundColor = color
        backgroundView.layer.cornerRadius = 12
    }
}

@QuickLayout
final class ZIndexDemoCanvas: UIView {

    private let backgroundView = UIView()
    let backCard = UILabel()
    let frontCard = UILabel()
    let middleCard = UILabel()
    private let backCardBackground = UIView()
    private let frontCardBackground = UIView()
    private let middleCardBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundView.backgroundColor = .secondarySystemGroupedBackground
        backgroundView.layer.cornerRadius = 16
        configureCard(
            backCard,
            backgroundView: backCardBackground,
            text: "A\nzIndex(0)",
            color: .systemOrange
        )
        configureCard(
            frontCard,
            backgroundView: frontCardBackground,
            text: "B\nzIndex(3)",
            color: .systemBlue
        )
        configureCard(
            middleCard,
            backgroundView: middleCardBackground,
            text: "C\nzIndex(1)",
            color: .systemGreen
        )

        accessibilityIdentifier = "positionAndZIndex.zIndex.canvas"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        ZStack(alignment: .topLeading) {
            backgroundView.resizable()

            backCard
                .expand(by: CGSize(width: 36, height: 24))
                .background { backCardBackground }
                .position(x: 86, y: 120)
                .zIndex(0)

            // B 在 C 之前声明，但更大的 zIndex 仍使它显示在最前方。
            frontCard
                .expand(by: CGSize(width: 36, height: 24))
                .background { frontCardBackground }
                .position(x: 146, y: 72)
                .zIndex(3)

            middleCard
                .expand(by: CGSize(width: 36, height: 24))
                .background { middleCardBackground }
                .position(x: 216, y: 122)
                .zIndex(1)
        }
    }

    private func configureCard(
        _ label: UILabel,
        backgroundView: UIView,
        text: String,
        color: UIColor
    ) {
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.accessibilityLabel = text.replacingOccurrences(of: "\n", with: " ")
        backgroundView.backgroundColor = color.withAlphaComponent(0.92)
        backgroundView.layer.cornerRadius = 16
    }
}

#Preview {
    UINavigationController(
        rootViewController: PositionAndZIndexDemoViewController()
    )
}
