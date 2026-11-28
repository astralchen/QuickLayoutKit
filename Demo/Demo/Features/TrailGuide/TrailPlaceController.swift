import QuickLayoutKit
import QuickLook
import UIKit

final class TrailPlaceController: LocalizedQuickLayoutHostingController, QLPreviewControllerDataSource {
    private let photo: JournalPhoto
    private let scroll = QuickLayoutScrollView()
    private let image = UIImageView()
    private let section = JournalLabel(.subheadline, color: .secondaryLabel)
    private let name = JournalLabel(.title1)
    private let notes = JournalLabel(.body)
    private let save = UIButton(type: .system)
    private let preview = UIButton(type: .system)

    init(photo: JournalPhoto) {
        self.photo = photo
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        image.image = photo.thumbnail
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 14
        name.accessibilityTraits.insert(.header)
        save.accessibilityIdentifier = "trail.toggle"
        preview.accessibilityIdentifier = "trail.preview"
        save.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            TrailItinerary.toggle(photo)
            updateSaveButton()
            UIAccessibility.post(notification: .announcement, argument: save.accessibilityValue)
        }, for: .touchUpInside)
        preview.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let viewer = QLPreviewController()
            viewer.dataSource = self
            present(viewer, animated: true)
        }, for: .touchUpInside)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        title = Localization.text("trail.place")
        name.text = photo.title
        section.text = photo.album.title
        notes.text = Localization.text("trail.note." + photo.id)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = Localization.text("trail.preview")
        configuration.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        configuration.imagePadding = 8
        preview.configuration = configuration
        updateSaveButton()
    }

    private func updateSaveButton() {
        let saved = TrailItinerary.photos.contains(photo)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .systemTeal
        configuration.title = Localization.text(saved ? "trail.remove" : "trail.add")
        configuration.image = UIImage(systemName: saved ? "bookmark.fill" : "bookmark")
        configuration.imagePadding = 8
        save.configuration = configuration
        save.accessibilityValue = Localization.text(saved ? "trail.saved" : "trail.unsaved")
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 16) {
                image.resizable().aspectRatio(1.65, contentMode: .fit)
                VStack(alignment: .leading, spacing: 4) {
                    section
                    name
                }
                notes
                save.resizable(axis: .horizontal).frame(minHeight: 48)
                preview.resizable(axis: .horizontal).frame(minHeight: 44)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        photo
    }
}
