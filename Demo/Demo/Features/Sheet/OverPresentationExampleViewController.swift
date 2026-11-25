import QuickLayoutKit
import QuickLook
import UIKit

/// 摄影主页和图库共用同一份相册数据。菜单按钮与屏幕边缘手势共用一个呈现入口。
final class OverPresentationExampleViewController: LocalizedQuickLayoutHostingController, QLPreviewControllerDataSource {
    override var localizedTitleKey: String? { "over.journal" }

    private let scroll = QuickLayoutScrollView()
    private let cover = JournalCoverView()
    private let sectionHeader = JournalSectionHeader()
    private var album = JournalAlbum.all
    private let tiles = JournalPhoto.collection.map { JournalPhotoTile($0) }
    private var interaction: OverPresentationInteraction?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        cover.menu.addAction(UIAction { [weak self] _ in self?.interaction?.present() }, for: .touchUpInside)
        for tile in tiles {
            tile.button.addAction(UIAction { [weak self, photo = tile.photo] _ in self?.preview(photo) }, for: .touchUpInside)
        }
        interaction = installOverPresentationInteraction(makeViewController: { [weak self] in
            JournalLibraryController(selected: self?.album ?? .all) { [weak self] album in
                self?.select(album)
            }
        }) { presentation in
            presentation.detent = .automatic()
            presentation.presentingViewEffect = .push
        }
        refreshGallery()
    }

    override var body: Layout {
        ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 22) {
                cover.resizable(axis: .horizontal)
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader.resizable(axis: .horizontal)
                    VGrid(columns: [.init(.adaptive(minimum: 136), spacing: 12)], alignment: .leading, spacing: 18) {
                        for tile in tiles where album.includes(tile.photo) {
                            tile.resizable(axis: .horizontal)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        cover.reloadText()
        tiles.forEach { $0.reloadText() }
        refreshGallery()
    }

    private func refreshGallery() {
        sectionHeader.configure(album)
        setNeedsQuickLayout()
    }

    private func select(_ album: JournalAlbum) {
        self.album = album
        refreshGallery()
        scroll.setContentOffset(CGPoint(x: -scroll.adjustedContentInset.left, y: -scroll.adjustedContentInset.top), animated: false)
    }

    private func preview(_ photo: JournalPhoto) {
        guard let index = album.photos.firstIndex(where: { $0 === photo }) else { return }
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.currentPreviewItemIndex = index
        present(preview, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { album.photos.count }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        album.photos[index]
    }
}

/// 封面与作品使用同一组本地照片；原图交给 Quick Look 以支持缩放和左右翻阅。
@MainActor
final class JournalPhoto: NSObject, QLPreviewItem {
    let id: String
    let album: JournalAlbum
    let previewItemURL: URL?
    var previewItemTitle: String? { title }
    var title: String { Localization.text("over." + id) }

    init(_ id: String, _ album: JournalAlbum) {
        self.id = id
        self.album = album
        previewItemURL = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "FieldNotes.bundle")
    }

    lazy var thumbnail: UIImage? = previewItemURL.flatMap { UIImage(contentsOfFile: $0.path) }?
        .preparingThumbnail(of: CGSize(width: 640, height: 640))

    static let collection = [
        JournalPhoto("ridge", .mountains), JournalPhoto("lake", .lakes),
        JournalPhoto("woodland", .woods), JournalPhoto("shore", .lakes),
        JournalPhoto("alpine", .mountains), JournalPhoto("forest", .woods)
    ]
}

enum JournalAlbum: String, CaseIterable {
    case all, mountains, lakes, woods

    @MainActor var title: String { Localization.text("over." + rawValue) }
    @MainActor var photos: [JournalPhoto] { JournalPhoto.collection.filter { includes($0) } }
    @MainActor func includes(_ photo: JournalPhoto) -> Bool { self == .all || self == photo.album }
}

final class JournalLabel: UILabel {
    init(_ style: UIFont.TextStyle, color: UIColor = .label) {
        super.init(frame: .zero)
        font = .preferredFont(forTextStyle: style)
        adjustsFontForContentSizeCategory = true
        textColor = color
        numberOfLines = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class JournalCoverView: QuickLayoutView {
    let menu = UIButton(type: .system)
    private let image = UIImageView()
    private let name = JournalLabel(.largeTitle, color: .white)
    private let bio = JournalLabel(.subheadline, color: .white)
    private let shade = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        image.image = JournalAlbum.lakes.photos.first?.thumbnail
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.80).cgColor]
        image.layer.addSublayer(shade)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "line.3.horizontal")
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .black.withAlphaComponent(0.55)
        config.cornerStyle = .capsule
        menu.configuration = config
        menu.accessibilityIdentifier = "over.open"
        name.accessibilityTraits.insert(.header)
        reloadText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reloadText() {
        name.text = Localization.text("over.name")
        bio.text = Localization.text("over.bio")
        menu.accessibilityLabel = Localization.text("over.menu")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 6) {
            menu.frame(width: 44, height: 44).frame(maxWidth: .infinity, alignment: .trailing)
            Spacer(minLength: 66)
            name
            bio
        }
        .padding(18)
        .background { image.resizable() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = image.bounds
        CATransaction.commit()
    }
}

private final class JournalSectionHeader: QuickLayoutView {
    private let heading = JournalLabel(.title2)
    private let count = JournalLabel(.subheadline, color: .secondaryLabel)

    func configure(_ album: JournalAlbum) {
        heading.text = album.title
        heading.accessibilityIdentifier = "over.gallery.title"
        heading.accessibilityTraits.insert(.header)
        count.text = Localization.text("over.count", Int64(album.photos.count))
        setNeedsQuickLayout()
    }

    override var body: Layout {
        HStack(spacing: 8) {
            heading
            Spacer()
            count
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

private final class JournalPhotoTile: QuickLayoutView {
    let photo: JournalPhoto
    let button = UIButton(type: .custom)
    private let image = UIImageView()
    private let caption = JournalLabel(.headline)
    private let category = JournalLabel(.caption1, color: .secondaryLabel)

    init(_ photo: JournalPhoto) {
        self.photo = photo
        super.init(frame: .zero)
        image.image = photo.thumbnail
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 10
        image.layer.cornerCurve = .continuous
        caption.isAccessibilityElement = false
        category.isAccessibilityElement = false
        button.accessibilityIdentifier = "over.photo." + photo.id
        reloadText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reloadText() {
        caption.text = photo.title
        category.text = photo.album.title
        button.accessibilityLabel = [photo.title, photo.album.title].joined(separator: " · ")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 3) {
            image.resizable().aspectRatio(1.35, contentMode: .fit).padding(.bottom, 4)
            caption
            category
        }
        .overlay { button.resizable() }
    }
}

@available(iOS 17.0, *)
#Preview { UINavigationController(rootViewController: OverPresentationExampleViewController()) }
