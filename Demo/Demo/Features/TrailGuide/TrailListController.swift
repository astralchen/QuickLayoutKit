import ListKit
import QuickLayoutKit
import UIKit

final class TrailListController: LocalizedViewController {
    enum Scope {
        case page(TrailPage)
        case route(JournalAlbum)
    }

    private let scope: Scope
    private let browsePlaces: (() -> Void)?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var adapter = TableListAdapter<Int>(tableView: table)

    init(scope: Scope, browsePlaces: (() -> Void)? = nil) {
        self.scope = scope
        self.browsePlaces = browsePlaces
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = table }

    override func viewDidLoad() {
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 96
        table.alwaysBounceVertical = true
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
        if let index = table.indexPathForSelectedRow { table.deselectRow(at: index, animated: animated) }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        render()
    }

    private func render() {
        switch scope {
        case .page(.routes):
            adapter.apply(transaction: .disabled) {
                TableSection(0) {
                    for album in JournalAlbum.allCases where album != .all {
                        routeRow(album)
                    }
                }
                .headerTitle(Localization.text("trail.routes.heading"))
                .selectionMode(.single)
            }
        case .page(.places):
            showPhotos(JournalPhoto.collection, heading: Localization.text("trail.places.heading"))
        case .page(.itinerary):
            let photos = TrailItinerary.photos
            if photos.isEmpty {
                adapter.apply(transaction: .disabled) {
                    TableSection(0) {
                        TableRow("browse", model: Localization.text("trail.browse"), cell: TrailRowCell.self) { cell, title, _ in
                            cell.configure(title: title, subtitle: Localization.text("trail.empty.detail"),
                                           photo: nil, identifier: "trail.browse")
                        }
                        .refreshID(Localization.text("trail.browse"))
                        .onSelect { [weak self] _ in self?.browsePlaces?() }
                    }
                    .headerTitle(Localization.text("trail.empty"))
                    .selectionMode(.single)
                }
            } else {
                showPhotos(photos, heading: Localization.text("trail.itinerary.heading"))
            }
        case let .route(album):
            title = album.title
            navigationItem.largeTitleDisplayMode = .never
            showPhotos(album.photos, heading: Localization.text("trail.route." + album.rawValue))
        }
    }

    private func routeRow(_ album: JournalAlbum) -> some TableRowRepresentable {
        TableRow(album, model: album, cell: TrailRowCell.self) { cell, album, _ in
            cell.configure(title: album.title, subtitle: Localization.text("trail.route." + album.rawValue),
                           photo: album.photos.first, identifier: "trail.route." + album.rawValue)
        }
        .refreshID(album.title)
        .onSelect { [weak self] album, _ in
            self?.navigationController?.pushViewController(TrailListController(scope: .route(album)), animated: true)
        }
    }

    private func showPhotos(_ photos: [JournalPhoto], heading: String) {
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                for photo in photos {
                    TableRow(photo.id, model: photo, cell: TrailRowCell.self) { cell, photo, _ in
                        cell.configure(title: photo.title, subtitle: photo.album.title, photo: photo,
                                       identifier: "trail.place." + photo.id)
                    }
                    .refreshID(photo.title)
                    .onSelect { [weak self] photo, _ in
                        self?.navigationController?.pushViewController(TrailPlaceController(photo: photo), animated: true)
                    }
                }
            }
            .headerTitle(heading)
            .selectionMode(.single)
        }
    }
}

private final class TrailRowCell: QuickLayoutTableViewCell {
    private let thumbnail = UIImageView()
    private let heading = JournalLabel(.headline)
    private let detail = JournalLabel(.subheadline, color: .secondaryLabel)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        thumbnail.layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String, photo: JournalPhoto?, identifier: String) {
        heading.text = title
        detail.text = subtitle
        thumbnail.contentMode = photo == nil ? .center : .scaleAspectFill
        thumbnail.image = photo?.thumbnail ?? UIImage(systemName: "map")
        thumbnail.backgroundColor = .secondarySystemBackground
        accessibilityIdentifier = identifier
        accessibilityLabel = [title, subtitle].joined(separator: ", ")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        HStack(spacing: 12) {
            thumbnail.resizable().frame(width: 78, height: 70)
            VStack(alignment: .leading, spacing: 5) {
                heading
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
    }
}
