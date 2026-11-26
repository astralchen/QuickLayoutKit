import QuickLayoutKit
import UIKit

/// 以实景路线手册演示当前页面的导航项目、独立工具栏和系统底部工具栏。
final class NavigationLabViewController: LocalizedQuickLayoutHostingController, UISearchResultsUpdating, UISearchControllerDelegate {
    override var localizedTitleKey: String? { "navLab.guide" }

    private let photos = JournalPhoto.collection
    private let search = UISearchController(searchResultsController: nil)
    private weak var systemPreview: NavigationLabPhotoController?
    private var selectedIndex = 0
    private var saved: Set<String> = []
    private var query = ""
    private var previousLargeTitles: Bool?
    private var guideName: String?

    private lazy var guide = NavigationGuideView(
        photos: photos,
        toolbar: NavigationRouteToolbar(
            onStep: { [weak self] in self?.step($0) },
            onBookmark: { [weak self] in self?.toggleBookmark() }
        ),
        onPageChange: { [weak self] in self?.select($0, scrollToCover: false) },
        onRouteSelected: { [weak self] in self?.select($0) }
    )

    override func viewDidLoad() {
        guide.settings.onChange = { [weak self] setting in
            switch setting {
            case .title: self?.applyTitleMode()
            case .search: self?.applySearchMode()
            case .toolbar: self?.moveToolbar()
            }
        }
        guide.canAdvanceCover = { [weak self] in
            guard let self else { return false }
            return presentedViewController == nil && systemPreview == nil && !search.isActive
        }
        search.delegate = self
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.accessibilityIdentifier = "navLab.search"
        search.searchBar.autocapitalizationType = .none
        definesPresentationContext = true
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setContentScrollView(guide, for: .top)
    }

    private func moveToolbar() {
        guard guide.settings.usesBottomBar else { return }
        let preview = NavigationLabPhotoController(photos: photos, title: guideName ?? Localization.text("navLab.guide")) {
            [weak self] photo in self?.select(photo)
        }
        systemPreview = preview
        guide.toolbar.moveItems(to: preview)
        let navigation = UINavigationController(rootViewController: preview)
        navigation.toolbarVisibility(.visible, for: .bottomBar)
        navigation.modalPresentationStyle = .fullScreen
        refresh()
        present(navigation, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let bar = navigationController?.navigationBar {
            previousLargeTitles = bar.prefersLargeTitles
            bar.prefersLargeTitles = true
        }
        applyTitleMode()
        if guide.settings.usesBottomBar {
            guide.toolbar.restoreItems(from: systemPreview)
            systemPreview = nil
            guide.settings.restoreCoverPosition()
            refresh()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let scene = view.window?.windowScene { guide.startAutomaticPaging(in: scene) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guide.stopAutomaticPaging()
        if let previousLargeTitles { navigationController?.navigationBar.prefersLargeTitles = previousLargeTitles }
        previousLargeTitles = nil
    }

    override var body: Layout {
        guide.contentMargins(.horizontal, 16, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        guide.settings.reloadLabels()
        let title = guideName ?? Localization.text("navLab.guide")
        if #available(iOS 16.0, *) {
            navigationItem.navigationTitle(title) { [weak self] title in self?.guideName = title }
                .toolbarTitleMenu { [weak self] suggested in
                    guard let self else { return nil }
                    let choices = photos.map { photo in
                        UIAction(title: photo.title, state: photo === photos[selectedIndex] ? .on : .off) { [weak self] _ in
                            self?.select(photo)
                        }
                    }
                    return UIMenu(children: suggested + [UIMenu(title: Localization.text("navLab.routes"), children: choices)])
                }
        } else {
            navigationItem.navigationTitle(title)
        }
        applySearchMode()
    }

    private func applyTitleMode() {
        if #available(iOS 17.0, *) {
            navigationItem.toolbarTitleDisplayMode(guide.settings.titleMode)
        } else {
            navigationItem.navigationBarTitleDisplayMode(guide.settings.titleMode)
        }
        guide.scrollTo(.top, animated: false)
    }

    private func applySearchMode() {
        if let placement = guide.settings.searchPlacement {
            navigationItem.searchable(search, placement: placement, prompt: Localization.text("navLab.searchPrompt"))
        } else {
            if search.isActive { search.isActive = false }
            search.searchBar.text = nil
            query = ""
            navigationItem.searchable(nil)
        }
        refresh()
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        refresh()
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        query = ""
        refresh()
    }

    private func select(_ photo: JournalPhoto, scrollToCover: Bool = true) {
        guard let index = photos.firstIndex(where: { $0 === photo }) else { return }
        selectedIndex = index
        if search.isActive {
            search.searchBar.text = nil
            search.isActive = false
        }
        query = ""
        refresh()
        guard scrollToCover else { return }
        guide.scrollTo(.top, animated: false)
    }

    private func step(_ delta: Int) {
        let index = selectedIndex + delta
        if photos.indices.contains(index) { select(photos[index]) }
    }

    private func toggleBookmark() {
        let id = photos[selectedIndex].id
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        refresh()
    }

    private func refresh() {
        let photo = photos[selectedIndex]
        guide.configure(photo: photo, position: selectedIndex + 1, total: photos.count, saved: saved, query: query)
        systemPreview?.cover.configure(photo, position: selectedIndex + 1, total: photos.count)
        if #available(iOS 26.0, *) { navigationItem.navigationSubtitle(photo.album.title) }
        setNeedsQuickLayout()
    }
}

/// 独立的导航栈让系统底部工具栏在折叠分栏及标签页容器中都拥有自己的显示区域。
private final class NavigationLabPhotoController: QuickLayoutHostingController {
    let cover: RouteCover

    init(photos: [JournalPhoto], title: String, onPageChange: @escaping (JournalPhoto) -> Void) {
        cover = RouteCover(.fullScreen, photos: photos, onPageChange: onPageChange)
        super.init(nibName: nil, bundle: nil)
        navigationItem.navigationTitle(title)
        let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        close.accessibilityLabel = Localization.text("common.close")
        close.accessibilityIdentifier = "navLab.closePreview"
        toolbar(placement: .topBarTrailing) { close }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override var body: Layout {
        cover.resizable().safeAreaPadding(.all, 0)
    }
}
