import QuickLayoutKit
import UIKit

final class NavigationGuideView: QuickLayoutScrollView, UIScrollViewDelegate {
    let settings = NavigationGuideSettings()
    let toolbar: NavigationRouteToolbar
    var canAdvanceCover: (() -> Bool)?

    private let cover: RouteCover
    private let photoBackground = NavigationGuideCard()
    private let routes: NavigationRouteList
    private static let coverInterval: TimeInterval = 5
    private var coverTimer: Timer?
    private lazy var guideTouch = GuideTouchObserver(target: self, action: #selector(guideTouchChanged))

    init(photos: [JournalPhoto], toolbar: NavigationRouteToolbar,
         onPageChange: @escaping (JournalPhoto) -> Void, onRouteSelected: @escaping (JournalPhoto) -> Void) {
        self.toolbar = toolbar
        cover = RouteCover(.guide, photos: photos, onPageChange: onPageChange)
        routes = NavigationRouteList(photos: photos, onSelect: onRouteSelected)
        super.init(frame: .zero)
        delegate = self
        guideTouch.minimumPressDuration = 0
        guideTouch.cancelsTouchesInView = false
        guideTouch.delaysTouchesEnded = false
        addGestureRecognizer(guideTouch)
        cover.photoPager.onPagingSettled = { [weak self] in self?.resetCoverInterval() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(photo: JournalPhoto, position: Int, total: Int, saved: Set<String>, query: String) {
        resetCoverInterval()
        cover.configure(photo, position: position, total: total)
        toolbar.configure(position: position, count: total, saved: saved.contains(photo.id))
        routes.configure(selected: photo, saved: saved, query: query)
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 18) {
            if !routes.isFiltering {
                coverLayout
                settings.resizable(axis: .horizontal)
            }
            routes.resizable(axis: .horizontal)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    @LayoutBuilder private var coverLayout: Layout {
        if #available(iOS 26.0, *) {
            cover.resizable(axis: .horizontal)
                .overlay(alignment: .top) {
                    toolbar.resizable().frame(height: 52)
                        .padding(.top, 6)
                }
        } else {
            VStack(spacing: 0) {
                cover.resizable(axis: .horizontal)
                toolbar.resizable().frame(height: 48)
            }
            .background { photoBackground.resizable() }
        }
    }

    func startAutomaticPaging(in scene: UIWindowScene) {
        guard coverTimer == nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(coverSceneActivated(_:)),
                                               name: UIScene.didActivateNotification, object: scene)
        let timer = Timer(timeInterval: Self.coverInterval, target: self, selector: #selector(advanceCover), userInfo: nil, repeats: true)
        coverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        resetCoverInterval()
    }

    func stopAutomaticPaging() {
        cover.photoPager.cancelAutomaticAdvance()
        coverTimer?.invalidate()
        coverTimer = nil
        NotificationCenter.default.removeObserver(self, name: UIScene.didActivateNotification, object: nil)
    }

    @objc private func coverSceneActivated(_ notification: Notification) {
        resetCoverInterval()
    }

    private func resetCoverInterval() {
        coverTimer?.fireDate = Date(timeIntervalSinceNow: Self.coverInterval)
    }

    @objc private func guideTouchChanged() {
        switch guideTouch.state {
        case .began: cover.photoPager.interruptAutomaticAdvance()
        case .ended, .cancelled:
            cover.photoPager.settleInterruptedAdvance()
            resetCoverInterval()
        default: break
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resetCoverInterval() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { resetCoverInterval() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { resetCoverInterval() }

    @objc private func advanceCover() {
        guard window?.windowScene?.activationState == .foregroundActive,
              canAdvanceCover?() == true, !routes.isFiltering,
              !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isReduceMotionEnabled,
              guideTouch.state != .began, guideTouch.state != .changed,
              !isTracking, !isDragging, !isDecelerating, !cover.photoPager.isPagingInteractively,
              cover.window != nil, bounds.inset(by: adjustedContentInset)
                .intersects(cover.convert(cover.bounds, to: self)) else { return }
        cover.photoPager.advanceAutomatically()
    }
}

final class NavigationGuideCard: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// 只观察手指按下和离开，让分页、滚动及工具栏继续接收原有手势。
private final class GuideTouchObserver: UILongPressGestureRecognizer {
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}
