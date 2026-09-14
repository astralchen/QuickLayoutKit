import UIKit
import QuickLayout
import QuickLayoutKit

/// 附件缩略图导航控件：封装玻璃背景、选中描边及选中项的可见区域维护。
@available(iOS 26.0, *)
final class AttachmentThumbnailStripView: QuickLayoutView {
    /// 嵌入播放控制胶囊时复用外层材质，避免玻璃叠加。
    enum BackgroundStyle { case glass, embedded }
    static let preferredHeight: CGFloat = 64

    /// 点击只请求切页；宿主停稳后调用 select，保证描边与实际当前附件一致。
    var didSelectItem: ((Int) -> Void)?
    private(set) var selectedIndex: Int?
    private let items: [AttachmentPreviewItem]
    private let backgroundStyle: BackgroundStyle
    private let scrollView = QuickLayoutScrollView(.horizontal, showsIndicators: false)
    private var buttons: [UIButton] = []
    private var needsRevealSelection = true
    private var animatesReveal = false
    private var lastViewportSize = CGSize.zero
    private var transparencyObserver: NSObjectProtocol?
    private lazy var glass = QuickLayoutVisualEffectView(effect: nil) { [unowned self] in
        ScrollView(scrollView, .horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                for button in buttons { button.resizable().frame(width: 44, height: 48) }
            }.padding(.horizontal, 4).padding(.vertical, 8)
        }.padding(.horizontal, 8)
    }

    override var body: Layout { glass.resizable().frame(height: Self.preferredHeight) }

    init(items: [AttachmentPreviewItem], selectedIndex: Int = 0, backgroundStyle: BackgroundStyle = .glass) {
        self.items = items
        self.backgroundStyle = backgroundStyle
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        semanticContentAttribute = .forceLeftToRight
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.contentInsetAdjustmentBehavior = .never
        glass.clipsToBounds = true
        glass.layer.cornerCurve = .continuous
        glass.layer.cornerRadius = 28
        accessibilityIdentifier = "imessage.preview.thumbnails"
        buttons = items.enumerated().map { index, item in
            let button = UIButton(type: .custom)
            button.setImage(item.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }
                ?? UIImage(systemName: item.kind == .video ? "video.fill" : "doc.fill"), for: .normal)
            button.imageView?.contentMode = .scaleAspectFill
            button.tintColor = .white
            button.clipsToBounds = true
            button.layer.cornerRadius = 10
            button.layer.borderColor = UIColor.white.cgColor
            button.accessibilityLabel = String(format: Localization.text("imessage.preview.position"), index + 1, items.count)
            button.accessibilityIdentifier = "imessage.preview.thumbnail.\(index)"
            button.addAction(UIAction { [weak self] _ in self?.didSelectItem?(index) }, for: .touchUpInside)
            return button
        }
        select(selectedIndex)
        updateGlass()
        transparencyObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGlass() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 越界索引收敛到有效范围，空数据不产生选中项；不触发用户点击回调。
    func select(_ index: Int, animated: Bool = false) {
        selectedIndex = items.isEmpty ? nil : AttachmentPreviewPolicy.index(index, count: items.count)
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == selectedIndex
            button.layer.borderWidth = button.isSelected ? 2 : 0
            button.accessibilityTraits = button.isSelected ? [.button, .selected] : .button
        }
        needsRevealSelection = true
        animatesReveal = animated
        setNeedsLayout()
    }

    /// 等嵌套 QuickLayout 完成后读取真实按钮坐标；首次非零选中项及旋转均可正确露出。
    override func layoutSubviews() {
        super.layoutSubviews()
        glass.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        guard scrollView.bounds.width > 0 else { return }
        let resized = lastViewportSize != scrollView.bounds.size
        lastViewportSize = scrollView.bounds.size
        guard needsRevealSelection || resized else { return }
        needsRevealSelection = false
        if let selectedIndex {
            let rect = buttons[selectedIndex].convert(buttons[selectedIndex].bounds, to: scrollView).insetBy(dx: -4, dy: 0)
            scrollView.scrollRectToVisible(rect, animated: animatesReveal && !resized && !UIAccessibility.isReduceMotionEnabled)
        }
        animatesReveal = false
    }

    private func updateGlass() {
        let opaque = UIAccessibility.isReduceTransparencyEnabled
        glass.effect = backgroundStyle == .glass && !opaque ? UIGlassEffect(style: .regular) : nil
        glass.backgroundColor = backgroundStyle == .glass && opaque ? .secondarySystemBackground : .clear
    }

    isolated deinit {
        if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) }
    }
}

#if DEBUG
@available(iOS 26.0, *)
#Preview("附件缩略图导航") {
    let strip = AttachmentThumbnailStripView(items: ConversationPreviewData.attachmentPreviewItems)
    strip.didSelectItem = { [weak strip] index in strip?.select(index, animated: true) }
    return QuickLayoutView {
        strip.resizable().frame(height: AttachmentThumbnailStripView.preferredHeight).padding(16)
    }
}
#endif
