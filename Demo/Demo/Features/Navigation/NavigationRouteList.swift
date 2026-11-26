import QuickLayoutKit
import UIKit

final class NavigationRouteList: QuickLayoutView {
    private let heading = JournalLabel(.title2)
    private let empty = JournalLabel(.body, color: .secondaryLabel)
    private let card = NavigationGuideCard()
    private let rows: [RouteRow]
    private var visibleRows: [RouteRow]
    private(set) var isFiltering = false

    init(photos: [JournalPhoto], onSelect: @escaping (JournalPhoto) -> Void) {
        rows = photos.map { photo in RouteRow(photo: photo) { onSelect(photo) } }
        visibleRows = rows
        super.init(frame: .zero)
        heading.accessibilityTraits.insert(.header)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(selected: JournalPhoto, saved: Set<String>, query: String) {
        isFiltering = !query.isEmpty
        heading.text = Localization.text(isFiltering ? "navLab.results" : "navLab.routes")
        empty.text = Localization.text("navLab.empty")
        visibleRows = rows.filter { row in
            query.isEmpty || row.photo.title.localizedStandardContains(query)
                || row.photo.album.title.localizedStandardContains(query)
        }
        for row in visibleRows { row.configure(selected: row.photo === selected, saved: saved.contains(row.photo.id)) }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 18) {
            heading
            if visibleRows.isEmpty {
                empty.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    for row in visibleRows { row.resizable(axis: .horizontal) }
                }
                .background { card.resizable() }
            }
        }
    }
}

private final class RouteRow: QuickLayoutView {
    let photo: JournalPhoto
    private let thumbnail = UIImageView()
    private let title = JournalLabel(.headline)
    private let album = JournalLabel(.caption1, color: .secondaryLabel)
    private let mark = UIImageView()
    private let button = UIButton(type: .system)

    init(photo: JournalPhoto, onSelect: @escaping () -> Void) {
        self.photo = photo
        super.init(frame: .zero)
        thumbnail.image = photo.thumbnail
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        mark.contentMode = .scaleAspectFit
        button.accessibilityIdentifier = "navLab.route." + photo.id
        button.addAction(UIAction { _ in onSelect() }, for: .touchUpInside)
        title.isAccessibilityElement = false
        album.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(selected: Bool, saved: Bool) {
        title.text = photo.title
        album.text = photo.album.title
        mark.image = UIImage(systemName: saved ? "bookmark.fill" : (selected ? "checkmark.circle.fill" : "chevron.forward"))
        mark.tintColor = selected || saved ? .systemTeal : .tertiaryLabel
        button.accessibilityLabel = [photo.title, photo.album.title].joined(separator: ", ")
        button.accessibilityValue = saved ? Localization.text("navLab.saved") : nil
        button.accessibilityTraits = selected ? [.button, .selected] : .button
        setNeedsQuickLayout()
    }

    override var body: Layout {
        HStack(spacing: 12) {
            thumbnail.resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                title
                album
            }
            Spacer()
            mark.resizable().frame(width: 17, height: 17)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay { button.resizable() }
    }
}
