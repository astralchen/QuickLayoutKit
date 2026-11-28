import QuickLayoutKit
import QuickLook
import UIKit

final class TrailPlaceController: LocalizedQuickLayoutHostingController, QLPreviewControllerDataSource {
    private let photo: JournalPhoto
    private let scroll = QuickLayoutScrollView()
    private let inlineImage = UIImageView()
    private let paneImage = UIImageView()
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
        scroll.accessibilityIdentifier = "trail.place.scroll"
        for image in [inlineImage, paneImage] {
            image.image = photo.thumbnail
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 14
        }
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
        GeometryReader { [self] viewport in
            pageLayout(in: viewport)
        }
        .safeAreaPadding(0)
    }

    private func pageLayout(in viewport: GeometryProxy) -> Layout {
        let divided: Bool
        if #available(iOS 27.1, *) {
            let bounds = CGRect(origin: .zero, size: viewport.size)
            divided = viewport.reservedRegions(kind: .division).contains { region in
                let cut = bounds.intersection(region.frame)
                return !cut.isEmpty && (
                    (cut.height == bounds.height && cut.minX > 0 && cut.maxX < bounds.width)
                    || (cut.width == bounds.width && cut.minY > 0 && cut.maxY < bounds.height)
                )
            }
        } else {
            divided = false
        }
        return ArrangementView {
            ScrollView(scroll) {
                if divided {
                    details.frame(maxWidth: 680).padding(.horizontal, 20).frame(maxWidth: .infinity)
                } else {
                    readingLayout.padding(.horizontal, 20).frame(maxWidth: .infinity)
                }
            }
            .contentMargins(.vertical, 20, for: .scrollContent)
            .overlayArrangementEdge(HorizontalEdge.trailing)
            .overlayArrangementEdge(VerticalEdge.bottom)
        } secondary: {
            if divided {
                paneImage.resizable().aspectRatio(1.65, contentMode: .fit).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .arrangementViewStyle(.overlay)
    }

    private var readingLayout: Layout {
        let photograph = inlineImage.resizable().aspectRatio(1.65, contentMode: .fit)
        return ViewThatFits(in: .horizontal) {
            if !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
                HStack(alignment: .top, spacing: 24) {
                    photograph.frame(minWidth: 300, idealWidth: 300, maxWidth: .infinity)
                    details.frame(minWidth: 300, idealWidth: 300, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                photograph
                details
            }
            .frame(maxWidth: 680)
        }
        .frame(maxWidth: 1040)
    }

    private var details: Layout {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                section
                name
            }
            notes
            save.resizable(axis: .horizontal).frame(minHeight: 48)
            preview.resizable(axis: .horizontal).frame(minHeight: 44)
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        photo
    }
}
