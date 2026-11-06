import AppLocalization
import QuickLayoutKit
import UIKit

final class ArrangementViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.arrangement.title" }

    private var isWindowPreview = false
    private var startsInSwiftUI = false
    private let openWindowButton = UIButton(type: .system)
    private var example = ArrangementExample.automatic
    private let scroll = QuickLayoutScrollView()
    private let picker = UIButton(type: .system)
    private let engine = UISegmentedControl(items: ["QuickLayoutKit", "SwiftUI"])
    private let preview = ArrangementPreview()
    private var reference: UIView?
    private let heightControl = UISlider()
    private var previewHeight: CGFloat = 0
    private let heightLabel = UILabel()
    private let containerClasses = UILabel()
    private let explanation = UILabel()
    private let code = UILabel()

    override func viewDidLoad() {
        engine.selectedSegmentIndex = startsInSwiftUI ? 1 : 0
        heightControl.value = 0.35
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        picker.showsMenuAsPrimaryAction = true
        picker.accessibilityIdentifier = "arrangement.example"
        picker.configuration = .tinted()
        picker.configuration?.image = UIImage(systemName: "chevron.down")
        picker.configuration?.imagePlacement = .trailing
        picker.configuration?.imagePadding = 8
        engine.accessibilityIdentifier = "arrangement.engine"
        engine.addTarget(self, action: #selector(updateExample), for: .valueChanged)
        heightControl.addTarget(self, action: #selector(resizePreview), for: .valueChanged)
        for label in [heightLabel, containerClasses, explanation, code] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        heightLabel.font = .preferredFont(forTextStyle: .caption1)
        containerClasses.font = .preferredFont(forTextStyle: .caption1)
        explanation.font = .preferredFont(forTextStyle: .body)
        code.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        code.textAlignment = .left
        code.semanticContentAttribute = .forceLeftToRight
        code.lineBreakMode = .byCharWrapping
        openWindowButton.accessibilityIdentifier = "arrangement.openWindow"
        openWindowButton.addTarget(self, action: #selector(openWindowPreview), for: .touchUpInside)
        if isWindowPreview {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self,
                                                               action: #selector(closeWindowPreview))
            navigationItem.leftBarButtonItem?.accessibilityIdentifier = "arrangement.closeWindow"
            if supportsReference { navigationItem.titleView = engine }
        }
        reloadLocalizedContent()
    }

    override var body: Layout {
        if isWindowPreview {
            return (reference ?? preview).resizable()
        }
        return ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 12) {
                picker
                if supportsReference { engine.resizable(axis: .horizontal) }
                containerClasses
                (reference ?? preview).resizable().frame(height: previewHeight)
                openWindowButton
                heightLabel
                heightControl.resizable(axis: .horizontal)
                explanation
                code
            }.padding(.vertical, 16)
        }.contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private var supportsReference: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) { return true }
        #endif
        return false
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        openWindowButton.setTitle(Localization.text("arrangement.openWindow"), for: .normal)
        heightControl.accessibilityLabel = Localization.text("arrangement.height")
        updateContainerClasses()
        updateExample()
    }

    @objc private func openWindowPreview() {
        let page = ArrangementViewController()
        page.isWindowPreview = true
        page.example = example
        page.startsInSwiftUI = engine.selectedSegmentIndex == 1
        let navigation = UINavigationController(rootViewController: page)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func closeWindowPreview() {
        dismiss(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContainerClasses()
        resizePreview()
    }

    private func updateContainerClasses() {
        let text = Localization.text("arrangement.container", traitCollection.arrangementSizeClasses)
        if isWindowPreview {
            if navigationItem.prompt != text { navigationItem.prompt = text }
        } else if containerClasses.text != text {
            containerClasses.text = text
            setNeedsQuickLayout()
        }
    }

    @objc private func resizePreview() {
        guard !isWindowPreview else { return }
        let available = view.safeAreaLayoutGuide.layoutFrame.height
        guard available > 0 else { return }
        let minimum = min(180, available)
        let heightInPoints = (minimum + CGFloat(heightControl.value) * (available - minimum)).rounded(.down)
        let height = "\(Int(heightInPoints)) pt"
        let title = "\(Localization.text("arrangement.height")) · \(height)"
        guard heightInPoints != previewHeight || heightLabel.text != title else { return }
        previewHeight = heightInPoints
        heightLabel.text = title
        heightControl.accessibilityValue = height
        setNeedsQuickLayout()
    }

    @objc private func updateExample() {
        picker.setTitle(Localization.text("arrangement.\(example.rawValue).title"), for: .normal)
        picker.menu = UIMenu(children: ArrangementExample.allCases.map { item in
            UIAction(title: Localization.text("arrangement.\(item.rawValue).title"),
                     state: item == example ? .on : .off) { [weak self] _ in
                self?.example = item
                self?.updateExample()
            }
        })
        preview.example = example
        preview.setNeedsQuickLayout()
        #if compiler(>=6.4)
        if #available(iOS 27.1, *), engine.selectedSegmentIndex == 1 {
            reference = makeArrangementReference(example, direction: view.effectiveUserInterfaceLayoutDirection)
        } else {
            reference = nil
        }
        #endif
        explanation.text = Localization.text("arrangement.\(example.rawValue).detail")
        code.text = example.code(swiftUI: reference != nil)
        resizePreview()
        setNeedsQuickLayout()
    }
}
