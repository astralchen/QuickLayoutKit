import ListKit
import Photos
import QuickLayoutKit
import UIKit

/// 用同一套图片网格显示内置图片和用户授权访问的图库照片。
@MainActor
final class AlertExampleImages: QuickLayoutHostingController {
    @MainActor struct Item {
        let id: String
        let title: String
        let image: UIImage?
        let asset: PHAsset?

        init(id: String, title: String, image: UIImage) {
            self.id = id
            self.title = title
            self.image = image
            asset = nil
        }

        init(asset: PHAsset, number: Int) {
            id = asset.localIdentifier
            title = Localization.text("demo.alertExamples.images.photo", number)
            image = nil
            self.asset = asset
        }
    }

    private let multiple: Bool
    private let usesLibrary: Bool
    private let didSelect: ([Item]) -> Void
    private var items: [Item]
    private(set) var selectedItems: [Item] = []
    private var didLoadLibrary = false
    private let paging: Bool
    private let imageManager = PHCachingImageManager()
    private let status = LocalizedLabel()
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    private lazy var adapter = CollectionListAdapter<Int>(collectionView: grid)

    init(items: [Item], multiple: Bool, paging: Bool, usesLibrary: Bool = false,
         didSelect: @escaping ([Item]) -> Void) {
        self.items = items
        self.multiple = multiple
        self.paging = paging
        self.usesLibrary = usesLibrary
        self.didSelect = didSelect
        super.init(nibName: nil, bundle: nil)
        preferredContentSize.height = paging ? 192 : 254
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        grid.collectionViewLayout = adapter.makeCompositionalLayout(configuration: .init(
            scrollDirection: paging ? .horizontal : .vertical,
            contentInsetsReference: .none
        ))
        grid.contentInsetAdjustmentBehavior = .never
        grid.isPagingEnabled = paging
        grid.accessibilityIdentifier = "alerts.photos.grid"
        grid.backgroundColor = .clear
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.text = Localization.text("demo.alertExamples.images.loading")
        status.isHidden = !usesLibrary
        renderImages()
    }

    override var body: Layout {
        VStack(spacing: 6) {
            if !status.isHidden { status.resizable(axis: .horizontal) }
            grid.resizable()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard usesLibrary, !didLoadLibrary else { return }
        didLoadLibrary = true
        loadLibrary()
    }

    private func loadLibrary() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            Task { @MainActor [weak self] in
                let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                self?.applyAuthorization(result)
            }
        } else {
            applyAuthorization(status)
        }
    }

    private func applyAuthorization(_ authorization: PHAuthorizationStatus) {
        defer { setNeedsQuickLayout() }
        guard authorization == .authorized || authorization == .limited else {
            status.text = Localization.text("demo.alertExamples.images.denied")
            return
        }
        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        items = (0..<assets.count).map { Item(asset: assets.object(at: $0), number: $0 + 1) }
        status.text = Localization.text("demo.alertExamples.images.empty")
        status.isHidden = !items.isEmpty
        renderImages()
    }

    private func renderImages() {
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                ListKit.ForEach(items, id: \.id) { item in
                    Row(model: item, cell: PhotoCell.self) { [weak self] cell, item, context in
                        self?.configure(cell, with: item, index: context.indexPath.item)
                    }
                    .onSelectionChange { [weak self] item, selected, _ in
                        self?.updateSelection(of: item, selected: selected)
                    }
                }
            }
            .selectionMode(multiple ? .multiple : .single)
            .layout {
                if paging {
                    GridLayout(tracks: 1)
                        .itemMainAxisSize(.fractionalViewport(1))
                } else {
                    GridLayout(tracks: 3)
                        .itemMainAxisSize(.aspectRatio(1))
                        .trackSpacing(6)
                        .lineSpacing(6)
                }
            }
        }
    }

    private func configure(_ cell: PhotoCell, with item: Item, index: Int) {
        cell.accessibilityLabel = item.title
        cell.accessibilityIdentifier = "alerts.photo.\(index)"
        cell.assetID = item.asset?.localIdentifier
        cell.imageView.image = item.image
        if let asset = item.asset {
            let id = asset.localIdentifier
            imageManager.requestImage(for: asset, targetSize: CGSize(width: 480, height: 480),
                                      contentMode: .aspectFill, options: nil) { [weak cell] image, _ in
                Task { @MainActor in
                    guard let cell, cell.assetID == id else { return }
                    cell.imageView.image = image
                }
            }
        }
    }

    private func updateSelection(of item: Item, selected: Bool) {
        if multiple {
            if selected {
                selectedItems.append(item)
            } else {
                selectedItems.removeAll { $0.id == item.id }
            }
        } else if selected {
            selectedItems = [item]
        } else {
            return
        }
        didSelect(selectedItems)
    }

    private final class PhotoCell: QuickLayoutCollectionViewCell {
        let imageView = UIImageView()
        var assetID: String?
        private let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

        override var body: Layout {
            imageView.resizable().overlay(alignment: .bottomTrailing) {
                checkmark.resizable().frame(width: 20, height: 20).padding(4)
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityTraits = .button
            contentView.clipsToBounds = true
            contentView.layer.cornerRadius = 10
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            checkmark.isHidden = true
            checkmark.tintColor = .systemBlue
            checkmark.backgroundColor = .systemBackground
            checkmark.layer.cornerRadius = 10
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func prepareForReuse() {
            super.prepareForReuse()
            assetID = nil
            imageView.image = nil
        }

        override var isSelected: Bool {
            didSet {
                checkmark.isHidden = !isSelected
                accessibilityTraits = isSelected ? [.button, .selected] : .button
            }
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("图片多选 · 网格") {
    AlertExamplesViewController.preview(.imagePicker, imageMode: .multiple)
}

@available(iOS 17.0, *)
#Preview("图片单选 · 分页") {
    AlertExamplesViewController.preview(.imagePicker, imageMode: .pages)
}
#endif
