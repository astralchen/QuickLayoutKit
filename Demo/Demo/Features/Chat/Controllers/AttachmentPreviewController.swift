import AVFoundation
import UIKit
import QuickLayout
import QuickLayoutKit
import ListKit

/// 照片、视频和常用文件共享的全屏玻璃预览容器。
@available(iOS 26.0, *)
final class AttachmentPreviewController: QuickLayoutHostingController, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    /// 仅玻璃交互控件命中，透明区域把手势交给内容页。
    final class ControlsView: QuickLayoutView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            var ancestor = hit
            while let view = ancestor, view !== self {
                if view is UIControl || view is UIScrollView { return hit }
                ancestor = view.superview
            }
            return nil
        }
    }
    let items: [AttachmentPreviewItem]
    private(set) var currentIndex: Int
    let playback: AttachmentPreviewPlayer
    let collectionView: UICollectionView
    let backdrop = UIView()
    /// 控制层与玻璃内容由 QuickLayout 管理，只有转场改变整体 alpha。
    lazy var chrome = ControlsView { [unowned self] in glassContainer.resizable() }
    private lazy var glassContainer = QuickLayoutVisualEffectView(effect: UIGlassContainerEffect()) { [unowned self] in
        VStack(spacing: 0) {
            ZStack {
                titleGlass.resizable().frame(width: titleWidth, height: titleHeight)
                HStack(spacing: 0) {
                    closeButton.resizable().frame(width: 44, height: 44)
                    Spacer()
                    moreButton.resizable().frame(width: 44, height: 44)
                }
            }.frame(height: titleHeight)
            Spacer()
            if bottomHeight > 0 {
                bottomGlass.resizable()
                    .frame(width: min(560, max(0, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 32)), height: bottomHeight)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        .safeAreaPadding(.all, 0)
    }
    private lazy var titleGlass = QuickLayoutVisualEffectView(effect: UIGlassEffect(style: .regular)) { [unowned self] in
        VStack(spacing: 2) {
            titleLabel.resizable(axis: .horizontal).frame(height: titleLabel.font.lineHeight)
            positionLabel.resizable(axis: .horizontal).frame(height: positionLabel.font.lineHeight)
        }.padding(.horizontal, 16).padding(.vertical, 4)
    }
    private lazy var bottomGlass = QuickLayoutVisualEffectView(effect: UIGlassEffect(style: .regular)) { [unowned self] in
        VStack(spacing: 0) {
            if isPlayable {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        playButton.resizable().frame(width: 44, height: 44)
                        slider.resizable(axis: .horizontal).frame(height: 44)
                        muteButton.resizable().frame(width: 44, height: 44)
                    }
                    timeLabel.resizable(axis: .horizontal).frame(height: 24)
                }.padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 16)
            }
            if items.count > 1 {
                thumbnailStrip.resizable().frame(height: AttachmentThumbnailStripView.preferredHeight)
            }
        }
    }
    private var titleHeight: CGFloat { max(44, titleLabel.font.lineHeight + positionLabel.font.lineHeight + 10) }
    /// 左右各预留相同的按钮与间隔，长文件名和大字号也保持信息胶囊居中。
    private var titleWidth: CGFloat {
        let available = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 32 - 120
        let content = max(titleLabel.intrinsicContentSize.width, positionLabel.intrinsicContentSize.width) + 32
        return min(max(0, available), max(160, content))
    }
    /// 与玻璃标题共享尺寸，避免依赖嵌套宿主完成布局的先后顺序。
    private var documentTopInset: CGFloat { view.safeAreaInsets.top + 20 + titleHeight }
    private var isPlayable: Bool { currentItem?.kind == .audio || currentItem?.kind == .video }
    private var bottomHeight: CGFloat { (isPlayable ? 92 : 0) + (items.count > 1 ? AttachmentThumbnailStripView.preferredHeight : 0) }
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collectionView)

    /// 黑色画布、分页和玻璃控制层共享全屏布局。
    override var body: Layout {
        ZStack {
            backdrop.resizable()
            collectionView.resizable()
            chrome.resizable()
        }
    }
    private let titleLabel = UILabel()
    private let positionLabel = UILabel()
    let closeButton = UIButton(type: .system)
    /// 只包含已有浏览动作的系统菜单，避免为装饰性省略号增加空入口。
    let moreButton = UIButton(type: .system)
    let playButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    let slider = UISlider()
    private let timeLabel = UILabel()
    private lazy var thumbnailStrip: AttachmentThumbnailStripView = {
        let strip = AttachmentThumbnailStripView(items: items, selectedIndex: currentIndex, backgroundStyle: .embedded)
        strip.didSelectItem = { [weak self] index in self?.select(index, animated: true) }
        return strip
    }()
    private var didPosition = false
    private var lastSize = CGSize.zero
    /// 待完成的程序翻页目标；实际当前项仅在停稳后提交。
    private(set) var pendingPageIndex: Int?
    private var isPositioningPage = false
    private var rotationPageIndex: Int?
    private var previousMetrics = AttachmentPagingLayout.Metrics(size: .zero, count: 0)
    let pagingLayout: AttachmentPagingLayout
    /// AppLocalization 可独立于系统语言切换布局方向，缓存物理返回图标方向。
    private var headerDirection: UIUserInterfaceLayoutDirection?
    private(set) var controlsVisible = true
    private var transitionHandler: AttachmentPreviewTransition!
    private var pan: UIPanGestureRecognizer!
    private var didCompleteDismissal = false
    private var accessibilityObservers: [NSObjectProtocol] = []
    /// 当前项目对应的可见来源，转场发生时重新求值。
    var sourceResolver: ((Int, Bool) -> UIView?)?
    /// 关闭成功后恢复编辑器和辅助功能焦点。
    var didClose: (() -> Void)?

    init(items: [AttachmentPreviewItem], initialIndex: Int, playbackCoordinator: PlaybackCoordinator) {
        self.items = items
        currentIndex = AttachmentPreviewPolicy.index(initialIndex, count: items.count)
        playback = AttachmentPreviewPlayer(coordinator: playbackCoordinator)
        let layout = AttachmentPagingLayout()
        pagingLayout = layout
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitionHandler = AttachmentPreviewTransition(preview: self)
        transitioningDelegate = transitionHandler
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { !controlsVisible }
    var currentItem: AttachmentPreviewItem? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    var currentPage: AttachmentPreviewPage? { collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? AttachmentPreviewPage }

    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .disabled
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "imessage.preview"
        view.accessibilityViewIsModal = true
        backdrop.backgroundColor = .black
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = false
        collectionView.decelerationRate = .fast
        collectionView.alwaysBounceHorizontal = items.count > 1
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        // Preserve the attachment's physical order, matching the existing stack gesture.
        collectionView.semanticContentAttribute = .forceLeftToRight
        bottomGlass.overrideUserInterfaceStyle = .dark
        for glass in [titleGlass, bottomGlass] {
            glass.clipsToBounds = true
            glass.layer.cornerCurve = .continuous
            glass.layer.cornerRadius = 28
        }
        titleGlass.cornerConfiguration = .capsule()
        configureButton(closeButton, symbol: "chevron.backward", key: "imessage.media.close", identifier: "imessage.media.preview.close")
        closeButton.configuration?.baseForegroundColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        configureButton(moreButton, symbol: "ellipsis", key: "imessage.preview.more", identifier: "imessage.preview.more")
        moreButton.configuration?.baseForegroundColor = .label
        moreButton.showsMenuAsPrimaryAction = true
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        positionLabel.font = .preferredFont(forTextStyle: .caption1)
        positionLabel.adjustsFontForContentSizeCategory = true
        positionLabel.adjustsFontSizeToFitWidth = true
        positionLabel.minimumScaleFactor = 0.6
        positionLabel.textColor = .secondaryLabel
        positionLabel.textAlignment = .center
        positionLabel.accessibilityIdentifier = "imessage.preview.position"
        titleGlass.accessibilityIdentifier = "imessage.preview.title"
        configureButton(playButton, symbol: "play.fill", key: "imessage.preview.play", identifier: "imessage.preview.play")
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        configureButton(muteButton, symbol: "speaker.wave.2.fill", key: "imessage.preview.mute", identifier: "imessage.preview.mute")
        muteButton.addAction(UIAction { [weak self] _ in guard let self else { return }; playback.isMuted.toggle() }, for: .touchUpInside)
        slider.accessibilityLabel = Localization.text("imessage.preview.progress")
        slider.accessibilityIdentifier = "imessage.preview.progress"
        slider.semanticContentAttribute = .forceLeftToRight
        slider.addTarget(self, action: #selector(seekBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(seekEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        playback.didChange = { [weak self] in self?.refreshPlayback() }
        playback.didFail = { [weak self] in self?.currentPage?.showError() }
        pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
        for name in [UIAccessibility.reduceTransparencyStatusDidChangeNotification, UIAccessibility.reduceMotionStatusDidChangeNotification, UIAccessibility.voiceOverStatusDidChangeNotification] {
            accessibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyAccessibilitySettings() }
            })
        }
        adapter.collectionDelegate = self
        adapter.scrollDelegate = self
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                ListKit.ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                    Row(entry.element.id, model: entry.element, cell: AttachmentPreviewPage.self) { [weak self] page, item, _ in
                        self?.configure(page, item: item, index: entry.offset)
                    }
                }
            }.selectionMode(.none)
        }
        applyAccessibilitySettings()
        updateCurrentItem()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = collectionView.bounds.size
        if size.width > 0, size.height > 0, !isPositioningPage, lastSize != size || !didPosition {
            let index = rotationPageIndex ?? pendingPageIndex ?? (pagingLayout.dragStartIndex != nil
                ? previousMetrics.index(nearestTo: collectionView.contentOffset) : currentIndex)
            lastSize = size
            didPosition = true
            rotationPageIndex = nil
            stopHorizontalScrolling()
            pagingLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            previousMetrics = pagingLayout.metrics
            finishPaging(at: index)
        }
        glassContainer.semanticContentAttribute = view.semanticContentAttribute
        let direction = view.effectiveUserInterfaceLayoutDirection
        if headerDirection != direction {
            headerDirection = direction
            closeButton.configuration?.image = UIImage(systemName: direction == .rightToLeft ? "chevron.right" : "chevron.left")
        }
        chrome.layoutIfNeeded()
        glassContainer.setNeedsQuickLayout()
        glassContainer.layoutIfNeeded()
        titleGlass.layoutIfNeeded()
        bottomGlass.layoutIfNeeded()
        for case let page as AttachmentPreviewPage in collectionView.visibleCells {
            page.documentTopInset = documentTopInset
        }
    }

    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); bindCurrentPlayer(); UIAccessibility.post(notification: .screenChanged, argument: closeButton) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if isBeingDismissed { completeDismissal() } }

    /// 仅在成功关闭后清理；交互式取消不能销毁播放状态。
    func completeDismissal() {
        guard !didCompleteDismissal else { return }
        didCompleteDismissal = true
        playback.stop()
        for case let page as AttachmentPreviewPage in collectionView.visibleCells { page.reset() }
        didClose?()
        UIAccessibility.post(notification: .screenChanged, argument: sourceResolver?(currentIndex, false))
    }
    /// ListKit 负责注册、复用和稳定身份；页面只配置附件内容与回调。
    private func configure(_ page: AttachmentPreviewPage, item: AttachmentPreviewItem, index: Int) {
        page.semanticContentAttribute = view.semanticContentAttribute
        page.contentView.semanticContentAttribute = view.semanticContentAttribute
        page.configure(item)
        page.documentTopInset = documentTopInset
        page.toggleControls = { [weak self] in self?.toggleControls() }
        page.pageDidChange = { [weak self] number, count in
            guard let self, currentIndex == index else { return }
            positionLabel.text = String(format: Localization.text("imessage.preview.pages"), number, count)
            glassContainer.setNeedsQuickLayout()
            titleGlass.setNeedsQuickLayout()
        }
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? AttachmentPreviewPage)?.documentTopInset = documentTopInset
        if indexPath.item == currentIndex { (cell as? AttachmentPreviewPage)?.bind(player: playback.player) }
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) { (cell as? AttachmentPreviewPage)?.bind(player: nil) }
    /// 旋转前使用旧尺寸确定锚点；程序翻页保留目标，手势翻页保留最近可见项。
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        rotationPageIndex = pendingPageIndex ?? pagingLayout.index(nearestTo: collectionView.contentOffset)
        stopHorizontalScrolling()
        super.viewWillTransition(to: size, with: coordinator)
    }
    var isHorizontalPaging: Bool {
        pendingPageIndex != nil || pagingLayout.dragStartIndex != nil || collectionView.isDragging || collectionView.isDecelerating
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView, !isPositioningPage else { return }
        pendingPageIndex = nil
        playback.pause()
        pagingLayout.beginDragging(at: collectionView.contentOffset)
        commitCurrentPage(pagingLayout.index(nearestTo: collectionView.contentOffset))
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }; settlePage()
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === collectionView, let target = pendingPageIndex,
              abs(scrollView.contentOffset.x - pagingLayout.offset(for: target).x) < 0.5 else { return }
        // 被新跳转替换的旧动画可能迟到结束；只有当前目标抵达时才提交。
        settlePage()
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === collectionView, !decelerate else { return }; settlePage()
    }
    private func settlePage() {
        guard !isPositioningPage, collectionView.bounds.width > 0 else { return }
        finishPaging(at: pendingPageIndex ?? pagingLayout.dragTargetIndex ?? pagingLayout.index(nearestTo: collectionView.contentOffset))
    }
    /// 取消旧动画及拖动，屏蔽取消过程中 UIKit 同步发出的结束回调。
    private func stopHorizontalScrolling() {
        isPositioningPage = true
        pendingPageIndex = nil
        pagingLayout.endDragging()
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        if collectionView.isTracking || collectionView.isDragging {
            collectionView.panGestureRecognizer.isEnabled = false
            collectionView.panGestureRecognizer.isEnabled = true
        }
        isPositioningPage = false
    }
    private func commitCurrentPage(_ index: Int) {
        let index = AttachmentPreviewPolicy.index(index, count: items.count)
        guard index != currentIndex else { return }
        playback.stop()
        currentPage?.bind(player: nil)
        currentIndex = index
        updateCurrentItem()
    }
    /// 所有滚动结束路径共用精确停页与当前附件同步。
    private func finishPaging(at index: Int) {
        isPositioningPage = true
        pendingPageIndex = nil
        pagingLayout.endDragging()
        collectionView.setContentOffset(pagingLayout.offset(for: index), animated: false)
        commitCurrentPage(index)
        collectionView.layoutIfNeeded()
        bindCurrentPlayer()
        isPositioningPage = false
    }
    /// 缩略图与菜单使用布局提供的坐标，连续跳转会替换旧目标。
    func select(_ index: Int, animated: Bool) {
        loadViewIfNeeded()
        collectionView.layoutIfNeeded()
        let index = AttachmentPreviewPolicy.index(index, count: items.count)
        stopHorizontalScrolling()
        let target = pagingLayout.offset(for: index)
        if animated, !UIAccessibility.isReduceMotionEnabled, view.window != nil, abs(target.x - collectionView.contentOffset.x) > 0.5 {
            playback.pause()
            pendingPageIndex = index
            collectionView.setContentOffset(target, animated: true)
        } else {
            finishPaging(at: index)
        }
    }
    private func updateCurrentItem() {
        guard let item = currentItem else { return }
        titleLabel.text = item.title.isEmpty ? Localization.text(item.kind == .video ? "imessage.media.video" : "imessage.media.image") : item.title
        positionLabel.text = positionText(index: currentIndex)
        updateMoreMenu()
        if item.kind == .video || item.kind == .audio { playback.prepare(url: item.url) }
        thumbnailStrip.select(currentIndex)
        glassContainer.setNeedsQuickLayout()
        titleGlass.setNeedsQuickLayout()
        bottomGlass.setNeedsQuickLayout()
        setNeedsQuickLayout()
        refreshPlayback()
    }
    private func bindCurrentPlayer() { currentPage?.bind(player: playback.player) }
    private func positionText(index: Int) -> String { String(format: Localization.text("imessage.preview.position"), index + 1, items.count) }
    /// 菜单边界跟随当前项目更新，RTL 下使用语义方向图标。
    private func updateMoreMenu() {
        var actions: [UIAction] = []
        if items.count > 1 {
            actions.append(UIAction(title: Localization.text("imessage.preview.previous"), image: UIImage(systemName: "chevron.backward"), attributes: currentIndex == 0 ? .disabled : []) { [weak self] _ in
                guard let self else { return }; select((pendingPageIndex ?? currentIndex) - 1, animated: true)
            })
            actions.append(UIAction(title: Localization.text("imessage.preview.next"), image: UIImage(systemName: "chevron.forward"), attributes: currentIndex == items.count - 1 ? .disabled : []) { [weak self] _ in
                guard let self else { return }; select((pendingPageIndex ?? currentIndex) + 1, animated: true)
            })
        }
        actions.append(UIAction(title: Localization.text("imessage.preview.hideControls"), image: UIImage(systemName: "rectangle"), attributes: UIAccessibility.isVoiceOverRunning ? .disabled : []) { [weak self] _ in self?.toggleControls() })
        moreButton.menu = UIMenu(children: actions)
    }
    private func configureButton(_ button: UIButton, symbol: String, key: String, identifier: String) {
        var config = UIButton.Configuration.glass()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        button.configuration = config
        button.accessibilityLabel = Localization.text(key)
        button.accessibilityIdentifier = identifier
    }
    private func refreshPlayback() {
        playButton.configuration?.image = UIImage(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
        playButton.accessibilityLabel = Localization.text(playback.isPlaying ? "imessage.preview.pause" : "imessage.preview.play")
        muteButton.configuration?.image = UIImage(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        muteButton.accessibilityLabel = Localization.text(playback.isMuted ? "imessage.preview.unmute" : "imessage.preview.mute")
        if !playback.isSeeking { slider.value = playback.duration > 0 ? Float(playback.time / playback.duration) : 0 }
        slider.isEnabled = playback.duration > 0
        timeLabel.text = "\(Self.time(playback.time)) / \(Self.time(playback.duration))"
        slider.accessibilityValue = timeLabel.text
        bindCurrentPlayer()
    }
    private static func time(_ value: Double) -> String { let seconds = Int(max(0, value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    @objc func playTapped() {
        if playback.player == nil, let item = currentItem { playback.prepare(url: item.url) }
        playback.toggle()
    }
    @objc private func seekBegan() { playback.beginSeeking() }
    @objc private func seekChanged() {
        // VoiceOver adjusts sliders without touch-down/up events.
        playback.seek(fraction: Double(slider.value), finished: !slider.isTracking && !playback.isSeeking)
    }
    @objc private func seekEnded() {
        guard playback.isSeeking else { return }
        playback.seek(fraction: Double(slider.value), finished: true)
    }
    @objc func closeTapped() {
        guard !transitionHandler.isInteracting, !isBeingDismissed else { return }
        let index = pagingLayout.index(nearestTo: collectionView.contentOffset)
        stopHorizontalScrolling()
        finishPaging(at: index)
        dismiss(animated: true)
    }
    override func accessibilityPerformEscape() -> Bool { closeTapped(); return true }
    private func toggleControls() {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        controlsVisible.toggle()
        chrome.isUserInteractionEnabled = controlsVisible
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.22) { self.chrome.alpha = self.controlsVisible ? 1 : 0 }
        setNeedsStatusBarAppearanceUpdate()
    }
    private func applyAccessibilitySettings() {
        updateMoreMenu()
        for glass in [titleGlass, bottomGlass] {
            glass.effect = UIAccessibility.isReduceTransparencyEnabled ? nil : UIGlassEffect(style: .regular)
            glass.backgroundColor = UIAccessibility.isReduceTransparencyEnabled ? .secondarySystemBackground : .clear
        }
        if UIAccessibility.isVoiceOverRunning { controlsVisible = true; chrome.alpha = 1; chrome.isUserInteractionEnabled = true }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return true }
        let velocity = pan.velocity(in: view)
        return !isHorizontalPaging && velocity.y > abs(velocity.x) * 1.2 && currentPage?.permitsDismissal == true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let view = target {
            if view is UIControl || view === chrome { return false }
            target = view.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && otherGestureRecognizer is UIPanGestureRecognizer && currentPage?.permitsDismissal == true
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began: transitionHandler.begin()
        case .changed: transitionHandler.update(translation: translation)
        case .ended: transitionHandler.end(translation: translation, velocity: gesture.velocity(in: view))
        case .cancelled, .failed: transitionHandler.cancel()
        default: break
        }
    }
    isolated deinit { accessibilityObservers.forEach(NotificationCenter.default.removeObserver) }
}

#if DEBUG
@available(iOS 26.0, *)
#Preview("附件预览 · Liquid Glass") {
    AttachmentPreviewController(items: ConversationPreviewData.attachmentPreviewItems, initialIndex: 0, playbackCoordinator: PlaybackCoordinator())
}
#endif
