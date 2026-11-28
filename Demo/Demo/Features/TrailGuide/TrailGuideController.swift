import AppLocalization
import QuickLayoutKit
import StickyPagerKit
import UIKit

enum TrailPage: String, CaseIterable {
    case routes, places, itinerary
}

/// 保存加入顺序，让从不同路线选出的看点组成同一份行程。
@MainActor
enum TrailItinerary {
    private static let key = "quicklayoutkit.demo.trail.stops"
    static var photos: [JournalPhoto] {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        return ids.compactMap { id in JournalPhoto.collection.first { $0.id == id } }
    }

    static func toggle(_ photo: JournalPhoto) {
        var ids = photos.map(\.id)
        if ids.contains(photo.id) {
            ids.removeAll { $0 == photo.id }
        } else {
            ids.append(photo.id)
        }
        UserDefaults.standard.set(ids, forKey: key)
    }
}

final class TrailGuideController: PageViewController, PageViewControllerDataSource, UIKitLocalizationApplying {
    private let cover = TrailCoverView()
    private let items = TrailPage.allCases.map { _ in StickyPagerKit.TabBarItem(title: nil) }

    override func viewDidLoad() {
        super.viewDidLoad()
        installLanguageMenu()
        if #unavailable(iOS 26.0) {
            // 旧版导航栏透出页面自己的磨砂层，iOS 26 起沿用系统导航栏的玻璃外观。
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            navigationItem.standardAppearance = appearance
            navigationItem.scrollEdgeAppearance = appearance
            navigationItem.compactAppearance = appearance
            navigationItem.compactScrollEdgeAppearance = appearance
        }
        // 分页容器会裁剪 Header。用它测量滚动位置，在页面上绘制可越过原边界的封面。
        headerView = QuickLayoutView { [weak self] in
            Spacer().frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { [weak self] _ in
                    self?.layoutCover()
                }
        }
        cover.isUserInteractionEnabled = false
        view.addSubview(cover)
        tabBar.layoutConfiguration.itemSizing = .equal
        tabBar.tintColor = .systemTeal
        dataSource = self
        applyLocalization(Localization.currentUIKitUpdate)
        reloadData()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let height = view.safeAreaInsets.top + max(178, cover.captionHeight(for: view.bounds.width) + 54)
        if layout.headerHeight != height { layout = PageLayout(headerHeight: height) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let count = TrailItinerary.photos.count
        items[2].badgeValue = count == 0 ? nil : count.formatted(.number.locale(Localization.localizationController.locale))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCover()
    }

    private func layoutCover() {
        guard let headerView, headerView.window != nil else { return }
        let header = headerView.convert(headerView.bounds, to: view)
        let top = min(header.minY, view.bounds.minY)
        let frame = CGRect(x: header.minX, y: top, width: header.width, height: header.maxY - top)
        if cover.frame != frame { cover.frame = frame }
        let clearance = header.maxY - view.safeAreaLayoutGuide.layoutFrame.minY
        let travel = max(1, header.height - view.safeAreaInsets.top)
        cover.updateAppearance(expandedFraction: min(1, max(0, clearance / travel)), clearance: clearance)
    }

    func applyLocalization(_ update: LocalizationUpdate) {
        guard isViewLoaded else { return }
        Localization.applyBoundary(update.semanticContentAttribute, to: view)
        title = Localization.text("trail.title")
        reloadLanguageMenu()
        cover.configure(photo: JournalAlbum.mountains.photos.first,
                        title: Localization.text("trail.cover"), subtitle: Localization.text("trail.cover.detail"))
        for (page, item) in zip(TrailPage.allCases, items) {
            item.title = Localization.text("trail." + page.rawValue)
        }
        view.setNeedsLayout()
    }

    func numberOfPages(in pageViewController: PageViewController) -> Int { TrailPage.allCases.count }

    func pageViewController(_ pageViewController: PageViewController, identifierForPageAt index: Int) -> AnyHashable {
        TrailPage.allCases[index]
    }

    func pageViewController(_ pageViewController: PageViewController, tabBarItemAt index: Int) -> StickyPagerKit.TabBarItem {
        items[index]
    }

    func pageViewController(_ pageViewController: PageViewController, viewControllerAt index: Int) -> UIViewController {
        TrailListController(scope: .page(TrailPage.allCases[index])) { [weak self] in
            guard let index = TrailPage.allCases.firstIndex(of: .places) else { return }
            self?.setSelectedIndex(index, animated: true)
        }
    }
}

/// 图片填满封面，文字在下沿自然换行，渐变只用于保持照片上的文字对比度。
final class TrailCoverView: QuickLayoutView {
    private let image = UIImageView()
    private let backdropImage = UIImageView()
    private let frost = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let shade = QuickLayoutLinearGradientView(colors: [.clear, .black.withAlphaComponent(0.85)])
    private let heading = JournalLabel(.title1, color: .white)
    private let subtitle = JournalLabel(.subheadline, color: .white)
    private lazy var captions = QuickLayoutView { [heading, subtitle] in
        VStack(alignment: .leading, spacing: 4) {
            heading
            subtitle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaPadding(.horizontal)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .darkGray
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        backdropImage.contentMode = .scaleAspectFill
        backdropImage.clipsToBounds = true
        heading.accessibilityTraits.insert(.header)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(photo: JournalPhoto?, title: String, subtitle: String) {
        image.image = photo?.thumbnail
        backdropImage.image = image.image
        heading.text = title
        self.subtitle.text = subtitle
        captions.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }

    func captionHeight(for width: CGFloat) -> CGFloat {
        captions.sizeThatFits(CGSize(width: width, height: .infinity)).height
    }

    func updateAppearance(expandedFraction: CGFloat, clearance: CGFloat) {
        // 淡出清晰照片，露出下方的材质；效果视图自身始终以完整不透明度渲染。
        image.alpha = expandedFraction
        shade.alpha = expandedFraction
        frost.isHidden = expandedFraction == 1
        captions.alpha = min(1, max(0, (clearance - captions.bounds.height - 18) / 36))
        captions.accessibilityElementsHidden = captions.alpha == 0
    }

    override var body: Layout {
        captions.resizable(axis: .horizontal)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                backdropImage.resizable()
                    .overlay { frost.resizable() }
                    .overlay { image.resizable() }
                    .overlay { shade.resizable() }
            }
    }
}
