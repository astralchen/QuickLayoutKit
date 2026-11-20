#if DEBUG && compiler(>=6.4)
import QuickLayoutKit
import UIKit

/// UI 测试使用同一内容、同一窗口记录真实触摸期间及松手后的几何。
@available(iOS 17.0, *)
final class DuoSheetGestureWindow: UIWindow {
    var didMoveTouch: (() -> Void)?
    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        if event.allTouches?.contains(where: { $0.phase == .moved }) == true { didMoveTouch?() }
    }
}

@available(iOS 17.0, *)
final class DuoSheetGestureProbe: UIViewController {
    private let poseLabel = UILabel()
    private var pose = ArrangementDevicePose.unknown
    private var angle: CGFloat?
    private let measuresLower = ProcessInfo.processInfo.arguments.contains("-measure-lower-sheet")
    private var clearsLowerBackdrop: Bool { ProcessInfo.processInfo.environment["DUO_DIM_THRESHOLD"] == "both" }
    private var gatesUpperBackdrop: Bool { ProcessInfo.processInfo.environment["DUO_DIM_THRESHOLD"] != nil }
    private var lowerPanel: AdaptivePanelController?
    private weak var lowerSurface: UIView?
    private var panel: AdaptivePanelController?
    private var content: UIViewController?
    private var engine = ""
    private var samples: [[CGFloat]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        poseLabel.accessibilityIdentifier = "gesture.pose"
        stack.addArrangedSubview(poseLabel)
        for name in ["UIKit", "Sheet", "Panel"] {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.open(name) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard #available(iOS 27.1, *), let window = view.window, !window.interactions.contains(where: { $0 is UIHingeInteraction }) else { return }
        window.addInteraction(UIHingeInteraction { [weak self] _, update in
            guard let self else { return }
            angle = update.hinge?.angle
            switch update.hinge?.status {
            case .closed: pose = .closed
            case .partiallyOpen: pose = .partial
            case .fullyOpen: pose = .open
            default: pose = .unknown
            }
            updatePose()
        })
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updatePose() }

    private var currentPose: String {
        guard let window = view.window else { return "unknown" }
        let size = window.bounds.size
        let name = pose == .closed ? (size.width > size.height ? "closedLandscape" : "closedPortrait") : pose.resolved(in: window).rawValue
        return "\(name) \(Int(size.width)) \(Int(size.height)) \(angle.map { $0 * 180 / .pi } ?? -1)"
    }

    private func updatePose() {
        poseLabel.text = currentPose
    }

    private func open(_ name: String) {
        guard ProcessInfo.processInfo.arguments.contains("-test-stacked-sheet") else { open(name, from: self); return }
        let short = ProcessInfo.processInfo.arguments.contains("-test-short-lower")
        let compact = traitCollection.verticalSizeClass == .compact
        let base = UIViewController()
        base.view.backgroundColor = .systemIndigo
        let ready = { [weak self] in
            guard let self else { return }
            lowerSurface = lowerPanel?.contentViewController.view.superview ?? base.customSheetPresentationController?.presentedView ?? base.view
            if measuresLower {
                let next = GestureReadingButton(type: .system)
                next.setTitle("Open upper sheet", for: .normal)
                next.setTitle("Close lower sheet", for: .selected)
                next.accessibilityIdentifier = "gesture.lower"
                next.read = { [weak self] in
                    guard let self, let lowerSurface, let window = view.window else { return nil }
                    let metrics = surfaceGeometry(lowerSurface, in: window) + scale(of: lowerSurface, in: window)
                    return try? String(decoding: JSONEncoder().encode(metrics), as: UTF8.self)
                }
                next.translatesAutoresizingMaskIntoConstraints = false
                base.view.addSubview(next)
                NSLayoutConstraint.activate([next.centerXAnchor.constraint(equalTo: base.view.centerXAnchor),
                                             next.centerYAnchor.constraint(equalTo: base.view.centerYAnchor)])
                next.addAction(UIAction { [weak self, weak base = base, weak next] _ in
                    guard let self, let base, let next else { return }
                    if next.isSelected {
                        if let lowerPanel { lowerPanel.dismiss(animated: false); self.lowerPanel = nil }
                        else { base.dismiss(animated: false) }
                        lowerSurface = nil
                    } else {
                        next.isSelected = true
                        open(name, from: base)
                    }
                }, for: .touchUpInside)
            } else { open(name, from: base) }
        }
        switch name {
        case "UIKit":
            base.modalPresentationStyle = .pageSheet
            if clearsLowerBackdrop { base.sheetPresentationController?.largestUndimmedDetentIdentifier = .large }
            base.sheetPresentationController?.prefersPageSizing = true
            base.sheetPresentationController?.prefersEdgeAttachedInCompactHeight = true
            if short, let sheet = base.sheetPresentationController {
                sheet.detents = [.custom(identifier: .init("third")) { $0.maximumDetentValue / 3 }, .medium(), .large()]
                sheet.selectedDetentIdentifier = compact ? .init("third") : .medium
            }
            present(base, animated: false, completion: ready)
        case "Sheet":
            presentSheet(base, animated: false) { [clearsLowerBackdrop] sheet in
                if clearsLowerBackdrop { sheet.largestUndimmedDetentIdentifier = .large }
                sheet.prefersPageSizing = true
                sheet.prefersEdgeAttachedInCompactHeight = true
                if short {
                    sheet.detents = [.custom(identifier: "third") { $0.maximumDetentValue / 3 }, .medium(), .large()]
                    sheet.selectedDetentIdentifier = compact ? "third" : .medium
                }
            } completion: { ready() }
        default:
            let panel = AdaptivePanelController(contentViewController: base)
            if clearsLowerBackdrop { panel.largestUndimmedDetentIdentifier = .large }
            lowerPanel = panel
            // 让下层内容的靛色一直延伸到顶边，与系统页及自定义 sheet 的对照配置一致。
            panel.prefersGrabberVisible = false
            if short {
                panel.detents = [.custom(identifier: "third") { $0.maximumDetentValue / 3 }, .medium(), .large()]
                panel.selectedDetentIdentifier = compact ? "third" : .medium
            }
            panel.safeAreaSource = .window
            panel.show(in: self, animated: false)
            ready()
        }
    }

    private func open(_ name: String, from host: UIViewController) {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        let close = GestureReadingButton(type: .system)
        close.accessibilityIdentifier = "gesture.reading"
        close.setTitle("Close", for: .normal)
        close.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(close)
        NSLayoutConstraint.activate([close.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                                     close.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)])
        engine = name
        content = vc
        samples = []
        close.read = { [weak self] in self?.reading() }
        close.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if measuresLower {
                if let panel { panel.dismiss(animated: false); self.panel = nil }
                else { content?.dismiss(animated: false) }
                content = nil
                return
            }
            if let panel {
                panel.dismiss(animated: false)
                lowerPanel?.dismiss(animated: false)
                self.panel = nil
                lowerPanel = nil
            }
            else { dismiss(animated: false) }
            lowerSurface = nil
            content = nil
        }, for: .touchUpInside)
        (view.window as? DuoSheetGestureWindow)?.didMoveTouch = { [weak self] in
            guard let self, let sample = geometry(), samples.last != sample else { return }
            samples.append(sample)
        }
        let radius = ProcessInfo.processInfo.environment["DUO_CORNER_RADIUS"].flatMap(Double.init).map { CGFloat($0) }
        let pageSizing = !ProcessInfo.processInfo.arguments.contains("-test-form-sizing")
        let large = ProcessInfo.processInfo.arguments.contains("-test-initial-large")
        let gated = gatesUpperBackdrop
        let compact = host.traitCollection.verticalSizeClass == .compact
        switch name {
        case "UIKit":
            vc.modalPresentationStyle = .pageSheet
            guard let sheet = vc.sheetPresentationController else { return }
            sheet.detents = [.custom(identifier: .init("third")) { $0.maximumDetentValue / 3 }, .medium(), .large()]
            sheet.preferredCornerRadius = radius
            sheet.prefersGrabberVisible = true
            if gated { sheet.largestUndimmedDetentIdentifier = compact ? .init("third") : .medium }
            sheet.prefersPageSizing = pageSizing
            sheet.prefersEdgeAttachedInCompactHeight = true
            if large { sheet.selectedDetentIdentifier = .large }
            host.present(vc, animated: false)
        case "Sheet":
            host.presentSheet(vc, animated: false) { sheet in
                sheet.detents = [.custom(identifier: "third") { $0.maximumDetentValue / 3 }, .medium(), .large()]
                sheet.preferredCornerRadius = radius
                sheet.prefersGrabberVisible = true
                if gated { sheet.largestUndimmedDetentIdentifier = compact ? "third" : .medium }
                sheet.prefersPageSizing = pageSizing
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.selectedDetentIdentifier = large ? .large : "third"
            }
        default:
            let panel = AdaptivePanelController(contentViewController: vc)
            panel.detents = [.custom(identifier: "third") { $0.maximumDetentValue / 3 }, .medium(), .large()]
            panel.selectedDetentIdentifier = large ? .large : "third"
            if gated { panel.largestUndimmedDetentIdentifier = compact ? "third" : .medium }
            panel.prefersPageSizing = pageSizing
            panel.preferredCornerRadius = radius
            panel.safeAreaSource = .window
            self.panel = panel
            panel.show(in: host, animated: false)
        }
    }

    private func geometry() -> [CGFloat]? {
        guard let window = view.window, let content else { return nil }
        let surface: UIView?
        switch engine {
        case "Panel": surface = content.view.superview
        case "Sheet": surface = content.customSheetPresentationController?.presentedView
        default: surface = content.view
        }
        guard let surface, surface.window === window else { return nil }
        let back = lowerSurface ?? view!
        let presenter = back.convert(back.bounds, to: window)
        let lowerMetrics = measuresLower ? Array(surfaceGeometry(back, in: window).suffix(4)) + scale(of: back, in: window) : []
        return surfaceGeometry(surface, in: window) + lowerMetrics + [presenter.minX, presenter.minY, presenter.width, presenter.height]
    }

    private func scale(of surface: UIView, in window: UIWindow) -> [CGFloat] {
        let origin = surface.convert(CGPoint.zero, to: window)
        let x = surface.convert(CGPoint(x: 1, y: 0), to: window)
        let y = surface.convert(CGPoint(x: 0, y: 1), to: window)
        return [hypot(x.x - origin.x, x.y - origin.y), hypot(y.x - origin.x, y.y - origin.y)]
    }

    private func surfaceGeometry(_ surface: UIView, in window: UIWindow) -> [CGFloat] {
        let frame = surface.convert(surface.bounds, to: window)
        var radii = Array(repeating: CGFloat.zero, count: 4)
        var current: UIView? = surface
        while let v = current, v !== window {
            let rect = v.convert(v.bounds, to: window)
            if v.clipsToBounds, abs(rect.minX - frame.minX) < 0.5, abs(rect.maxX - frame.maxX) < 0.5,
               abs(rect.minY - frame.minY) < 0.5, abs(rect.maxY - frame.maxY) < 0.5 {
                let scale = rect.width / max(1, v.bounds.width)
                for (i, corner) in [UIRectCorner.topLeft, .topRight, .bottomLeft, .bottomRight].enumerated() {
                    if #available(iOS 26, *) {
                        radii[i] = max(radii[i], v.effectiveRadius(corner: corner) * scale)
                    } else {
                        let masks: [CACornerMask] = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                        if v.layer.maskedCorners.contains(masks[i]) { radii[i] = max(radii[i], v.layer.cornerRadius * scale) }
                    }
                }
            }
            current = v.superview
        }
        return [frame.minX, frame.minY, window.bounds.maxX - frame.maxX, window.bounds.maxY - frame.maxY] + radii
    }

    private func reading() -> String? {
        guard let geometry = geometry(), let content, let window = view.window else { return nil }
        let id: String?
        switch engine {
        case "Panel": id = panel?.selectedDetentIdentifier?.rawValue
        case "Sheet": id = content.customSheetPresentationController?.selectedDetentIdentifier?.rawValue
        default: id = content.sheetPresentationController?.selectedDetentIdentifier?.rawValue.components(separatedBy: ".").last
        }
        let data: [String: Any] = ["detent": id ?? "third", "geometry": geometry, "samples": samples, "pose": currentPose,
                                   "windowSize": [window.bounds.width, window.bounds.height]]
        return (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

private final class GestureReadingButton: UIButton {
    var read: (() -> String?)?
    override var accessibilityValue: String? { get { read?() } set {} }
}
#endif
