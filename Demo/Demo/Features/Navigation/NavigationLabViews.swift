import QuickLayoutKit
import UIKit

final class RouteCover: QuickLayoutView {
    enum Presentation { case guide, fullScreen }

    private let presentation: Presentation
    let photoPager: RoutePhotoPager

    private let shade = QuickLayoutLinearGradientView(colors: [.clear, .black.withAlphaComponent(0.78)])
    private let category = JournalLabel(.subheadline, color: .white)
    private let name = JournalLabel(.largeTitle, color: .white)

    init(_ presentation: Presentation, photos: [JournalPhoto], onPageChange: @escaping (JournalPhoto) -> Void = { _ in }) {
        self.presentation = presentation
        photoPager = RoutePhotoPager(photos: photos, presentation: presentation, onPageChange: onPageChange)
        super.init(frame: .zero)
        backgroundColor = .darkGray
        clipsToBounds = true
        layer.cornerRadius = presentation == .guide ? 16 : 0
        layer.cornerCurve = .continuous
        if #unavailable(iOS 26.0) {
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
        shade.isUserInteractionEnabled = false
        let descriptor = UIFont.systemFont(ofSize: 34, weight: .semibold).fontDescriptor
        name.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(
            descriptor: descriptor.withDesign(.serif) ?? descriptor, size: 34
        ))
        name.accessibilityTraits.insert(.header)
        name.accessibilityIdentifier = "navLab.featured"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ photo: JournalPhoto, position: Int, total: Int) {
        photoPager.select(photo)
        category.text = "\(photo.album.title)  ·  \(position.formatted()) / \(total.formatted())"
        name.text = photo.title
        setNeedsQuickLayout()
    }

    private var toolbarSpace: CGFloat {
        if #available(iOS 26.0, *), presentation == .guide { return 54 }
        return 0
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 4) {
            category
            name
        }
        .padding(18)
        .padding(.top, toolbarSpace)
        .frame(maxWidth: .infinity, minHeight: 178 + toolbarSpace, maxHeight: presentation == .guide ? nil : .infinity, alignment: .bottomLeading)
        .background {
            photoPager.resizable().overlay { shade.resizable() }
        }
    }
}

/// 在照片允许翻页的方向上接管单指横滑。
final class RoutePhotoPager: UIScrollView, UIScrollViewDelegate {
    var isPagingInteractively: Bool { isTracking || isDragging || isDecelerating }
    var onPagingSettled: (() -> Void)?
    private let photos: [JournalPhoto]
    private let pages: [RoutePhotoScrollView]
    private let onPageChange: (JournalPhoto) -> Void
    private var selectedIndex = 0 {
        didSet { pages[oldValue].recenter() }
    }
    private var viewport: CGSize = .zero
    private var rightToLeft = false
    private var automaticTarget: Int?
    private var automaticAdvanceInterrupted = false

    init(photos: [JournalPhoto], presentation: RouteCover.Presentation, onPageChange: @escaping (JournalPhoto) -> Void) {
        self.photos = photos
        self.onPageChange = onPageChange
        pages = photos.map { _ in RoutePhotoScrollView(presentation: presentation) }
        super.init(frame: .zero)
        delegate = self
        isPagingEnabled = true
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        panGestureRecognizer.maximumNumberOfTouches = 1
        accessibilityIdentifier = presentation == .guide ? "navLab.coverPager" : "navLab.photoPager"
        pages.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        guard viewport != bounds.size || rtl != rightToLeft else { return }
        viewport = bounds.size
        rightToLeft = rtl
        interruptAutomaticAdvance()
        automaticTarget = nil
        automaticAdvanceInterrupted = false
        contentInset = .zero
        contentSize = CGSize(width: viewport.width * CGFloat(pages.count), height: viewport.height)
        for (index, page) in pages.enumerated() {
            page.frame = CGRect(origin: CGPoint(x: offset(for: index), y: 0), size: viewport)
        }
        showSelectedPage()
    }

    func select(_ photo: JournalPhoto) {
        cancelAutomaticAdvance()
        guard let index = photos.firstIndex(of: photo), index != selectedIndex else { return }
        selectedIndex = index
        showSelectedPage()
    }

    func advanceAutomatically() {
        guard photos.count > 1, viewport.width > 0, automaticTarget == nil else { return }
        let next = (selectedIndex + 1) % photos.count
        automaticTarget = next
        var destination = offset(for: next)
        if next == 0 {
            // Temporarily place the first photo one slot beyond the last, including in RTL.
            destination = offset(for: photos.count)
            var inset = UIEdgeInsets.zero
            if rightToLeft { inset.left = viewport.width } else { inset.right = viewport.width }
            contentInset = inset
            pages[0].frame.origin.x = destination
            pages[0].display(photos[0])
        }
        setContentOffset(CGPoint(x: destination, y: 0), animated: true)
    }

    func interruptAutomaticAdvance() {
        guard automaticTarget != nil, !automaticAdvanceInterrupted else { return }
        // UIKit can deliver the animation completion synchronously while stopping.
        automaticAdvanceInterrupted = true
        setContentOffset(contentOffset, animated: false)
    }

    func settleInterruptedAdvance() {
        if automaticTarget != nil, !isDragging, !isDecelerating { finishPaging() }
    }

    func cancelAutomaticAdvance() {
        guard automaticTarget != nil else { return }
        interruptAutomaticAdvance()
        restorePagePositions()
        showSelectedPage()
    }

    private func restorePagePositions() {
        if automaticTarget == 0 {
            pages[0].frame.origin.x = offset(for: 0)
            contentInset = .zero
        }
        automaticTarget = nil
        automaticAdvanceInterrupted = false
    }

    private func offset(for index: Int) -> CGFloat {
        CGFloat(rightToLeft ? pages.count - 1 - index : index) * viewport.width
    }

    private func showSelectedPage() {
        guard viewport.width > 0, pages.indices.contains(selectedIndex) else { return }
        setContentOffset(CGPoint(x: offset(for: selectedIndex), y: 0), animated: false)
        prepareVisiblePages()
    }

    private func prepareVisiblePages() {
        let nearby = bounds.insetBy(dx: -viewport.width, dy: 0)
        for (index, page) in pages.enumerated() where nearby.intersects(page.frame) {
            page.display(photos[index])
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { prepareVisiblePages() }

    private func finishPaging() {
        defer { onPagingSettled?() }
        guard viewport.width > 0 else { return }
        let slot = Int((contentOffset.x / viewport.width).rounded())
        let logicalSlot = rightToLeft ? pages.count - 1 - slot : slot
        let index = automaticTarget == 0 && logicalSlot == pages.count ? 0 : logicalSlot
        guard pages.indices.contains(index) else { cancelAutomaticAdvance(); return }
        let changed = index != selectedIndex
        guard changed || automaticTarget != nil else { return }
        restorePagePositions()
        if changed { selectedIndex = index }
        showSelectedPage()
        if changed { onPageChange(photos[index]) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishPaging() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if !automaticAdvanceInterrupted { finishPaging() }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishPaging() }
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.y) > abs(velocity.x) { return false }
            if pages.indices.contains(selectedIndex), !pages[selectedIndex].allowsPaging(velocityX: velocity.x) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }
}

/// 按视口等比铺满原图，只让超出视口的部分参与滚动。
private final class RoutePhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private let presentation: RouteCover.Presentation
    private let imageView = UIImageView()
    private var photo: JournalPhoto?
    private var laidOutSize: CGSize = .zero

    init(presentation: RouteCover.Presentation) {
        self.presentation = presentation
        super.init(frame: .zero)
        isUserInteractionEnabled = presentation == .fullScreen
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        accessibilityIdentifier = "navLab.photoScroll"
        addSubview(imageView)
        if presentation == .fullScreen {
            delegate = self
            maximumZoomScale = 4
            bouncesZoom = false
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            tap.numberOfTapsRequired = 2
            addGestureRecognizer(tap)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func display(_ photo: JournalPhoto) {
        guard self.photo !== photo else { return }
        self.photo = photo
        switch presentation {
        case .guide: imageView.image = photo.thumbnail
        case .fullScreen: imageView.image = photo.previewItemURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? photo.thumbnail
        }
        recenter()
    }

    func recenter() {
        if isDragging || isDecelerating {
            isScrollEnabled = false
            isScrollEnabled = true
        }
        laidOutSize = .zero
        setNeedsLayout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updatePanTouchCount()
    }

    private func updatePanTouchCount() {
        let needsTwoFingers = zoomScale == minimumZoomScale && imageView.bounds.width > bounds.width
        panGestureRecognizer.minimumNumberOfTouches = needsTwoFingers ? 2 : 1
    }

    @objc private func toggleZoom(_ tap: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: animated)
        } else {
            let point = tap.location(in: imageView)
            let size = CGSize(width: bounds.width / 2, height: bounds.height / 2)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: animated)
        }
    }

    func allowsPaging(velocityX: CGFloat) -> Bool {
        if isZooming { return false }
        if zoomScale <= minimumZoomScale { return true }
        if velocityX > 0 { return contentOffset.x <= 1 }
        return velocityX < 0 && contentOffset.x >= contentSize.width - bounds.width - 1
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === panGestureRecognizer, panGestureRecognizer.numberOfTouches == 1 {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.x) >= abs(velocity.y), allowsPaging(velocityX: velocity.x) { return false }
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let viewport = bounds.size
        guard viewport != laidOutSize, viewport.width > 0, viewport.height > 0 else { return }
        laidOutSize = viewport
        if zoomScale != minimumZoomScale { setZoomScale(minimumZoomScale, animated: false) }
        var size = viewport
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            let aspect = image.size.width / image.size.height
            if viewport.width / viewport.height < aspect {
                size.width = viewport.height * aspect
            } else {
                size.height = viewport.width / aspect
            }
        }
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        updatePanTouchCount()
        contentOffset = CGPoint(x: (size.width - viewport.width) / 2, y: (size.height - viewport.height) / 2)
    }
}
