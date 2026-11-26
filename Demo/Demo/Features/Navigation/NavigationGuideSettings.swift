import QuickLayoutKit
import UIKit

final class NavigationGuideSettings: QuickLayoutView {
    enum Setting { case title, search, toolbar }
    var onChange: ((Setting) -> Void)?

    private let heading = JournalLabel(.title2)
    private let card = NavigationGuideCard()
    private let titleChoice: NavigationLabChoice
    private let searchChoice = NavigationLabChoice("navLab.searchMode", icon: "magnifyingglass",
                                                   options: ["navLab.off", "navLab.drawer", "navLab.pinned"])
    private let toolbarChoice = NavigationLabChoice("navLab.toolbarPosition", icon: "rectangle.bottomthird.inset.filled",
                                                    options: ["navLab.photo", "navLab.bottomBar"])

    var titleMode: QuickLayoutNavigationTitleDisplayMode {
        switch titleChoice.control.selectedSegmentIndex {
        case 1: return .large
        case 2:
            if #available(iOS 17.0, *) { return .inlineLarge }
            return .inline
        default: return .inline
        }
    }
    var searchPlacement: QuickLayoutSearchFieldPlacement? {
        switch searchChoice.control.selectedSegmentIndex {
        case 1: return .navigationBarDrawer
        case 2: return .navigationBarDrawer(displayMode: .always)
        default: return nil
        }
    }
    var usesBottomBar: Bool { toolbarChoice.control.selectedSegmentIndex == 1 }

    override init(frame: CGRect) {
        var titles = ["navLab.inline", "navLab.large"]
        if #available(iOS 17.0, *) { titles.append("navLab.inlineLarge") }
        titleChoice = NavigationLabChoice("navLab.titleMode", icon: "textformat.size", options: titles)
        super.init(frame: frame)
        heading.accessibilityTraits.insert(.header)
        for (choice, setting) in [(titleChoice, Setting.title), (searchChoice, .search), (toolbarChoice, .toolbar)] {
            choice.control.addAction(UIAction { [weak self] _ in self?.onChange?(setting) }, for: .valueChanged)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func restoreCoverPosition() { toolbarChoice.control.selectedSegmentIndex = 0 }

    func reloadLabels() {
        heading.text = Localization.text("navLab.settings")
        [titleChoice, searchChoice, toolbarChoice].forEach { $0.reloadLabels() }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 18) {
            heading
            VStack(spacing: 14) {
                titleChoice.resizable(axis: .horizontal)
                searchChoice.resizable(axis: .horizontal)
                toolbarChoice.resizable(axis: .horizontal)
            }
            .padding(16)
            .background { card.resizable() }
        }
    }
}

private final class NavigationLabChoice: QuickLayoutView {
    let control = UISegmentedControl()
    private let label = JournalLabel(.headline)
    private let icon = UIImageView()

    private let key: String
    private let options: [String]

    init(_ key: String, icon symbol: String, options: [String]) {
        self.key = key
        self.options = options
        super.init(frame: .zero)
        control.accessibilityIdentifier = key
        for index in options.indices { control.insertSegment(withTitle: "", at: index, animated: false) }
        control.selectedSegmentIndex = 0
        icon.image = UIImage(systemName: symbol)
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reloadLabels() {
        label.text = Localization.text(key)
        control.accessibilityLabel = label.text
        for index in 0..<control.numberOfSegments {
            control.setTitle(Localization.text(options[index]), forSegmentAt: index)
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                icon.resizable().frame(width: 17, height: 17)
                label
            }
            control.resizable(axis: .horizontal).frame(minHeight: 34)
        }
    }
}
