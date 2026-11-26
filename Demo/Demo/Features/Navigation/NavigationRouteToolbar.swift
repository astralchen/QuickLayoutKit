import QuickLayoutKit
import UIKit

final class NavigationRouteToolbar: UIToolbar {
    private let previousItem: UIBarButtonItem
    private let nextItem: UIBarButtonItem
    private let bookmark: UIBarButtonItem

    init(onStep: @escaping (Int) -> Void, onBookmark: @escaping () -> Void) {
        previousItem = Self.makeItem("chevron.backward", id: "previous") { onStep(-1) }
        nextItem = Self.makeItem("chevron.forward", id: "next") { onStep(1) }
        bookmark = Self.makeItem("bookmark", id: "bookmark", action: onBookmark)
        super.init(frame: .zero)
        if #unavailable(iOS 26.0) {
            let appearance = UIToolbarAppearance()
            appearance.configureWithTransparentBackground()
            standardAppearance = appearance
            scrollEdgeAppearance = appearance
            tintColor = .label
        }
        items(content: routeActions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func moveItems(to preview: UIViewController) {
        items {}
        preview.toolbarItems(content: routeActions)
    }

    func restoreItems(from preview: UIViewController?) {
        preview?.toolbarItems {}
        items(content: routeActions)
    }

    func configure(position: Int, count: Int, saved: Bool) {
        previousItem.isEnabled = position > 1
        nextItem.isEnabled = position < count
        previousItem.accessibilityLabel = Localization.text("navLab.previous")
        nextItem.accessibilityLabel = Localization.text("navLab.next")
        bookmark.image = UIImage(systemName: saved ? "bookmark.fill" : "bookmark")
        bookmark.accessibilityLabel = Localization.text(saved ? "navLab.unsave" : "navLab.save")
    }

    @QuickLayoutBarButtonItemBuilder
    private func routeActions() -> [UIBarButtonItem] {
        previousItem
        if #available(iOS 26.0, *) {
            nextItem
            UIBarButtonItem.flexibleSpace()
            bookmark
        } else {
            UIBarButtonItem.flexibleSpace()
            bookmark
            UIBarButtonItem.flexibleSpace()
            nextItem
        }
    }

    private static func makeItem(_ symbol: String, id: String, action: @escaping () -> Void) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { _ in action() })
        item.accessibilityIdentifier = "navLab." + id
        return item
    }
}
