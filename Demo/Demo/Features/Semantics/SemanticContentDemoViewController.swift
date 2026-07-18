//
//  SemanticContentDemoViewController.swift
//  Demo
//
//  Created by Sondra on 2026/1/30.
//

import UIKit
import QuickLayoutKit
import QuickLayout
/*
UIKit semanticContentAttribute 行为整理（实战版）

一、三个层级，先记住这张心智模型 🧠

1️⃣ 系统方向
    •    UIApplication.shared.userInterfaceLayoutDirection
    •    由系统语言决定（中文 / 英文 = LTR）

⸻

2️⃣ View 语义
    •    UIView.semanticContentAttribute
    •    作用于：
    •    Auto Layout 的 leading / trailing
    •    StackView 排列
    •    部分控件内部布局

⚠️ 不是所有子控件都会完全继承

⸻

3️⃣ 控件内部子布局（坑最多）
    •    UIButton 的 image / title
    •    UITextField 的 leftView / rightView
    •    UICollectionViewCell 的内部 subviews

👉 很多都是“必须自己 force”
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
        example4.semanticContentAttribute = semantic
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
    let button = RTLAwareButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8

        button.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        button.backgroundColor = .systemBlue
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        reloadLocalizedContent()
    }

//    override var semanticContentAttribute: UISemanticContentAttribute {
//        didSet {
//            /*
//            ❓为什么 Apple 要这么设计？
//
//            这是一个历史包袱：
//                •    UIButton 早于 RTL 支持很多年
//                •    image/title 排列是早期“固定逻辑”
//                •    为了兼容老 App：
//                •    ❌ 不敢自动跟随父 view RTL
//                •    ✅ 只能在按钮自身 force
//
//            📌 所以这不是 bug，是“为了不破坏老 UI”。
//             */
//            button.semanticContentAttribute = semanticContentAttribute
//        }
//    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var body: Layout {
        button
            .frame(height: 44)
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
    }

    func reloadLocalizedContent() {
        button.setTitle(" \(DemoLocalization.text("semantic.next"))", for: .normal)
        setNeedsLayout()
    }
}

//superview.semanticContentAttribute 默认就是 .unspecified，父容器并不是通过自身的 semanticContentAttribute 来表达 RTL 的，而是通过 effectiveUserInterfaceLayoutDirection 来体现最终方向。
//所以读 superview.semanticContentAttribute 拿到的还是 .unspecified，同步过去没有任何效果。

class RTLAwareButton: UIButton {
//    effectiveUserInterfaceLayoutDirection 在 didMoveToSuperview 时不一定已经稳定（父容器自身可能还没完成布局），更安全的时机是：

//    override func didMoveToSuperview() {
//        super.didMoveToSuperview()
//        syncDirection()
//    }
//
//    private func syncDirection() {
//        guard let superview else { return }
//        switch superview.effectiveUserInterfaceLayoutDirection {
//        case .rightToLeft:
//            semanticContentAttribute = .forceRightToLeft
//        case .leftToRight:
//            semanticContentAttribute = .forceLeftToRight
//        @unknown default:
//            break
//        }
//        
//    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 只在需要时更新，避免死循环
        let needed: UISemanticContentAttribute =
            (superview?.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            ? .forceRightToLeft : .forceLeftToRight
        
        if semanticContentAttribute != needed {
            semanticContentAttribute = needed
        }
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
        progressFill.frame = CGRect(
            x: 0,
            y: 0,
            width: progressBar.bounds.width * 0.75,
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
