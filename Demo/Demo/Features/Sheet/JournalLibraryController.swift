import ListKit
import QuickLayoutKit
import UIKit

/// 相册和封面直接取自主页作品。选择相册后关闭侧栏，并在主页显示相应作品。
final class JournalLibraryController: LocalizedQuickLayoutHostingController {
    private let selected: JournalAlbum
    private let onSelection: (JournalAlbum) -> Void
    private let titleLabel = JournalLabel(.largeTitle)
    private let name = JournalLabel(.headline)
    private let handle = JournalLabel(.subheadline, color: .secondaryLabel)
    private let avatar = UIImageView(image: UIImage(named: "VoiceRoomAvatarHost"))
    private let close = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var adapter = TableListAdapter<Int>(tableView: table)

    init(selected: JournalAlbum, onSelection: @escaping (JournalAlbum) -> Void) {
        self.selected = selected
        self.onSelection = onSelection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        avatar.contentMode = .scaleAspectFill
        avatar.layer.cornerRadius = 22
        avatar.clipsToBounds = true
        titleLabel.accessibilityTraits.insert(.header)
        handle.text = "@fieldnotes"
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        configuration.image = UIImage(systemName: "xmark")
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
        configuration.baseForegroundColor = .label
        close.configuration = configuration
        close.accessibilityIdentifier = "over.close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        table.accessibilityIdentifier = "over.menu"
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 66
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                // 关闭按钮靠近面板内缘，宽窗口中也能避开外侧的系统控件。
                HStack(spacing: 12) {
                    close.resizable().frame(width: 44, height: 44)
                    titleLabel
                    Spacer()
                }
                HStack(spacing: 12) {
                    avatar.resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        handle
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            table.resizable()
        }
        .safeAreaPadding(.top)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderAlbums()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        titleLabel.text = Localization.text("over.menu")
        name.text = Localization.text("over.name")
        close.accessibilityLabel = Localization.text("common.close")
        if table.window != nil { renderAlbums() }
    }

    private func renderAlbums() {
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                albumRow(.all)
            }
            .selectionMode(.single)
            TableSection(1) {
                for album in JournalAlbum.allCases where album != .all {
                    albumRow(album)
                }
            }
            .headerTitle(Localization.text("over.albums"))
            .selectionMode(.single)
        }
    }

    private func albumRow(_ album: JournalAlbum) -> some TableRowRepresentable {
        TableRow(album, model: album, cell: UITableViewCell.self) { [weak self] cell, album, _ in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = album.title
            content.secondaryText = Localization.text("over.count", Int64(album.photos.count))
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = album == .all ? UIImage(systemName: "photo.stack") : album.photos.first?.thumbnail
            content.imageProperties.maximumSize = CGSize(width: 52, height: 48)
            content.imageProperties.reservedLayoutSize = CGSize(width: 52, height: 48)
            content.imageProperties.cornerRadius = 6
            content.directionalLayoutMargins.top = 10
            content.directionalLayoutMargins.bottom = 10
            cell.contentConfiguration = content
            cell.accessoryType = album == self?.selected ? .checkmark : .none
            cell.accessibilityIdentifier = "over.album." + album.rawValue
        }
        .refreshID(album.title)
        .onSelect { [weak self] album, _ in
            guard let self else { return }
            self.dismiss(animated: true) { self.onSelection(album) }
        }
    }
}
