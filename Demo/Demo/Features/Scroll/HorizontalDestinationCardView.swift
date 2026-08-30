//
//  HorizontalDestinationCardView.swift
//  Demo
//
//  Created by Codex on 2026/8/21.
//

import UIKit
import QuickLayout
import QuickLayoutKit

struct HorizontalDestinationCardContent: Equatable {
    let tag: String
    let title: String
    let location: String
    let summary: String
    let rating: String
    let price: String
    let priceCaption: String
    let accessibilityHint: String
}

final class HorizontalDestinationCardView: QuickLayoutView {

    enum Palette: CaseIterable {
        case lakeside
        case bamboo
        case city
        case garden
        case coast

        var localizationKeyPrefix: String {
            switch self {
            case .lakeside:
                "horizontal.explore.destination.lakeside"
            case .bamboo:
                "horizontal.explore.destination.bamboo"
            case .city:
                "horizontal.explore.destination.city"
            case .garden:
                "horizontal.explore.destination.garden"
            case .coast:
                "horizontal.explore.destination.coast"
            }
        }

        fileprivate var colors: [UIColor] {
            switch self {
            case .lakeside:
                [
                    UIColor(red: 0.19, green: 0.55, blue: 0.91, alpha: 1),
                    UIColor(red: 0.31, green: 0.78, blue: 0.79, alpha: 1)
                ]
            case .bamboo:
                [
                    UIColor(red: 0.12, green: 0.55, blue: 0.37, alpha: 1),
                    UIColor(red: 0.51, green: 0.74, blue: 0.38, alpha: 1)
                ]
            case .city:
                [
                    UIColor(red: 0.34, green: 0.29, blue: 0.77, alpha: 1),
                    UIColor(red: 0.74, green: 0.39, blue: 0.78, alpha: 1)
                ]
            case .garden:
                [
                    UIColor(red: 0.18, green: 0.47, blue: 0.52, alpha: 1),
                    UIColor(red: 0.55, green: 0.72, blue: 0.65, alpha: 1)
                ]
            case .coast:
                [
                    UIColor(red: 0.12, green: 0.46, blue: 0.76, alpha: 1),
                    UIColor(red: 0.25, green: 0.69, blue: 0.91, alpha: 1)
                ]
            }
        }

        fileprivate var symbolName: String {
            switch self {
            case .lakeside:
                "sailboat.fill"
            case .bamboo:
                "leaf.fill"
            case .city:
                "building.2.fill"
            case .garden:
                "camera.fill"
            case .coast:
                "sun.max.fill"
            }
        }

        var rating: String {
            switch self {
            case .lakeside:
                "4.9"
            case .bamboo:
                "4.8"
            case .city:
                "4.7"
            case .garden:
                "4.9"
            case .coast:
                "4.8"
            }
        }

        fileprivate var accessibilityIdentifier: String {
            let identifier = localizationKeyPrefix.split(separator: ".").last
                ?? "card"
            return "horizontal.destination.\(identifier)"
        }
    }

    var onSelect: (() -> Void)?

    private let artworkView: HorizontalDestinationArtworkView
    private let artworkSymbolView = UIImageView()
    private let tagLabel = UILabel()
    private let tagBackgroundView = UIView()
    private let titleLabel = UILabel()
    private let locationIconView = UIImageView()
    private let locationLabel = UILabel()
    private let summaryLabel = UILabel()
    private let ratingIconView = UIImageView()
    private let ratingLabel = UILabel()
    private let separatorView = UIView()
    private let priceCaptionLabel = UILabel()
    private let priceLabel = UILabel()
    private let disclosureIconView = UIImageView()
    private var content: HorizontalDestinationCardContent?

    var destinationTitle: String { content?.title ?? "" }
    var destinationSummary: String { content?.summary ?? "" }

    init(palette: Palette) {
        artworkView = HorizontalDestinationArtworkView(colors: palette.colors)
        super.init(frame: .zero)
        artworkSymbolView.image = UIImage(systemName: palette.symbolName)
        accessibilityIdentifier = palette.accessibilityIdentifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        artworkView = HorizontalDestinationArtworkView(
            colors: [.systemBlue, .systemTeal]
        )
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ content: HorizontalDestinationCardContent) {
        self.content = content
        tagLabel.text = content.tag
        titleLabel.text = content.title
        locationLabel.text = content.location
        summaryLabel.text = content.summary
        ratingLabel.text = content.rating
        priceLabel.text = content.price
        priceCaptionLabel.text = content.priceCaption
        accessibilityLabel = [
            content.title,
            content.location,
            content.rating,
            content.price
        ].joined(separator: ", ")
        accessibilityHint = content.accessibilityHint
        setNeedsQuickLayout()
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        guard layer.cornerRadius != cornerRadius else { return }
        layer.cornerRadius = cornerRadius
        artworkView.layer.cornerRadius = cornerRadius
        setNeedsLayout()
    }

    override var body: Layout {
        VStack(spacing: 0) {
            artworkLayout
                .frame(height: 146)

            detailsLayout
        }
        // 等高轮播布局可能让宿主高度大于内容的自然高度。填满该提议高度并将内容固定
        // 在顶部，避免较短卡片的背景出现在图片上方。
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var artworkLayout: Layout {
        ZStack(alignment: .center) {
            artworkView
                .resizable()

            artworkSymbolView
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)

            tagLabel
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background { tagBackgroundView }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .padding(.all, 12)
        }
    }

    private var detailsLayout: Layout {
        VStack(alignment: .leading, spacing: 9) {
            titleLabel

            HStack(spacing: 5) {
                locationIconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                locationLabel
                Spacer()
                ratingIconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                ratingLabel
            }

            summaryLabel

            separatorView
                .resizable(axis: .horizontal)
                .frame(height: 1)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    priceCaptionLabel
                    priceLabel
                }
                Spacer()
                disclosureIconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.all, 16)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
    }

    private func setupViews() {
        quickLayoutHorizontalFlexibility = .fullyFlexible
        quickLayoutVerticalFlexibility = .fixedSize
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 22
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)

        artworkView.layer.cornerRadius = 22
        artworkView.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ]
        artworkView.clipsToBounds = true

        artworkSymbolView.tintColor = UIColor.white.withAlphaComponent(0.92)
        artworkSymbolView.contentMode = .scaleAspectFit

        tagLabel.font = .preferredFont(forTextStyle: .caption1)
        tagLabel.adjustsFontForContentSizeCategory = true
        tagLabel.textColor = .white
        tagBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        tagBackgroundView.layer.cornerRadius = 13

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        locationIconView.image = UIImage(systemName: "location.fill")
        locationIconView.tintColor = .secondaryLabel
        locationIconView.contentMode = .scaleAspectFit

        locationLabel.font = .preferredFont(forTextStyle: .caption1)
        locationLabel.adjustsFontForContentSizeCategory = true
        locationLabel.textColor = .secondaryLabel
        locationLabel.lineBreakMode = .byTruncatingTail
        locationLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        ratingIconView.image = UIImage(systemName: "star.fill")
        ratingIconView.tintColor = .systemOrange
        ratingIconView.contentMode = .scaleAspectFit

        ratingLabel.font = .preferredFont(forTextStyle: .caption1)
        ratingLabel.adjustsFontForContentSizeCategory = true
        ratingLabel.textColor = .label
        ratingLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        separatorView.backgroundColor = .separator

        priceCaptionLabel.font = .preferredFont(forTextStyle: .caption2)
        priceCaptionLabel.adjustsFontForContentSizeCategory = true
        priceCaptionLabel.textColor = .secondaryLabel

        priceLabel.font = .preferredFont(forTextStyle: .headline)
        priceLabel.adjustsFontForContentSizeCategory = true
        priceLabel.textColor = .label

        disclosureIconView.image = UIImage(
            systemName: "chevron.forward.circle.fill"
        )
        disclosureIconView.tintColor = .systemBlue
        disclosureIconView.contentMode = .scaleAspectFit

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(didTapCard))
        )
    }

    @objc
    private func didTapCard() {
        onSelect?()
    }
}

private final class HorizontalDestinationArtworkView: QuickLayoutLinearGradientView {

    private let glowLayer = CAGradientLayer()

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        configure(colors: colors)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(colors: [.systemBlue, .systemTeal])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glowLayer.frame = CGRect(
            x: bounds.width * 0.34,
            y: -bounds.height * 0.45,
            width: bounds.width * 0.92,
            height: bounds.height * 1.36
        )
    }

    private func configure(colors: [UIColor]) {
        gradient = QuickLayoutGradient(colors: colors)
        startPoint = .topLeading
        endPoint = .bottomTrailing

        glowLayer.type = .radial
        glowLayer.colors = [
            UIColor.white.withAlphaComponent(0.36).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glowLayer)
    }
}
