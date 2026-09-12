import UIKit
import QuickLayout
import QuickLayoutKit

struct ContentConfigurationWaterfallItem {
    let id: Int
    var revision = 0
    var isExpanded = false
    let model: ContentConfigurationModel
    let imageAspectRatio: CGFloat

    static func samples(localizer: Localizer) -> [Self] {
        let models = ContentConfigurationModel.localizedMockData(localizer: localizer)
        let ratios: [CGFloat] = [1, 4.0 / 3, 3.0 / 4]
        return (0..<40).map { id in
            Self(id: id, model: models[id % models.count], imageAspectRatio: ratios[id % ratios.count])
        }
    }
}

/// 只声明内容；尺寸测量及失效由 QuickLayoutContentView 提供。
final class ContentConfigurationWaterfallCard: QuickLayoutContentView {
    struct Configuration: UIContentConfiguration {
        var item: ContentConfigurationWaterfallItem
        let sizing: ContentConfigurationWaterfallLayout.ItemSizing
        var isHighlighted = false

        func makeContentView() -> UIView & UIContentView {
            ContentConfigurationWaterfallCard(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> Self {
            var result = self
            result.isHighlighted = (state as? UICellConfigurationState)?.isHighlighted ?? false
            return result
        }
    }

    let coverView = UIImageView()
    let titleLabel = UILabel()
    let detailLabel = UILabel()
    private var imageAspectRatio: CGFloat = 1
    private var sizing = ContentConfigurationWaterfallLayout.ItemSizing(
        constraint: CGSize(width: 1, height: CGFloat.infinity),
        horizontalFlexibility: .fixedSize, verticalFlexibility: .fullyFlexible
    )

    override var body: Layout {
        // 约束来自布局；估算主轴长度不进入内容测量。
        if sizing.horizontalFlexibility == .fullyFlexible {
            HStack(alignment: .center, spacing: 12) {
                coverView.resizable()
                    .frame(width: horizontalCoverHeight * imageAspectRatio, height: horizontalCoverHeight)
                // 先选择窄文本栏；行高不足时增加宽度，正文始终完整。只在 QuickLayout 内部评估候选布局。
                ViewThatFits(in: .vertical) {
                    textLayout.frame(width: 180)
                    textLayout.frame(width: 260)
                    textLayout.frame(width: 360)
                    textLayout.frame(width: 520)
                    textLayout
                }
            }
            .padding(12)
            .frame(height: sizing.constraint.height, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                coverView.resizable()
                    .aspectRatio(imageAspectRatio, contentMode: .fit)
                    .frame(width: sizing.constraint.width)
                textLayout
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(width: sizing.constraint.width, alignment: .leading)
            .frame(height: sizing.constraint.height.isFinite ? sizing.constraint.height : nil, alignment: .topLeading)
        }
    }

    private var horizontalCoverHeight: CGFloat { max(1, min(96, sizing.constraint.height - 24)) }

    private var textLayout: Layout {
        VStack(alignment: .leading, spacing: 6) {
            titleLabel
            detailLabel
        }
    }

    init(configuration: Configuration) {
        super.init(configuration: configuration)
        coverView.contentMode = .center
        coverView.clipsToBounds = true
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        for label in [titleLabel, detailLabel] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        layer.cornerRadius = 12
        clipsToBounds = true
        applyCurrentContentConfiguration()
    }

    override func applyContentConfiguration(_ configuration: UIContentConfiguration) {
        guard let configuration = configuration as? Configuration else {
            assertionFailure("Unexpected waterfall configuration")
            return
        }
        let item = configuration.item
        sizing = configuration.sizing
        quickLayoutHorizontalFlexibility = sizing.horizontalFlexibility
        quickLayoutVerticalFlexibility = sizing.verticalFlexibility
        coverView.layer.cornerRadius = sizing.horizontalFlexibility == .fullyFlexible ? 8 : 0
        imageAspectRatio = item.imageAspectRatio
        titleLabel.text = item.model.title
        // 每组增加正文段落，展开后继续增加真实内容，不指定卡片高度。
        let repetitions = 1 + (item.id / 4) % 3 + (item.isExpanded ? 3 : 0)
        detailLabel.text = Array(repeating: item.model.detail, count: repetitions).joined(separator: sizing.horizontalFlexibility == .fullyFlexible ? " " : "\n\n")
        coverView.image = UIImage(
            systemName: item.model.imageName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        )
        coverView.tintColor = item.model.themeColor
        coverView.backgroundColor = item.model.themeColor.withAlphaComponent(0.15)
        backgroundColor = .secondarySystemGroupedBackground
        alpha = configuration.isHighlighted ? 0.75 : 1
        accessibilityIdentifier = "waterfall.card.\(item.id)"
        super.applyContentConfiguration(configuration)
    }
}

/// 装饰视图由布局注册并复用；不经过 data source 的 supplementary provider。
final class ContentConfigurationWaterfallBackground: UICollectionReusableView {
    static let elementKind = "waterfall.section.background"
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.08)
        layer.cornerRadius = 16
        isUserInteractionEnabled = false
        accessibilityIdentifier = "waterfall.section.background"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 固定主轴长度的分组标题，内容布局继续使用 QuickLayoutKit。
final class ContentConfigurationWaterfallHeader: QuickLayoutCollectionReusableView {
    private let titleLabel = UILabel()
    override var body: Layout {
        titleLabel.resizable().padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .secondaryLabel
        isAccessibilityElement = true
        accessibilityTraits = .header
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, direction: UIUserInterfaceLayoutDirection) {
        titleLabel.text = title
        semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        titleLabel.textAlignment = direction == .rightToLeft ? .right : .left
        accessibilityLabel = title
        setNeedsQuickLayout()
    }
}
