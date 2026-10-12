import AppLocalization
import QuickLayoutKit
import UIKit

/// 二维几何与 Duo 系统区域实验室。系统区域只显示真实查询结果。
final class GeometryDemoViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.geometry.title" }
    private let page = QuickLayoutScrollView(.vertical)
    private let canvas = GeometryDemoCanvas()
    private let scenario = UIButton(type: .system)
    private let options = UIButton(type: .system)
    private let directionButton = UIButton(type: .system)
    private let width = UISlider()
    private let margin = UISlider()
    private let radius = UISlider()
    private let metrics = UILabel()
    private let code = UILabel()
    private let instructions = UILabel()
    private let widthLabel = UILabel()
    private let marginLabel = UILabel()
    private let radiusLabel = UILabel()
    private var selection = 0
    private var includeInactive = false
    private var mirrors = true
    private var isRTL = false
    private var callbacks = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        for label in [metrics, code, instructions, widthLabel, marginLabel, radiusLabel] {
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.adjustsFontForContentSizeCategory = true
        }
        code.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .regular))
        code.textColor = .systemIndigo
        code.semanticContentAttribute = .forceLeftToRight
        code.textAlignment = .left
        metrics.accessibilityIdentifier = "geometry.metrics"
        code.accessibilityIdentifier = "geometry.code"
        canvas.accessibilityIdentifier = "geometry.canvas"
        width.minimumValue = 0.35; width.maximumValue = 1; width.value = 0.8
        margin.minimumValue = 0; margin.maximumValue = 48; margin.value = 16
        radius.minimumValue = 0; radius.maximumValue = 80; radius.value = 48
        width.accessibilityIdentifier = "geometry.width"
        margin.accessibilityIdentifier = "geometry.margin"
        radius.accessibilityIdentifier = "geometry.radius"
        width.addTarget(self, action: #selector(controlsChanged), for: .valueChanged)
        margin.addTarget(self, action: #selector(controlsChanged), for: .valueChanged)
        radius.addTarget(self, action: #selector(controlsChanged), for: .valueChanged)
        for button in [scenario, options, directionButton] { button.configuration = .tinted() }
        scenario.showsMenuAsPrimaryAction = true
        options.showsMenuAsPrimaryAction = true
        scenario.accessibilityIdentifier = "geometry.scenario"
        options.accessibilityIdentifier = "geometry.options"
        directionButton.accessibilityIdentifier = "geometry.direction"
        directionButton.addTarget(self, action: #selector(toggleDirection), for: .touchUpInside)
        canvas.didChange = { [weak self] proxy in self?.display(proxy) }
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(page) {
            VStack(alignment: .leading, spacing: 12) {
                scenario.resizable(axis: .horizontal).frame(minHeight: 44)
                instructions
                HStack(spacing: 8) {
                    options.resizable(axis: .horizontal).frame(minHeight: 44)
                    directionButton.frame(minWidth: 70, minHeight: 44)
                }
                widthLabel
                width.resizable(axis: .horizontal).frame(height: 32)
                marginLabel
                margin.resizable(axis: .horizontal).frame(height: 32)
                if selection == 2 {
                    radiusLabel
                    radius.resizable(axis: .horizontal).frame(height: 32)
                }
                canvas.resizable().frame(width: max(100, (view.bounds.width - 32) * CGFloat(width.value)), height: 260)
                metrics
                code
            }.safeAreaPadding(.horizontal, 16).padding(.vertical, 16)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        widthLabel.text = Localization.text("geometry.width")
        marginLabel.text = Localization.text("geometry.margin")
        radiusLabel.text = Localization.text("geometry.radius")
        width.accessibilityLabel = widthLabel.text
        margin.accessibilityLabel = marginLabel.text
        radius.accessibilityLabel = radiusLabel.text
        updateControls()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        isRTL = direction == .rightToLeft
        updateControls()
        code.semanticContentAttribute = .forceLeftToRight
    }

    private func updateControls() {
        let keys = ["spaces", "anchors", "container", "regions"]
        scenario.configuration?.title = Localization.text("geometry." + keys[selection])
        scenario.menu = UIMenu(children: keys.enumerated().map { index, key in
            UIAction(title: Localization.text("geometry." + key), state: index == selection ? .on : .off) { [weak self] _ in
                self?.selection = index; self?.callbacks = 0; self?.updateControls()
            }
        })
        options.configuration?.title = Localization.text("geometry.options")
        options.menu = UIMenu(children: [
            UIAction(title: Localization.text("geometry.inactive"), state: includeInactive ? .on : .off) { [weak self] _ in
                self?.includeInactive.toggle(); self?.updateControls()
            },
            UIAction(title: Localization.text("geometry.mirrors"), state: mirrors ? .on : .off) { [weak self] _ in
                self?.mirrors.toggle(); self?.updateControls()
            },
        ])
        directionButton.configuration?.title = isRTL ? "RTL" : "LTR"
        instructions.text = Localization.text("geometry." + keys[selection] + ".detail")
        code.text = [
            ".coordinateSpace(.named(\"stage\"))\n.onGeometryChange(for: CGRect.self) {\n  $0.frame(in: .named(\"stage\"))\n} action: { frame in … }\n// bounds(of:) converts in the reverse direction",
            "let anchor = Anchor<CGRect>(.bounds)\ncontent.geometryAnchor(anchor)\n// in transform:\nlet rect = proxy.resolve(anchor)",
            ".geometryContainer(values)\n// iOS 26+: proxy.containerCornerInsets\n// iOS 27+: proxy.concentricCornerRadii\n// iOS 27.1+:\nproxy.contentMargins(for: .container)",
            "// iOS 27.1+ · system regions\nproxy.reservedRegions(kind: .division,\n  options: [.includeInactive],\n  layoutDirectionBehavior: .fixed)\n// frame already includes margins",
        ][selection]
        canvas.selection = selection
        canvas.includeInactive = includeInactive
        canvas.mirrors = mirrors
        canvas.rtl = isRTL
        controlsChanged()
        if let proxy = canvas.lastProxy { display(proxy, counting: false) }
        setNeedsQuickLayout()
    }

    @objc private func controlsChanged() {
        canvas.fraction = CGFloat(width.value)
        canvas.margin = CGFloat(margin.value)
        canvas.radius = CGFloat(radius.value)
        canvas.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }

    @objc private func toggleDirection() { isRTL.toggle(); updateControls() }

    private func display(_ proxy: GeometryProxy, counting: Bool = true) {
        if counting { callbacks += 1 }
        var rows = ["\(Localization.text("geometry.callbacks")): \(callbacks)",
                    "size: \(proxy.size)", "safeArea: \(proxy.safeAreaInsets)"]
        switch selection {
        case 0:
            rows += ["local: \(proxy.frame(in: .local))", "global: \(proxy.frame(in: .global))",
                     "named: \(proxy.frame(in: .named("stage")))",
                     "bounds: \(String(describing: proxy.bounds(of: .named("stage"))))",
                     "scroll: \(proxy.frame(in: .scrollView))"]
        case 1:
            rows += ["Anchor: \(String(describing: proxy.resolve(canvas.anchor)))",
                     "UIView: \(String(describing: proxy.resolve(canvas.viewAnchor)))"]
        case 2:
            if #available(iOS 26.0, *) { rows.append("corners: \(proxy.containerCornerInsets)") }
            if #available(iOS 27.0, *) { rows.append("radii: \(String(describing: proxy.concentricCornerRadii(in: CGRect(x: 8, y: 8, width: 80, height: 60))))") }
            if #available(iOS 27.1, *) { rows.append("margins: \(proxy.contentMargins(for: .container))") }
            else { rows.append(Localization.text("geometry.requires271")) }
        default:
            if #available(iOS 27.1, *) {
                let regions = proxy.reservedRegions(kind: .occlusion, options: includeInactive ? .includeInactive : [], layoutDirectionBehavior: mirrors ? .mirrors : .fixed)
                    + proxy.reservedRegions(kind: .division, options: includeInactive ? .includeInactive : [], layoutDirectionBehavior: mirrors ? .mirrors : .fixed)
                rows += regions.map { "\($0.kind): \($0.frame) · active=\($0.isActive)" }
                if regions.isEmpty { rows.append(Localization.text("geometry.noRegions")) }
            } else { rows.append(Localization.text("geometry.requires271")) }
        }
        let text = rows.joined(separator: "\n")
        if metrics.text != text { metrics.text = text; setNeedsQuickLayout() }
    }
}

private final class GeometryDemoCanvas: QuickLayoutView {
    let anchor = Anchor<CGRect>(.bounds)
    private let sample = UIView()
    lazy var viewAnchor = sample.geometryAnchor(Anchor<CGPoint>.Source.center)
    private let overlay = GeometryDemoOverlay()
    private let horizontal = QuickLayoutScrollView(.horizontal)
    var didChange: ((GeometryProxy) -> Void)?
    private(set) var lastProxy: GeometryProxy?
    var selection = 0
    var fraction: CGFloat = 0.8
    var margin: CGFloat = 16
    var radius: CGFloat = 48
    var rtl = false
    var includeInactive = false
    var mirrors = true
    private var availableRegion: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        sample.backgroundColor = .systemTeal.withAlphaComponent(0.25)
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        _ = viewAnchor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        let values = GeometryContainerValues(
            contentMargins: EdgeInsets(top: margin, leading: margin, bottom: margin / 2, trailing: margin * 1.5),
            cornerInsets: .init(topLeading: CGSize(width: radius, height: radius * 0.75), bottomTrailing: CGSize(width: radius / 2, height: radius / 2)),
            cornerRadii: .init(topLeading: radius, bottomLeading: radius * 2 / 3, bottomTrailing: radius / 3, topTrailing: radius / 2))
        return ZStack {
            sampleLayout
            overlay.resizable()
        }
        .onGeometryChange(for: GeometryProxy.self, of: { $0 }) { [weak self] proxy in
            guard let self else { return }
            self.lastProxy = proxy
            self.render(proxy)
            self.didChange?(proxy)
        }
        .coordinateSpace(.named("stage"))
        .geometryContainer(values)
        .layoutDirection(rtl ? .rightToLeft : .leftToRight)
    }

    @LayoutBuilder
    private var sampleLayout: Layout {
        if selection == 3 {
            let region = availableRegion?.intersection(bounds) ?? bounds
            sample.resizable().frame(width: max(0, region.width), height: max(0, region.height))
                .geometryAnchor(anchor)
                .position(x: region.midX, y: region.midY)
        } else {
            ScrollView(horizontal, .horizontal) {
                sample.resizable().frame(width: max(100, bounds.width * fraction * 1.6), height: 200)
                    .geometryAnchor(anchor).padding(.horizontal, margin)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let proxy = lastProxy { render(proxy) }
    }

    private func render(_ proxy: GeometryProxy) {
        var rects: [CGRect] = []
        var points: [CGPoint] = []
        if selection == 1 {
            if let rect = proxy.resolve(anchor) { rects.append(rect) }
            if let point = proxy.resolve(viewAnchor) { points.append(point) }
        } else if selection == 2 {
            rects = [bounds.insetBy(dx: margin, dy: margin)]
        } else if selection == 3, #available(iOS 27.1, *) {
            let options: QuickLayoutKitCore.ReservedRegion.QueryOptions = includeInactive ? .includeInactive : []
            let behavior: LayoutDirectionBehavior = mirrors ? .mirrors : .fixed
            rects = (proxy.reservedRegions(kind: .occlusion, options: options, layoutDirectionBehavior: behavior)
                + proxy.reservedRegions(kind: .division, options: options, layoutDirectionBehavior: behavior)).map(\.frame)
            // 对真实活动区域逐个避让，选择剩余面积最大的矩形承载示例内容。
            let active = proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                + proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
            var available = bounds
            for region in active {
                let blocked = available.intersection(region.frame)
                guard !blocked.isNull, !blocked.isEmpty else { continue }
                let candidates = [
                    CGRect(x: available.minX, y: available.minY, width: max(0, blocked.minX - available.minX), height: available.height),
                    CGRect(x: blocked.maxX, y: available.minY, width: max(0, available.maxX - blocked.maxX), height: available.height),
                    CGRect(x: available.minX, y: available.minY, width: available.width, height: max(0, blocked.minY - available.minY)),
                    CGRect(x: available.minX, y: blocked.maxY, width: available.width, height: max(0, available.maxY - blocked.maxY)),
                ]
                available = candidates.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
            }
            if available != availableRegion {
                availableRegion = available
                DispatchQueue.main.async { [weak self] in self?.setNeedsQuickLayout() }
            }
        }
        overlay.rects = rects
        overlay.points = points
        overlay.setNeedsDisplay()
    }
}

private final class GeometryDemoOverlay: UIView {
    var rects: [CGRect] = []
    var points: [CGPoint] = []
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        UIColor.systemOrange.setStroke()
        UIColor.systemOrange.withAlphaComponent(0.15).setFill()
        for rect in rects {
            let path = UIBezierPath(rect: rect)
            path.lineWidth = 2; path.fill(); path.stroke()
        }
        UIColor.systemPink.setFill()
        for point in points { UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill() }
    }
}

@available(iOS 17.0, *)
#Preview { UINavigationController(rootViewController: GeometryDemoViewController()) }
