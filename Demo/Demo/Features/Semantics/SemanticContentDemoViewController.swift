//
//  SemanticContentDemoViewController.swift
//  Demo
//
//  Created by Sondra on 2026/1/30.
//

import UIKit
import AppLocalization
import QuickLayoutKit
import QuickLayout
/*
UIKit / QuickLayout 方向适配原则：

1. Scene 或 controller root 建立 semanticContentAttribute 边界。
2. 每个 QuickLayout host 从 effectiveUserInterfaceLayoutDirection 取方向，
   普通布局无需再加同值的 layoutDirection modifier。
3. 缓存、复用或独立 host 在语言切换时同步 semantic 并失效布局。
4. UIButton 使用 iOS 15 Configuration 的 leading / trailing placement；
   运行时切换 semantic 后重新应用 configuration，刷新内部图文排列。

只有明确要与页面方向不同的局部示例才使用 forceLeftToRight / forceRightToLeft。
*/

// MARK: - Main Demo Controller
class SemanticContentDemoViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.semantic.title" }

    let scrollView = QuickLayoutScrollView()
    let titleLabel = UILabel()
    let descLabel = UILabel()

    // Demo sections
    let unspecifiedSection = DemoSection(
        titleKey: "semantic.unspecified",
        semantic: .unspecified
    )

    let ltrSection = DemoSection(
        titleKey: "semantic.ltr",
        semantic: .forceLeftToRight
    )

    let rtlSection = DemoSection(
        titleKey: "semantic.rtl",
        semantic: .forceRightToLeft
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center

        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        titleLabel.text = DemoLocalization.text("semantic.header.title")
        descLabel.text = DemoLocalization.text("semantic.header.subtitle")
        unspecifiedSection.reloadLocalizedContent()
        ltrSection.reloadLocalizedContent()
        rtlSection.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

        let attribute = direction.appLayoutDirection.semanticContentAttribute
        scrollView.semanticContentAttribute = attribute
        [titleLabel, descLabel].forEach {
            $0.semanticContentAttribute = attribute
        }

        // The unspecified section inherits from the scroll view. The explicit
        // LTR and RTL sections keep their forced semantic boundaries.
        unspecifiedSection.invalidateLayoutDirection()
        ltrSection.invalidateLayoutDirection()
        rtlSection.invalidateLayoutDirection()
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                titleLabel
                descLabel
            }
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))

            // Scrollable content
            ScrollView(scrollView) {
                VStack(spacing: 20) {
                    unspecifiedSection
                    ltrSection
                    rtlSection
                }
            }
            .contentMargins(16)
        }
        .safeAreaPadding(.top, 0)
        .safeAreaPadding(.horizontal, 0)
    }
}

// MARK: - Demo Section Component
@QuickLayout
class DemoSection: UIView {

    let titleLabel = UILabel()
    let semantic: UISemanticContentAttribute

    // Example 1: Icon + Text
    let example1 = ExampleRow1()

    // Example 2: Leading/Trailing
    let example2 = ExampleRow2()

    // Example 3: Image alignment
    let example3 = ExampleRow3()

    // Example 4: Button with icon
    let example4 = ExampleRow4()

    // Example 5: Progress bar
    let example5 = ExampleRow5()

    let titleKey: String

    init(titleKey: String, semantic: UISemanticContentAttribute) {
        self.titleKey = titleKey
        self.semantic = semantic
        super.init(frame: .zero)

        setupViews()
        self.semanticContentAttribute = semantic
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemGray6
        layer.cornerRadius = 12

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        example1.semanticContentAttribute = semantic
        example2.semanticContentAttribute = semantic
        example3.semanticContentAttribute = semantic
        example4.applySemanticContentAttribute(semantic)
        example5.semanticContentAttribute = semantic
        reloadLocalizedContent()
    }

    func reloadLocalizedContent() {
        titleLabel.text = DemoLocalization.text(titleKey)
        example1.reloadLocalizedContent()
        example2.reloadLocalizedContent()
        example3.reloadLocalizedContent()
        example4.reloadLocalizedContent()
        setNeedsLayout()
    }

    func invalidateLayoutDirection() {
        semanticContentAttribute = semantic
        [example1, example2, example3, example5].forEach {
            $0.semanticContentAttribute = semantic
            $0.setNeedsLayout()
        }
        example4.applySemanticContentAttribute(semantic)
        setNeedsLayout()
    }

    var body: Layout {
        VStack(spacing: 12) {
            titleLabel
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))

            example1
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            example2
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            example3
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            example4
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            example5
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
        }
    }
}

// MARK: - Example Rows

@QuickLayout
class ExampleRow1: UIView {
    let iconLabel = UILabel()
    let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8

        iconLabel.text = "📱"
        iconLabel.font = .systemFont(ofSize: 32)

        textLabel.font = .systemFont(ofSize: 16)
        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        HStack(spacing: 12) {
            iconLabel
                .frame(width: 32, height: 32)
            textLabel
            Spacer()
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    func reloadLocalizedContent() {
        textLabel.text = DemoLocalization.text("semantic.phone")
        setNeedsLayout()
    }
}

@QuickLayout
class ExampleRow2: UIView {
    let leadingBackgroundView = UIView()
    let leadingTitleLabel = UILabel()
    let directionIconView = UIImageView(image: UIImage(systemName: "arrow.left.and.right"))
    let trailingTitleLabel = UILabel()
    let trailingBackgroundView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8

        leadingBackgroundView.backgroundColor = .systemBlue
        leadingBackgroundView.layer.cornerRadius = 6

        trailingBackgroundView.backgroundColor = .systemRed
        trailingBackgroundView.layer.cornerRadius = 6

        [leadingTitleLabel, trailingTitleLabel].forEach { label in
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .label
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
        }

        directionIconView.tintColor = .secondaryLabel
        directionIconView.contentMode = .scaleAspectFit
        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        HStack(alignment: .center, spacing: 12) {
            leadingTitleLabel
                .padding(8)
                .background() {
                    leadingBackgroundView
                }

            Spacer()
            directionIconView
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Spacer()

            trailingTitleLabel
                .padding(8)
                .background() {
                    trailingBackgroundView
                }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    func reloadLocalizedContent() {
        leadingTitleLabel.text = DemoLocalization.text("semantic.leading")
        trailingTitleLabel.text = DemoLocalization.text("semantic.trailing")
        setNeedsLayout()
    }
}

@QuickLayout
class ExampleRow3: UIView {
    let imageView = UIImageView()
    let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8

        imageView.backgroundColor = .systemGreen
        imageView.image = UIImage(systemName: "person.crop.circle.fill")
        imageView.tintColor = .white
        imageView.layer.cornerRadius = 20
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        descLabel.font = .systemFont(ofSize: 14)
        descLabel.numberOfLines = 2
        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        HStack(spacing: 12) {
            imageView
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
            descLabel
            Spacer()
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    func reloadLocalizedContent() {
        descLabel.text = DemoLocalization.text("semantic.avatar")
        setNeedsLayout()
    }
}

@QuickLayout
class ExampleRow4: UIView {
    let button: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = DemoLocalization.text("semantic.next")
        configuration.image = UIImage(systemName: "arrow.right")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        return UIButton(configuration: configuration)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8

        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        button
            .frame(height: 44)
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    func reloadLocalizedContent() {
        if var configuration = button.configuration {
            configuration.title = DemoLocalization.text("semantic.next")
            button.configuration = configuration
        } else {
            assertionFailure("Semantic demo button requires UIButton.Configuration")
        }
        setNeedsLayout()
    }

    func applySemanticContentAttribute(
        _ semanticContentAttribute: UISemanticContentAttribute
    ) {
        self.semanticContentAttribute = semanticContentAttribute
        button.semanticContentAttribute = semanticContentAttribute
        button.configuration = button.configuration
        setNeedsLayout()
    }
}

@QuickLayout
class ExampleRow5: UIView {
    let progressBar = UIView()
    let progressFill = UIView()
    let percentLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8

        progressBar.backgroundColor = .systemGray5
        progressBar.layer.cornerRadius = 4

        progressFill.backgroundColor = .systemBlue
        progressFill.layer.cornerRadius = 4

        percentLabel.text = "75%"
        percentLabel.font = .systemFont(ofSize: 12, weight: .medium)
        percentLabel.textColor = .systemBlue

        progressBar.addSubview(progressFill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Progress fill takes 75% of progress bar width
        let fillWidth = progressBar.bounds.width * 0.75
        let fillOriginX = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? progressBar.bounds.width - fillWidth
            : 0
        progressFill.frame = CGRect(
            x: fillOriginX,
            y: 0,
            width: fillWidth,
            height: progressBar.bounds.height
        )
    }

    var body: Layout {
        HStack(spacing: 8) {
            progressBar
                .frame(height: 8)
            percentLabel
                .frame(width: 50)
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }
}

#Preview {
    UINavigationController(rootViewController: SemanticContentDemoViewController())
}
