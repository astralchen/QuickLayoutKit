@testable import Demo
import QuickLayoutKit
import Testing
import UIKit

@MainActor
private final class PopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate, PopoverPresentationControllerDelegate {
    var style = UIModalPresentationStyle.none
    var preparations = 0
    var attempts = 0
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { style }
    func prepareForPopoverPresentation(_ popover: PopoverPresentationController) { preparations += 1 }
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { attempts += 1 }
}

@MainActor
private final class PopoverFixture {
    let window: UIWindow
    let previous: UIWindow?
    let host = UIViewController()
    let source = UIView()
    let delegate = PopoverDelegate()
    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.keyWindow
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(source)
        source.frame = CGRect(origin: CGPoint(x: host.view.bounds.midX, y: host.view.bounds.midY), size: CGSize(width: 2, height: 2))
        host.view.layoutIfNeeded()
    }
    func pixel(at point: CGPoint) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { ctx in
            ctx.cgContext.translateBy(x: -point.x, y: -point.y)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes {
            let ctx = try #require(CGContext(data: $0.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
    func difference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }
    func close() { window.isHidden = true; previous?.makeKey() }

    func show(native: Bool, directions: UIPopoverArrowDirection = .any,
              background: UIPopoverBackgroundView.Type? = nil,
              configureNative: (UIPopoverPresentationController) -> Void = { _ in },
              configure: (PopoverPresentationController) -> Void = { _ in }) async throws -> UIViewController {
        let content = UIViewController()
        content.preferredContentSize = CGSize(width: 220, height: 140)
        if native {
            content.modalPresentationStyle = .popover
            let pc = try #require(content.popoverPresentationController)
            pc.sourceView = source
            pc.permittedArrowDirections = directions
            pc.delegate = delegate
            pc.popoverBackgroundViewClass = background
            configureNative(pc)
            await withCheckedContinuation { end in host.present(content, animated: false) { end.resume() } }
        } else {
            let ok: Bool = await withCheckedContinuation { end in
                let started = host.presentPopover(content, animated: false) { pc in
                    pc.sourceView = self.source
                    pc.permittedArrowDirections = directions
                    pc.popoverDelegate = self.delegate
                    pc.popoverBackgroundViewClass = background
                    configure(pc)
                } completion: { end.resume(returning: true) }
                if !started { end.resume(returning: false) }
            }
            try #require(ok)
        }
        return content
    }
    func dismiss(_ content: UIViewController) async {
        await withCheckedContinuation { end in content.dismiss(animated: false) { end.resume() } }
    }

    private typealias Measurement = (frame: CGRect, intersection: CGRect, arrow: UIPopoverArrowDirection)

    private func measureAnchor(_ sourceRect: CGRect, native: Bool, direction: UIPopoverArrowDirection, overlap: Bool) async throws -> Measurement {
        let content = try await show(native: native, directions: direction, configureNative: {
            $0.sourceRect = sourceRect
            $0.canOverlapSourceViewRect = overlap
        }, configure: {
            $0.sourceRect = sourceRect
            $0.canOverlapSourceViewRect = overlap
        })
        let pc = try #require(content.presentationController)
        let arrow = try #require(native ? content.popoverPresentationController?.arrowDirection : content.customPopoverPresentationController?.arrowDirection)
        let surface = try #require(pc.presentedView)
        window.layoutIfNeeded()
        let frame = surface.convert(surface.bounds, to: window)
        let source = self.source.convert(sourceRect, to: window)
        let intersection = frame.intersection(source)
        await dismiss(content)
        return (frame, intersection.isEmpty ? .null : intersection, arrow)
    }

    /// 在同一窗口依次呈现，比较布局完成后的视图外框、正面积交集和最终箭头方向。
    func compareAnchor(_ sourceRect: CGRect, direction: UIPopoverArrowDirection, overlap: Bool, label: String) async throws -> String {
        let pixel = 1 / max(1, window.traitCollection.displayScale)

        func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
            if actual.isNull || expected.isNull { return actual.isNull && expected.isNull }
            return abs(actual.minX - expected.minX) <= pixel && abs(actual.maxX - expected.maxX) <= pixel &&
                abs(actual.minY - expected.minY) <= pixel && abs(actual.maxY - expected.maxY) <= pixel
        }

        let reference = try await measureAnchor(sourceRect, native: true, direction: direction, overlap: overlap)
        let actual = try await measureAnchor(sourceRect, native: false, direction: direction, overlap: overlap)
        let row = [label, "\(overlap)",
                   "\(reference.frame)", "\(actual.frame)", "\(reference.intersection)", "\(actual.intersection)",
                   "\(reference.arrow.rawValue)", "\(actual.arrow.rawValue)"].joined(separator: "\t")
        #expect(actual.arrow == reference.arrow, "\(row)")
        #expect(matches(actual.frame, reference.frame), "外框：\(row)")
        #expect(matches(actual.intersection, reference.intersection), "交集：\(row)")
        return row
    }
}

private final class MeasuringPopoverBackground: UIPopoverBackgroundView {
    override class func arrowBase() -> CGFloat { 36 }
    override class func arrowHeight() -> CGFloat { 18 }
    override class func contentViewInsets() -> UIEdgeInsets { UIEdgeInsets(top: 3, left: 5, bottom: 7, right: 9) }
    private var offset: CGFloat = 0
    private var direction: UIPopoverArrowDirection = .unknown
    override var arrowOffset: CGFloat { get { offset } set { offset = newValue } }
    override var arrowDirection: UIPopoverArrowDirection { get { direction } set { direction = newValue } }
}

/// 仅通过框架的公开 API 自定义箭头和配色，验证跨模块覆写会参与实际布局和绘制。
private final class WideArrowBackground: OutlinedPopoverBackground {
    private(set) weak var appearanceController: UIPresentationController?

    required init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "wideOutlinedBackground"
    }

    required init?(coder: NSCoder) { nil }

    override nonisolated class func arrowBase() -> CGFloat { 64 }
    override nonisolated class func arrowHeight() -> CGFloat { 24 }
    override nonisolated class func contentViewInsets() -> UIEdgeInsets {
        .init(top: 9, left: 11, bottom: 13, right: 15)
    }

    override func applyPopoverAppearance(from controller: UIPresentationController, backgroundColor: UIColor?) {
        super.applyPopoverAppearance(from: controller, backgroundColor: backgroundColor)
        appearanceController = controller
        if backgroundColor == nil || backgroundColor == .red { fillColor = .green }
    }
}

private final class WideUIOutlinedBackground: UIOutlinedPopoverBackground {
    override nonisolated class var drawingViewClass: OutlinedPopoverBackground.Type { WideArrowBackground.self }
}

/// UIKit 与 QuickLayoutKit 使用同一个框架外子类，分别验证初始化、布局度量及外观分派。
private final class WideSolidBackground: SolidPopoverBackground {
    private(set) weak var appearanceController: UIPresentationController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "wideSolidBackground"
    }

    required init?(coder: NSCoder) { nil }

    override class func arrowBase() -> CGFloat { 64 }
    override class func arrowHeight() -> CGFloat { 24 }
    override class func contentViewInsets() -> UIEdgeInsets {
        .init(top: 9, left: 11, bottom: 13, right: 15)
    }

    override func applyPopoverAppearance(from controller: UIPresentationController, backgroundColor: UIColor?) {
        super.applyPopoverAppearance(from: controller, backgroundColor: backgroundColor)
        appearanceController = controller
        if backgroundColor == .red { self.backgroundColor = .green }
    }
}

@MainActor
@Suite(.serialized)
struct PopoverPresentationTests {
    @Test func geometryMatchesUIKit() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let bounds = f.host.view.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let samples: [(CGPoint, UIPopoverArrowDirection)] = [
            (center, .any), (center, .up), (center, .left), (center, .right), (center, .down),
            (CGPoint(x: 12, y: 80), .up), (CGPoint(x: bounds.width - 12, y: 80), .any),
            (CGPoint(x: 12, y: bounds.height - 45), .any)
        ]
        for (point, directions) in samples {
            f.source.frame.origin = point
            let reference = try await f.show(native: true, directions: directions)
            let expected = reference.view.convert(reference.view.bounds, to: f.host.view)
            let safeArea = reference.view.safeAreaInsets
            let direction = reference.popoverPresentationController?.arrowDirection
            await f.dismiss(reference)
            let content = try await f.show(native: false, directions: directions)
            let pc = try #require(content.customPopoverPresentationController)
            let actual = content.view.convert(content.view.bounds, to: f.host.view)
            #expect(content.view.safeAreaInsets == safeArea)
            #expect(direction == pc.arrowDirection, "锚点 \(point)，允许方向 \(directions.rawValue)")
            #expect(abs(expected.minX - actual.minX) <= 1 && abs(expected.minY - actual.minY) <= 1, "锚点 \(point)，UIKit \(expected)，自定义 \(actual)")
            #expect(abs(expected.width - actual.width) <= 1 && abs(expected.height - actual.height) <= 1,
                    "方向 \(directions.rawValue)，UIKit \(expected)，自定义 \(actual)")
            await f.dismiss(content)
            #expect(pc.arrowDirection == .unknown)
        }
        #expect(f.delegate.preparations == samples.count)
    }

    @Test func customBackgroundOffsets() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        for dir in [UIPopoverArrowDirection.up, .down, .left, .right] {
            for far in [false, true] {
                let b = f.host.view.safeAreaLayoutGuide.layoutFrame
                let vertical = dir == .up || dir == .down
                f.source.frame.origin = CGPoint(x: vertical ? (far ? b.maxX - 12 : b.minX + 10) : b.midX,
                                                y: vertical ? b.midY : (far ? b.maxY - 2 : b.minY + 2))
                var reference: CGFloat = 0
                for native in [true, false] {
                    let content = try await f.show(native: native, directions: dir, background: MeasuringPopoverBackground.self)
                    func background(in root: UIView) -> MeasuringPopoverBackground? {
                        root as? MeasuringPopoverBackground ?? root.subviews.lazy.compactMap { background(in: $0) }.first
                    }
                    let view = try #require(background(in: f.window))
                    #expect(view.arrowDirection == dir)
                    if native { reference = view.arrowOffset }
                    else { #expect(abs(reference - view.arrowOffset) <= 1, "方向 \(dir.rawValue)，UIKit \(reference)，自定义 \(view.arrowOffset)") }
                    await f.dismiss(content)
                }
            }
        }
    }
}

extension PopoverPresentationTests {
    /// 对照侧栏按钮呈现时的面板尺寸，首帧和入场结束后都使用同一个窗口。
    @Test func adaptiveBarItemPresentationSize() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.window.rootViewController = nil
        let navigation = UINavigationController(rootViewController: f.host)
        f.window.rootViewController = navigation
        let item = UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)
        f.host.navigationItem.rightBarButtonItem = item
        f.window.layoutIfNeeded()
        let compact = f.window.traitCollection.horizontalSizeClass == .compact
        f.delegate.style = compact ? .pageSheet : .none
        var reference = CGRect.zero
        for native in [true, false] {
            let content = UIViewController()
            content.preferredContentSize = CGSize(width: 220, height: 140)
            if native {
                content.modalPresentationStyle = .popover
                let pc = try #require(content.popoverPresentationController)
                pc.delegate = f.delegate
                pc.barButtonItem = item
                pc.adaptiveSheetPresentationController.detents = [.medium(), .large()]
                f.host.present(content, animated: true)
            } else {
                let started = f.host.presentPopover(content) { pc in
                    pc.popoverDelegate = f.delegate
                    pc.barButtonItem = item
                    pc.sourceView = navigation.navigationBar
                    pc.adaptiveSheetPresentationController.detents = [.medium(), .large()]
                }
                try #require(started)
            }
            var samples: [CGRect] = []
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(20))
                if let view = content.viewIfLoaded, view.window === f.window {
                    samples.append(view.convert(view.bounds, to: f.window))
                }
                if content.transitionCoordinator == nil && !samples.isEmpty { break }
            }
            try await Task.sleep(for: .milliseconds(180))
            let final = content.view.convert(content.view.bounds, to: f.window)
            if native { reference = final }
            else {
                #expect(abs(final.width - reference.width) <= 1 && abs(final.height - reference.height) <= 1, "UIKit \(reference)，自定义 \(final)")
                if compact {
                    try #require(!samples.isEmpty)
                    #expect(samples.allSatisfy { abs($0.width - reference.width) <= 1 && abs($0.height - reference.height) <= 1 },
                            "UIKit \(reference.size)，入场尺寸 \(samples.map(\.size))")
                }
            }
            await f.dismiss(content)
        }
    }

    @Test func adaptationAndLiveRelayout() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let content = try await f.show(native: false, directions: .up)
        let pc = try #require(content.customPopoverPresentationController)
        let sheet = pc.adaptiveSheetPresentationController
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        let container = try #require(pc.containerView)
        let before = pc.frameOfPresentedViewInContainerView
        f.source.frame.origin.y += 30
        try await Task.sleep(for: .milliseconds(120))
        #expect(abs(pc.frameOfPresentedViewInContainerView.midY - before.midY - 30) <= 1)
        content.preferredContentSize.width += 30
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(content.view.bounds.width == 250)
        f.delegate.style = .pageSheet
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(pc.arrowDirection == .unknown)
        #expect(content.view.window === f.window)
        let actual = try #require(sheet.presentedView).frame
        let expected = pc.frameOfPresentedViewInContainerView
        // UIView 从中心点和 bounds 计算 frame，允许浮点往返产生的尾差。
        #expect(actual.size == expected.size && abs(actual.minX - expected.minX) < 0.000001 && abs(actual.minY - expected.minY) < 0.000001)
        f.delegate.style = .none
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(pc.arrowDirection == .up)
        #expect(pc.adaptiveSheetPresentationController === sheet)
        #expect(sheet.selectedDetentIdentifier == .medium)
        #expect(content.view.bounds.width == 250)
        await f.dismiss(content)
        #expect(content.view.window == nil)
    }

    @Test func outsideTapAndPassthrough() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let button = UIButton(frame: CGRect(x: 35, y: 150, width: 90, height: 42))
        f.host.view.addSubview(button)
        let content = try await f.show(native: false)
        let pc = try #require(content.customPopoverPresentationController)
        pc.passthroughViews = [button]
        let p = button.convert(CGPoint(x: 10, y: 12), to: f.window)
        #expect(f.window.hitTest(p, with: nil) === button)
        pc.passthroughViews = []
        let backdrop = try #require(f.window.hitTest(p, with: nil) as? UIControl)
        #expect(backdrop !== button)
        content.isModalInPresentation = true
        backdrop.sendActions(for: .touchUpInside)
        #expect(f.delegate.attempts == 1)
        #expect(f.host.presentedViewController === content)
        content.isModalInPresentation = false
        backdrop.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(650))
        #expect(f.host.presentedViewController == nil)
    }
}

extension PopoverPresentationTests {
    @Test func hiddenArrowRetainsFrameAndOffsetUpdatesBackground() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let content = try await f.show(native: false, directions: .up, background: MeasuringPopoverBackground.self, configure: { pc in
            pc.shouldHideArrow = true
            pc.arrowOffset = 34
            pc.dimmingViewTopEdgeInset = 90
        })
        let pc = try #require(content.customPopoverPresentationController)
        let frame = pc.frameOfPresentedViewInContainerView
        #expect(pc.arrowDirection.isEmpty)
        #expect(pc.arrowOffset == 0)
        #expect(content.view.bounds.size == CGSize(width: 220, height: 158))
        #expect(frame.height == 168)
        let sourceFrame = f.source.convert(f.source.bounds, to: pc.containerView)
        #expect(frame.minY == sourceFrame.maxY)
        let container = try #require(pc.containerView)
        func findBackground(_ view: UIView) -> MeasuringPopoverBackground? {
            view as? MeasuringPopoverBackground ?? view.subviews.lazy.compactMap { findBackground($0) }.first
        }
        let background = try #require(findBackground(container))
        pc.arrowOffset = 39
        #expect(background.arrowOffset == 39)
        content.preferredContentSize.width += 20
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(pc.arrowOffset == 39)
        pc.shouldHideArrow = false
        container.layoutIfNeeded()
        #expect(content.view.bounds.height == 140)
        #expect(pc.arrowDirection == .up)
        #expect(pc.frameOfPresentedViewInContainerView.height == frame.height)
        #expect(container.hitTest(CGPoint(x: 80, y: 50), with: nil) === container.hitTest(CGPoint(x: 80, y: 110), with: nil))
        await f.dismiss(content)
    }

    @Test func cornerAndMaterialConfiguration() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let content = try await f.show(native: false, directions: .up)
        let pc = try #require(content.customPopoverPresentationController)
        #expect(pc.cornerRadius == -1)
        #expect(pc.popoverBackgroundStyle == .automatic)
        #expect(pc.backgroundBlurEffectStyle == nil)
        #expect(pc.arrowBackgroundColor == nil)
        pc.cornerRadius = 7
        if #available(iOS 26, *) {
            #expect(pc.cornerConfiguration == .corners(radius: .fixed(7)))
            let corners = UICornerConfiguration.uniformTopRadius(.fixed(11), bottomLeftRadius: .fixed(3), bottomRightRadius: .fixed(17))
            pc.cornerConfiguration = corners
            #expect(pc.cornerRadius == -1)
            #expect(pc.cornerConfiguration == corners)
        }
        pc.popoverBackgroundStyle = .init(rawValue: 1)
        pc.backgroundBlurEffectStyle = .dark
        pc.backgroundColor = .systemBlue
        pc.arrowBackgroundColor = .systemRed
        pc.containerView?.layoutIfNeeded()
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
        let views = descendants(try #require(pc.presentedView))
        let tint = try #require(views.first { $0.backgroundColor == .systemRed && !$0.isHidden })
        #expect(tint.bounds.height == 13)
        let material = try #require(views.compactMap { $0 as? UIVisualEffectView }.first)
        #expect(material.effect is UIBlurEffect)
        #expect(material.contentView.backgroundColor == .systemBlue)
        if #available(iOS 26, *) {
            pc.backgroundBlurDisabled = true
            pc.containerView?.layoutIfNeeded()
            #expect(material.isHidden)
            pc.backgroundBlurDisabled = false
            pc.containerView?.layoutIfNeeded()
            #expect(!material.isHidden)
            pc.backgroundColor = nil
            pc.backgroundBlurEffectStyle = nil
            pc.containerView?.layoutIfNeeded()
            #expect(material.effect == nil)
            #expect(views.contains { $0 is any UIContentView && !$0.isHidden })
        }
        await f.dismiss(content)
    }

    @Test func barButtonTransitionRestoresSource() async throws {
        guard #available(iOS 26, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 130, width: f.host.view.bounds.width, height: 50))
        let button = UIButton(type: .system)
        button.setTitle("＋", for: .normal)
        button.alpha = 0.8
        let item = UIBarButtonItem(customView: button)
        toolbar.items = [item]
        f.host.view.addSubview(toolbar)
        toolbar.layoutIfNeeded()
        let content = UIViewController()
        content.preferredContentSize = CGSize(width: 220, height: 140)
        let shown: Bool = await withCheckedContinuation { end in
            let started = f.host.presentPopover(content) { pc in
                pc.sourceItem = item
                pc.popoverDelegate = f.delegate
            } completion: { end.resume(returning: true) }
            if !started { end.resume(returning: false) }
        }
        try #require(shown)
        let pc = try #require(content.customPopoverPresentationController)
        #expect(pc.shouldHideArrow)
        #expect(pc.arrowDirection.isEmpty)
        #expect(button.alpha == 0)
        let anchor = try #require(item.frame(in: f.host.view))
        #expect(abs(pc.frameOfPresentedViewInContainerView.midX - anchor.midX) <= 1)
        await withCheckedContinuation { end in content.dismiss(animated: true) { end.resume() } }
        #expect(abs(button.alpha - 0.8) < 0.001)
        #expect(content.transitioningDelegate == nil)
    }
}

#if DEBUG
extension PopoverPresentationTests {
    /// 在同一块红色底图上取样，分别核对默认玻璃和显式着色两条背景绘制路径。
    @Test func disabledBlurMatchesUIKit() async throws {
        guard #available(iOS 27, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .red
        let underlying = try f.pixel(at: f.source.center)
        for native in [true, false] {
            for color: UIColor? in [nil, .systemTeal] {
                var enabled: [UInt8] = []
                for disabled in [false, true] {
                    let content = try await f.show(native: native, directions: .up, configureNative: { pc in
                        pc.backgroundColor = color
                        if disabled { PopoverComparisonOption.disableBlur.apply(to: pc) }
                    }, configure: { pc in
                        pc.backgroundColor = color
                        if disabled { PopoverComparisonOption.disableBlur.apply(to: pc) }
                    })
                    if native {
                        let pc = try #require(content.popoverPresentationController)
                        try #require(pc.responds(to: NSSelectorFromString("_backgroundBlurDisabled")))
                        #expect((pc.value(forKey: "_backgroundBlurDisabled") as? NSNumber)?.boolValue == disabled)
                    }
                    let view = try #require(content.view)
                    let sample = try f.pixel(at: view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: f.window))
                    if disabled {
                        #expect(f.difference(sample, color == nil ? enabled : underlying) <= 5)
                    } else {
                        #expect(f.difference(sample, underlying) > 15)
                        enabled = sample
                    }
                    await f.dismiss(content)
                }
            }
        }
    }

    /// 把来源移到窗口边缘，验证外边距实际改变背景位置，并确认两种呈现都使用框架的纯色背景。
    @Test func exampleBackgroundAndMargins() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.source.frame.origin = CGPoint(x: 3, y: f.host.view.bounds.midY)
        for margin in [UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                       UIEdgeInsets(top: 12, left: 48, bottom: 32, right: 16)] {
            var expected = CGRect.zero
            for native in [true, false] {
                let content = try await f.show(native: native, directions: .up, background: SolidPopoverBackground.self,
                    configureNative: { $0.popoverLayoutMargins = margin; $0.backgroundColor = .systemTeal },
                    configure: { $0.popoverLayoutMargins = margin; $0.backgroundColor = .systemTeal })
                func background(in root: UIView) -> SolidPopoverBackground? {
                    root as? SolidPopoverBackground ?? root.subviews.lazy.compactMap { background(in: $0) }.first
                }
                let view = try #require(background(in: f.window))
                #expect(view.backgroundColor == .systemTeal)
                if native { content.popoverPresentationController?.backgroundColor = nil }
                else { content.customPopoverPresentationController?.backgroundColor = nil }
                f.window.layoutIfNeeded()
                await Task.yield()
                #expect(view.backgroundColor == .systemBackground, "呈现中恢复默认色，UIKit = \(native)")
                #expect(view.arrowDirection == .up)
                let frame = view.convert(view.bounds, to: f.window)
                if native { expected = frame }
                else {
                    #expect(abs(frame.minX - expected.minX) <= 1 && abs(frame.width - expected.width) <= 1,
                            "边距 \(margin)，UIKit \(expected)，自定义 \(frame)")
                }
                await f.dismiss(content)
            }
        }
    }

    /// UIKit 及框架装载相同包装类时，都应按内部子类度量，并将控制器改色传给该实例。
    @Test func outlinedWrapperUsesDrawingSubclassInBothEngines() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .white
        func wrapper(in view: UIView) -> WideUIOutlinedBackground? {
            view as? WideUIOutlinedBackground ?? view.subviews.lazy.compactMap { wrapper(in: $0) }.first
        }
        #expect(WideUIOutlinedBackground.arrowBase() == 64)
        #expect(WideUIOutlinedBackground.arrowHeight() == 24)
        #expect(WideUIOutlinedBackground.contentViewInsets() == WideArrowBackground.contentViewInsets())
        for native in [true, false] {
            for direction: UIPopoverArrowDirection in [.up, .down, .left, .right] {
                let content = try await f.show(native: native, directions: direction, background: WideUIOutlinedBackground.self,
                    configureNative: { $0.backgroundColor = .red }, configure: { $0.backgroundColor = .red })
                let view = try #require(wrapper(in: f.window))
                let drawings = view.subviews.compactMap { $0 as? WideArrowBackground }
                let drawing = try #require(drawings.first)
                #expect(drawing.appearanceController === content.presentationController)
                #expect(drawing.arrowOffset == view.arrowOffset)
                try await verifyWideArrow(drawing, direction: direction, content: content, fixture: f)
                await f.dismiss(content)
            }
        }
    }

    @Test func solidSubclassLayoutAndAppearanceInBothEngines() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .white
        func findBackground(in view: UIView) -> WideSolidBackground? {
            view as? WideSolidBackground ?? view.subviews.lazy.compactMap { findBackground(in: $0) }.first
        }
        for native in [true, false] {
            for direction: UIPopoverArrowDirection in [.up, .down, .left, .right] {
                let content = try await f.show(native: native, directions: direction, background: WideSolidBackground.self,
                    configureNative: { $0.backgroundColor = .red }, configure: { $0.backgroundColor = .red })
                let background = try #require(findBackground(in: f.window))
                #expect(background.accessibilityIdentifier == "wideSolidBackground")
                #expect(background.appearanceController === content.presentationController)
                try await verifyWideArrow(background, direction: direction, content: content, fixture: f)
                await f.dismiss(content)
            }
        }
    }

    /// 从实际内容位置核对四边边距；向上时再取样箭翼与主体，区分子类与默认尺寸、颜色。
    private func verifyWideArrow(_ drawing: some PopoverBackgroundDrawing, direction: UIPopoverArrowDirection,
                                 content: UIViewController, fixture: PopoverFixture) async throws {
        #expect(drawing.arrowDirection == direction)
        var insets = UIEdgeInsets(top: 9, left: 11, bottom: 13, right: 15)
        switch direction {
        case .up: insets.top += 24
        case .down: insets.bottom += 24
        case .left: insets.left += 24
        default: insets.right += 24
        }
        let rect = content.view.convert(content.view.bounds, to: drawing)
        #expect(rect == drawing.bounds.inset(by: insets))
        guard direction == .up else { return }
        let tipX = drawing.bounds.midX + drawing.arrowOffset
        let wing = drawing.convert(CGPoint(x: tipX + 12, y: 17), to: fixture.window)
        let body = drawing.convert(CGPoint(x: tipX, y: 30), to: fixture.window)
        let outside = drawing.convert(CGPoint(x: tipX + 50, y: 17), to: fixture.window)
        let green = try fixture.pixel(at: wing)
        let bodyColor = try fixture.pixel(at: body)
        let outsideColor = try fixture.pixel(at: outside)
        #expect(green[0] < 15 && green[1] > 240 && green[2] < 15)
        #expect(fixture.difference(green, bodyColor) <= 3)
        #expect(fixture.difference(green, outsideColor) > 100)

        if let controller = content.presentationController as? PopoverPresentationController {
            controller.backgroundColor = .blue
        } else {
            content.popoverPresentationController?.backgroundColor = .blue
        }
        fixture.window.layoutIfNeeded()
        await Task.yield()
        let blue = try fixture.pixel(at: wing)
        let blueBody = try fixture.pixel(at: body)
        #expect(blue[0] < 15 && blue[1] < 15 && blue[2] > 240)
        #expect(fixture.difference(blue, blueBody) <= 3)
    }

    /// 在同一个视图上切换外观，验证箭头和主体跟随系统背景色一起变化。
    @Test func solidBackgroundFollowsInterfaceStyle() throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .systemPink
        let origin = f.host.view.safeAreaLayoutGuide.layoutFrame.origin
        let background = SolidPopoverBackground(frame: CGRect(x: origin.x + 12, y: origin.y + 12,
                                                              width: 100, height: 80))
        background.arrowDirection = .up
        let reference = UIView(frame: background.frame.offsetBy(dx: 110, dy: 0))
        reference.backgroundColor = .systemBackground
        f.host.view.addSubview(background)
        f.host.view.addSubview(reference)
        var light: [UInt8] = []
        for style: UIUserInterfaceStyle in [.light, .dark] {
            f.window.overrideUserInterfaceStyle = style
            f.window.layoutIfNeeded()
            let expected = try f.pixel(at: reference.convert(CGPoint(x: 50, y: 40), to: f.window))
            for y: CGFloat in [8, 40] {
                let actual = try f.pixel(at: background.convert(CGPoint(x: 50, y: y), to: f.window))
                #expect(f.difference(actual, expected) <= 3)
            }
            if style == .light { light = expected }
            else { #expect(f.difference(expected, light) > 100) }
        }
    }

    /// 在实际填色遮罩上取点，区分圆尖和直线三角形，并检查主体圆角的内外侧。
    @Test func solidBackgroundRoundsTipRootsAndCorners() throws {
        let width: CGFloat = 200
        let height: CGFloat = 150
        for direction: UIPopoverArrowDirection in [.up, .down, .left, .right] {
            let horizontal = direction == .left || direction == .right
            let size = horizontal ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            let background = SolidPopoverBackground(frame: CGRect(origin: .zero, size: size))
            background.arrowDirection = direction
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                switch direction {
                case .down: return CGPoint(x: width - x, y: height - y)
                case .left: return CGPoint(x: y, y: width - x)
                case .right: return CGPoint(x: height - y, y: x)
                default: return CGPoint(x: x, y: y)
                }
            }
            for distance: CGFloat in [3, 24, 48, width / 2, width - 48, width - 24, width - 3] {
                let reversed = direction == .down || direction == .left
                background.arrowOffset = (distance - width / 2) * (reversed ? -1 : 1)
                background.layoutIfNeeded()
                let paths = background.subviews.compactMap { ($0.layer.mask as? CAShapeLayer)?.path }
                let path = try #require(paths.first)
                let tip = min(width - 19, max(19, distance))
                for sign: CGFloat in [-1, 1] {
                    #expect(path.contains(point(tip + sign * 1.5, 1)))
                    #expect(!path.contains(point(tip + sign * 12.5, 11)))
                    #expect(path.contains(point(tip + sign * 12.5, 12.5)))
                }
                for x: CGFloat in [6, width - 6] {
                    #expect(!path.contains(point(x, height - 6)))
                    if distance == width / 2 { #expect(!path.contains(point(x, 12 + 6))) }
                }
                for x: CGFloat in [9, width - 9] {
                    #expect(path.contains(point(x, height - 9)))
                    if distance == width / 2 { #expect(path.contains(point(x, 12 + 9))) }
                }
                if direction == .down && distance == width / 2 {
                    let image = UIGraphicsImageRenderer(size: size).image { background.layer.render(in: $0.cgContext) }
                    Attachment.record(try #require(image.pngData()), named: "solid-down-center.png")
                }
            }
        }
    }

    @Test func constrainedAnchorGeometry() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let safe = f.host.view.safeAreaLayoutGuide.layoutFrame
        var rows = ["来源\t指定方向\t边长\t距边\t允许重叠\tUIKit 外框\tQuickLayoutKit 外框\tUIKit 交集\tQuickLayoutKit 交集\tUIKit 箭头方向值\tQuickLayoutKit 箭头方向值"]
        let directions: [(String, UIPopoverArrowDirection)] = [("上", .up), ("下", .down), ("左", .left), ("右", .right)]
        for (name, direction) in directions {
            for size: CGFloat in [1, 30, 80] {
                // 一组紧贴安全区边缘，另一组保留部分空间，以覆盖压缩和移动两种情况。
                for gap: CGFloat in [3, 130 - size] {
                    var rect = CGRect(x: safe.midX - size / 2, y: safe.midY - size / 2, width: size, height: size)
                    switch direction {
                    case .up: rect.origin.y = safe.maxY - gap - size
                    case .down: rect.origin.y = safe.minY + gap
                    case .left: rect.origin.x = safe.maxX - gap - size
                    default: rect.origin.x = safe.minX + gap
                    }
                    for canvas in [false, true] {
                        f.source.frame = canvas ? f.host.view.bounds : rect
                        let sourceRect = canvas ? rect : f.source.bounds
                        for overlap in [false, true] {
                            let label = [canvas ? "画布" : "来源视图", name, "\(size)", "\(gap)"].joined(separator: "\t")
                            rows.append(try await f.compareAnchor(sourceRect, direction: direction, overlap: overlap, label: label))
                        }
                    }
                }
            }
        }
        Attachment.record(Data(rows.joined(separator: "\n").utf8), named: "四向靠边锚点对照.txt")
    }

    @Test func automaticArrowAtEdgesAndCorners() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let safe = f.host.view.safeAreaLayoutGuide.layoutFrame
        f.source.frame = f.host.view.bounds
        let positions: [(String, CGFloat, CGFloat)] = [
            ("上边", 0.5, 0), ("下边", 0.5, 1), ("左边", 0, 0.5), ("右边", 1, 0.5),
            ("左上", 0, 0), ("右上", 1, 0), ("左下", 0, 1), ("右下", 1, 1)
        ]
        var rows = ["位置\t边长\t距边\t允许重叠\tUIKit 外框\tQuickLayoutKit 外框\tUIKit 交集\tQuickLayoutKit 交集\tUIKit 箭头方向值\tQuickLayoutKit 箭头方向值"]
        for size: CGFloat in [1, 30, 80] {
            for gap: CGFloat in [0, 3] {
                let region = safe.insetBy(dx: gap, dy: gap)
                for (name, x, y) in positions {
                    let rect = CGRect(x: region.minX + (region.width - size) * x,
                                      y: region.minY + (region.height - size) * y, width: size, height: size)
                    for overlap in [false, true] {
                        let label = [name, "\(size)", "\(gap)"].joined(separator: "\t")
                        rows.append(try await f.compareAnchor(rect, direction: .any, overlap: overlap, label: label))
                    }
                }
            }
        }
        Attachment.record(Data(rows.joined(separator: "\n").utf8), named: "自动方向边角对照.txt")
    }

    /// 先读取原生默认值，再在同一窗口、同一锚点核对自定义控制器。
    @Test func sourceOverlapAndDimmingInsetDefaults() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let key = "_dimmingViewTopEdgeInset"
        let native = try await f.show(native: true, configureNative: { pc in
            #expect(!pc.canOverlapSourceViewRect)
            if pc.responds(to: NSSelectorFromString(key)) {
                #expect((pc.value(forKey: key) as? NSNumber)?.doubleValue == 0)
            }
        })
        let reference = try #require(native.popoverPresentationController)
        try #require(reference.responds(to: NSSelectorFromString(key)))
        let inset = try #require(reference.value(forKey: key) as? NSNumber).doubleValue
        let overlap = reference.canOverlapSourceViewRect
        await f.dismiss(native)
        let content = try await f.show(native: false)
        let pc = try #require(content.customPopoverPresentationController)
        #expect(pc.canOverlapSourceViewRect == overlap)
        #expect(Double(pc.dimmingViewTopEdgeInset) == inset)
        await f.dismiss(content)
    }

    /// 用示例菜单实际调用的访问器核对控制器及背景的值，兼顾无箭头时的内容区域。
    @Test func comparesPrivateUIKitAccessors() async throws {
        guard #available(iOS 26, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        let options: [PopoverComparisonOption] = [.hide, .inset, .style, .blur, .radius, .corners, .tint]
        let native = try await f.show(native: true, directions: .up, configureNative: { pc in options.forEach { $0.apply(to: pc) } })
        let reference = try #require(native.popoverPresentationController)
        PopoverComparisonOption.offset.apply(to: reference)
        reference.containerView?.layoutIfNeeded()
        let frame = native.view.convert(native.view.bounds, to: f.host.view)
        func number(_ key: String) throws -> Double {
            try #require(reference.value(forKey: key) as? NSNumber).doubleValue
        }
        let hide = try number("_shouldHideArrow")
        let offset = try number("_arrowOffset")
        let inset = try number("_dimmingViewTopEdgeInset")
        let style = try number("_popoverBackgroundStyle")
        let blur = try number("_backgroundBlurEffectStyle")
        let radius = try number("_cornerRadius")
        let color = reference.value(forKey: "arrowBackgroundColor") as? UIColor
        let nativeCorners = UIView()
        nativeCorners.setValue(reference.value(forKey: "_cornerConfiguration"), forKey: "cornerConfiguration")
        await f.dismiss(native)
        let content = try await f.show(native: false, directions: .up, configure: { pc in options.forEach { $0.apply(to: pc) } })
        let pc = try #require(content.customPopoverPresentationController)
        PopoverComparisonOption.offset.apply(to: pc)
        #expect(pc.shouldHideArrow == (hide != 0))
        #expect(Double(pc.arrowOffset) == offset)
        #expect(Double(pc.dimmingViewTopEdgeInset) == inset)
        #expect(Double(pc.popoverBackgroundStyle.rawValue) == style)
        #expect(pc.backgroundBlurEffectStyle?.rawValue == Int(blur))
        #expect(Double(pc.cornerRadius) == radius)
        #expect(pc.cornerConfiguration == nativeCorners.cornerConfiguration)
        #expect(pc.arrowBackgroundColor == color)
        let actual = content.view.convert(content.view.bounds, to: f.host.view)
        #expect(abs(actual.minY - frame.minY) <= 1 && abs(actual.height - frame.height) <= 1)
        await f.dismiss(content)
    }
}
#endif

extension PopoverPresentationTests {
    @Test func presentationBackgroundEffectMatchesUIKit() async throws {
        guard #available(iOS 26.1, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .red
        let underlying = try f.pixel(at: f.source.center)
        func visibleMaterial(in v: UIView) -> UIVisualEffectView? {
            guard !v.isHidden, v.alpha > 0 else { return nil }
            if let material = v as? UIVisualEffectView, material.effect != nil { return material }
            return v.subviews.lazy.compactMap { visibleMaterial(in: $0) }.first
        }
        for native in [true, false] {
            for effect in [UIBlurEffect(style: .dark), UIGlassEffect(style: .clear), UIColorEffect(color: .clear)] as [UIVisualEffect] {
                let content = try await f.show(native: native, configureNative: { $0.backgroundEffect = effect },
                                               configure: { $0.backgroundEffect = effect })
                let pc = try #require(content.presentationController)
                let view = try #require(pc.presentedView)
                let material = try #require(visibleMaterial(in: view))
                let actual = try #require(material.effect)
                #expect(type(of: actual) == type(of: effect))
                #expect(material.bounds.size == pc.frameOfPresentedViewInContainerView.size)
                if effect is UIColorEffect {
                    let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                    let sample = try f.pixel(at: view.convert(center, to: f.window))
                    #expect(f.difference(sample, underlying) <= 5, "透明效果，系统 \(native)，取样 \(sample)，底图 \(underlying)")
                }
                if !native {
                    pc.backgroundEffect = nil
                    pc.containerView?.layoutIfNeeded()
                    #expect(material.isHidden)
                }
                await f.dismiss(content)
            }
        }
    }

    @Test func presentationEffectWithTintAndAdaptation() async throws {
        guard #available(iOS 26.1, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        f.host.view.backgroundColor = .red
        for style: UIModalPresentationStyle in [.none, .pageSheet] {
            f.delegate.style = style
            var reference: [UInt8] = []
            for native in [true, false] {
                let effect = UIColorEffect(color: .systemGreen)
                let content = try await f.show(native: native, configureNative: {
                    $0.backgroundColor = .systemTeal
                    $0.backgroundEffect = effect
                }, configure: {
                    $0.backgroundColor = .systemTeal
                    $0.backgroundEffect = effect
                })
                let view = try #require(content.view)
                let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: f.window)
                let sample = try f.pixel(at: point)
                if native { reference = sample }
                else { #expect(f.difference(sample, reference) <= 5, "呈现样式 \(style.rawValue)，UIKit \(reference)，自定义 \(sample)") }
                await f.dismiss(content)
            }
        }
    }

    @Test func demoCanvasActivatesBothEngines() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let demo = PopoverPresentationExampleViewController()
        f.window.rootViewController = UINavigationController(rootViewController: demo)
        f.window.layoutIfNeeded()
        func find(_ id: String, in root: UIView) -> UIView? {
            root.accessibilityIdentifier == id ? root : root.subviews.lazy.compactMap { find(id, in: $0) }.first
        }
        let canvas = try #require(find("popover.canvas", in: demo.view) as? PopoverAnchorButton)
        let engine = try #require(find("popover.engine", in: demo.view) as? UISegmentedControl)
        let options = try #require(find("popover.options", in: demo.view) as? UIButton)
        func select(_ groupTitle: String, _ title: String) throws {
            func actions() -> [UIAction] {
                let menus = options.menu?.children.compactMap { $0 as? UIMenu } ?? []
                return menus.first { $0.title == groupTitle }?.children.compactMap { $0 as? UIAction } ?? []
            }
            let action = try #require(actions().first { $0.title == title })
            options.sendAction(action)
            #expect(actions().filter { $0.state == .on }.map(\.title) == [title])
        }
        // 在画布提示文字上铺均匀底图，避免透明箭头处的取样落在文字笔画上。
        let backdrop = UIView(frame: canvas.bounds)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.isUserInteractionEnabled = false
        canvas.addSubview(backdrop)
        // 从真实菜单重新呈现浮层，分别在箭头内部和主体内部取样。
        let reference = UIView(frame: CGRect(x: 0, y: f.window.bounds.midY, width: 8, height: 8))
        f.window.overrideUserInterfaceStyle = .light
        let arrowUp = try #require(options.menu?.children.compactMap { $0 as? UIAction }
            .first { $0.title == Localization.text("popover.up") })
        options.sendAction(arrowUp)
        for (key, defaultColor) in [("solidBackground", UIColor.systemBackground),
                                    ("outlinedBackground", UIColor.secondarySystemBackground),
                                    ("customOutlinedBackground", UIColor.systemYellow)] {
            try select("popoverBackgroundViewClass", Localization.text("popover." + key))
            let customOutline = key == "customOutlinedBackground"
            for index in [0, 1] {
                engine.selectedSegmentIndex = index
                engine.sendActions(for: .valueChanged)
                for (title, color) in [("systemTeal", UIColor.systemTeal), ("clear", .clear),
                                       (Localization.text("popover.default"), defaultColor)] {
                    try select("backgroundColor", title)
                    backdrop.backgroundColor = .red
                    #expect(canvas.accessibilityActivate())
                    try await Task.sleep(for: .milliseconds(720))
                    let content = try #require(demo.presentedViewController)
                    let controller = try #require(content.presentationController)
                    let container = try #require(controller.containerView)
                    let frame = container.convert(controller.frameOfPresentedViewInContainerView, to: f.window)
                    if customOutline {
                        if index == 0 {
                            let pc = try #require(controller as? PopoverPresentationController)
                            #expect(pc.popoverBackgroundViewClass == DemoOutlinedPopoverBackground.self)
                        } else {
                            let pc = try #require(controller as? UIPopoverPresentationController)
                            #expect(pc.popoverBackgroundViewClass == DemoUIOutlinedPopoverBackground.self)
                        }
                        // 从内容实际外框核对非对称边距；上方另含 24 pt 的箭头区域。
                        let contentFrame = content.view.convert(content.view.bounds, to: f.window)
                        #expect(contentFrame == frame.inset(by: .init(top: 24 + 9, left: 11, bottom: 13, right: 15)))
                    }
                    // (12, 17) 位于 64 pt 宽箭头的侧翼，可以检出退回默认底宽的情况。
                    let arrow = CGPoint(x: frame.midX + (customOutline ? 12 : 0), y: frame.minY + (customOutline ? 17 : 8))
                    let body = CGPoint(x: frame.midX, y: frame.minY + 36)
                    let points = [arrow, body]
                    let pixels = try points.map { try f.pixel(at: $0) }
                    if color == .clear {
                        func findBackground(in view: UIView) -> UIView? {
                            if view is SolidPopoverBackground || view is UIOutlinedPopoverBackground || view is OutlinedPopoverBackground { return view }
                            return view.subviews.lazy.compactMap { findBackground(in: $0) }.first
                        }
                        let background = try #require(findBackground(in: container))
                        // 保留同一浮层的内容、阴影和遮暗层，对照隐藏填色视图后的同位置像素。
                        for backdropColor: UIColor in [.red, .blue] {
                            backdrop.backgroundColor = backdropColor
                            let visible = try points.map { try f.pixel(at: $0) }
                            background.isHidden = true
                            let underlying = try points.map { try f.pixel(at: $0) }
                            background.isHidden = false
                            for (actual, expected) in zip(visible, underlying) {
                                #expect(f.difference(actual, expected) <= 12,
                                        "引擎 \(index)，\(key) 透明填充：\(actual) / 底图 \(expected)")
                            }
                        }
                    } else {
                        reference.backgroundColor = color.resolvedColor(with: content.traitCollection)
                        f.window.addSubview(reference)
                        let expected = try f.pixel(at: reference.center)
                        reference.removeFromSuperview()
                        for actual in pixels {
                            #expect(f.difference(actual, expected) <= 5,
                                    "引擎 \(index)，\(key) \(title)：\(actual) / \(expected)")
                        }
                    }
                    if key == "outlinedBackground" || customOutline {
                        let stroke = try f.pixel(at: CGPoint(x: frame.midX + 46, y: frame.minY + (customOutline ? 25 : 14)))
                        #expect(Int(stroke[2]) - max(Int(stroke[0]), Int(stroke[1])) > 55)
                    }
                    await f.dismiss(content)
                }
            }
        }
        #if DEBUG
        if #available(iOS 26, *) {
            // 通过实际菜单在同一背景类型上切换，检查上、下物理角并恢复默认。
            backdrop.backgroundColor = .red
            for index in [0, 1] {
                engine.selectedSegmentIndex = index
                engine.sendActions(for: .valueChanged)
                for key in ["solidBackground", "outlinedBackground"] {
                    try select("popoverBackgroundViewClass", Localization.text("popover." + key))
                    for option: PopoverComparisonOption in [.radius, .corners, .corners] {
                        let items = options.menu?.children.compactMap { $0 as? UIMenu }.flatMap(\.children) ?? []
                        let action = try #require(items.compactMap { $0 as? UIAction }.first { $0.title == option.rawValue })
                        let resets = action.state == .on
                        options.sendAction(action)
                        #expect(canvas.accessibilityActivate())
                        try await Task.sleep(for: .milliseconds(720))
                        let content = try #require(demo.presentedViewController)
                        let pc = try #require(content.presentationController)
                        let container = try #require(pc.containerView)
                        let frame = container.convert(pc.frameOfPresentedViewInContainerView, to: f.window)
                        let height = key == "solidBackground" ? SolidPopoverBackground.arrowHeight() : OutlinedPopoverBackground.arrowHeight()
                        for (y, top) in [(frame.minY + height + 4, true), (frame.maxY - 5, false)] {
                            let pixel = try f.pixel(at: CGPoint(x: frame.minX + 4, y: y))
                            let outside = Int(pixel[0]) - Int(pixel[2]) > 70
                            #expect(outside == (resets || (!top && option == .corners)),
                                    "引擎 \(index)，\(key)，\(option)，恢复 \(resets)，上角 \(top)：\(pixel)")
                        }
                        await f.dismiss(content)
                    }
                }
            }
        }
        #endif
        backdrop.removeFromSuperview()
        try select("backgroundColor", "systemTeal")
        try select("popoverLayoutMargins", "12 / 48 / 32 / 16 pt")
        try select("popoverBackgroundViewClass", Localization.text("popover.solidBackground"))
        try select("popoverBackgroundViewClass", Localization.text("popover.outlinedBackground"))
        if #available(iOS 26.1, *) { try select("backgroundEffect", "UIColorEffect · clear") }
        #expect(canvas.bounds.height > 100)
        #expect(canvas.accessibilityLabel?.isEmpty == false)
        #expect(canvas.sourceRect == CGRect(x: canvas.bounds.midX - 0.5, y: canvas.bounds.midY - 0.5, width: 1, height: 1))
        let point = CGPoint(x: canvas.bounds.maxX - 0.25, y: canvas.bounds.midY)
        canvas.selectAnchor(at: point)
        for side in [1, 30, 80] {
            try select("sourceRect", "\(side) pt")
            canvas.layoutIfNeeded()
            let length = CGFloat(side)
            let expected = CGRect(x: canvas.bounds.maxX - length, y: point.y - length / 2, width: length, height: length)
            let marker = try #require(canvas.layer.sublayers?.first { $0.name == "popover.sourceRect" })
            #expect(marker.frame == expected && !marker.isHidden)
            for allowOverlap in [true, false] {
                try select("canOverlapSourceViewRect", String(allowOverlap))
                for index in [0, 1] {
                    engine.selectedSegmentIndex = index
                    engine.sendActions(for: .valueChanged)
                    #expect(canvas.accessibilityActivate())
                    try await Task.sleep(for: .milliseconds(720))
                    let content = try #require(demo.presentedViewController)
                    let anchor = index == 0 ? content.customPopoverPresentationController?.sourceRect : content.popoverPresentationController?.sourceRect
                    #expect(anchor == expected)
                    let pc = try #require(content.presentationController)
                    let margins = UIEdgeInsets(top: 12, left: 48, bottom: 32, right: 16)
                    if let custom = pc as? PopoverPresentationController {
                        #expect(custom.canOverlapSourceViewRect == allowOverlap)
                        #expect(custom.backgroundColor == .systemTeal && custom.popoverLayoutMargins == margins)
                        #expect(custom.popoverBackgroundViewClass == OutlinedPopoverBackground.self)
                    } else {
                        let system = try #require(pc as? UIPopoverPresentationController)
                        #expect(system.canOverlapSourceViewRect == allowOverlap)
                        #expect(system.backgroundColor == .systemTeal && system.popoverLayoutMargins == margins)
                        #expect(system.popoverBackgroundViewClass == UIOutlinedPopoverBackground.self)
                    }
                    if #available(iOS 26.1, *) { #expect(pc.backgroundEffect is UIColorEffect) }
                    await f.dismiss(content)
                }
            }
        }
    }

    /// 在实际呈现的向下箭头背景上检查四处圆弧，避免斜切角再次通过布局测试。
    @Test func outlinedBackgroundDrawsRoundedCorners() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        f.window.overrideUserInterfaceStyle = .light
        f.host.view.backgroundColor = .white
        let content = try await f.show(native: false, directions: .down, configure: {
            $0.popoverBackgroundViewClass = OutlinedPopoverBackground.self
        })
        let pc = try #require(content.customPopoverPresentationController)
        let container = try #require(pc.containerView)
        let frame = container.convert(pc.frameOfPresentedViewInContainerView, to: f.window)
        let bodyBottom = frame.maxY - OutlinedPopoverBackground.arrowHeight()
        let stroke = try f.pixel(at: CGPoint(x: frame.midX, y: frame.minY + 1))
        let fill = try f.pixel(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(f.difference(stroke, fill) > 50)
        // 在圆角的对角线中点采到描边，排除直角和斜切。
        for x in [frame.minX + 11, frame.maxX - 12] {
            for y in [frame.minY + 11, bodyBottom - 12] {
                let corner = try f.pixel(at: CGPoint(x: x, y: y))
                #expect(f.difference(stroke, corner) < 35)
            }
        }
        let crop = frame.insetBy(dx: -8, dy: -8)
        let image = UIGraphicsImageRenderer(size: crop.size).image { context in
            context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true)
        }
        Attachment.record(try #require(image.pngData()), named: "RoundedPopover.png")
        await f.dismiss(content)
    }

    /// 从窗口截图的物理像素量取外沿，各方向统一为箭头朝上、锚点靠左。
    private func contourSamples(_ image: UIImage, direction: UIPopoverArrowDirection, far: Bool,
                                centered: Bool, outlined: Bool, allCorners: Bool, arrowHeight: CGFloat = 13) throws -> [CGFloat] {
        let source = try #require(image.cgImage)
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        }
        let vertical = direction == .up || direction == .down
        let span = vertical ? width : height
        let thickness = vertical ? height : width
        let scale = image.scale
        func edges(at depth: CGFloat, opposite: Bool = false) throws -> (CGFloat, CGFloat) {
            let fromEdge = Int((8 + depth + 0.5) * scale)
            let fromEnd = (direction == .down || direction == .right) != opposite
            let row = fromEnd ? thickness - 1 - fromEdge : fromEdge
            let hits = (0..<span).filter { column in
                let t = far ? span - 1 - column : column
                let i = 4 * (vertical ? row * width + t : t * width + row)
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                return min(r, g, b) > 225 || (outlined && b - max(r, g) > 55)
            }
            let first = try #require(hits.first)
            let last = try #require(hits.last)
            return ((CGFloat(first) + 0.5) / scale - 8, (CGFloat(span - last) - 0.5) / scale - 8)
        }
        var samples: [CGFloat] = []
        let bodyWidth = CGFloat(span) / scale - 16
        // 箭头用同一锚点对齐。两种呈现的内容内边距可以不同，因此圆角各自从最近的边量起。
        for depth: CGFloat in [1, 6, 10] {
            let (left, right) = try edges(at: depth)
            let origin = centered ? bodyWidth / 2 : 0
            samples.append(contentsOf: [left - origin, bodyWidth - right - origin])
        }
        for depth: CGFloat in (allCorners ? [3, 8, 16] : [3, 8]) {
            let (left, right) = try edges(at: arrowHeight + depth)
            samples.append(left)
            if allCorners {
                let (oppositeLeft, oppositeRight) = try edges(at: depth, opposite: true)
                samples.append(contentsOf: [right, oppositeLeft, oppositeRight])
            }
        }
        return samples
    }

    /// 固定方向并沿横轴移动真实锚点，对照 UIKit 默认轮廓和两套呈现中的同一描边。
    @Test func outlinedArrowNearCornersComparedWithUIKit() async throws {
        try await compareArrowNearCorners(outlined: true)
    }

    @Test func defaultGlassArrowNearCornersComparedWithUIKit() async throws {
        guard #available(iOS 26, *) else { return }
        try await compareArrowNearCorners(outlined: false)
    }

    /// 在同一个已呈现的浮层上改变配置，覆盖零半径、左右不对称以及恢复背景默认值。
    @Test func customCornersUpdateWhilePresented() async throws {
        guard #available(iOS 26, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        f.window.overrideUserInterfaceStyle = .light
        f.host.view.backgroundColor = .red
        for native in [false, true] {
            for outlined in [false, true] {
                let content = try await f.show(native: native, directions: .left,
                    background: outlined ? UIOutlinedPopoverBackground.self : SolidPopoverBackground.self,
                    configure: { if outlined { $0.popoverBackgroundViewClass = OutlinedPopoverBackground.self } })
                let pc = try #require(content.presentationController)
                let host = try #require(pc.containerView)
                let configuration = UICornerConfiguration.uniformEdges(leftRadius: .fixed(0), rightRadius: .fixed(28))
                for step in 0..<3 {
                    if let custom = pc as? PopoverPresentationController {
                        if step == 0 { custom.cornerConfiguration = configuration }
                        else if step == 1 { custom.cornerRadius = 0 }
                        else { custom.cornerConfiguration = nil }
                    } else {
                        let system = try #require(pc as? UIPopoverPresentationController)
                        if step == 0 { system.setCustomBackgroundCornerConfiguration(configuration) }
                        else if step == 1 { system.setCustomBackgroundCornerRadius(0) }
                        else { system.setCustomBackgroundCornerConfiguration(nil) }
                    }
                    host.layoutIfNeeded()
                    let frame = host.convert(pc.frameOfPresentedViewInContainerView, to: f.window)
                    let arrow = outlined ? OutlinedPopoverBackground.arrowHeight() : SolidPopoverBackground.arrowHeight()
                    for left in [true, false] {
                        let point = CGPoint(x: left ? frame.minX + arrow + 4 : frame.maxX - 5, y: frame.minY + 4)
                        let pixel = try f.pixel(at: point)
                        #expect((Int(pixel[0]) - Int(pixel[2]) > 70) == (step == 2 || (step == 0 && !left)),
                                "原生 \(native)，描边 \(outlined)，配置 \(step)，左角 \(left)：\(pixel)")
                    }
                }
                await f.dismiss(content)
            }
        }
    }

    #if DEBUG
    @Test func configuredBackgroundCornersComparedWithUIKit() async throws {
        guard #available(iOS 26, *) else { return }
        for option: PopoverComparisonOption in [.radius, .corners] {
            for outlined in [false, true] {
                try await compareArrowNearCorners(outlined: outlined, option: option)
            }
        }
    }
    #endif

    private func compareArrowNearCorners(outlined: Bool, option: PopoverComparisonOption? = nil) async throws {
        let solid = !outlined && option != nil
        let hasCustomBackground = outlined || solid
        let type: (any UIPopoverBackgroundViewMethods.Type)? = outlined ? OutlinedPopoverBackground.self :
            (solid ? SolidPopoverBackground.self : nil)
        let f = try PopoverFixture()
        defer { f.close() }
        f.window.overrideUserInterfaceStyle = .light
        f.host.view.backgroundColor = UIColor(white: 0.82, alpha: 1)
        let bounds = f.host.view.bounds
        // 将可用区域缩进窗口，截图可完整保留箭头、描边和原生阴影。
        let margins = UIEdgeInsets(top: 64, left: 64, bottom: 64, right: 64)
        let directions: [(String, UIPopoverArrowDirection)] = [("up", .up), ("down", .down), ("left", .left), ("right", .right)]
        for (name, direction) in directions {
            let vertical = direction == .up || direction == .down
            for far in [false, true] {
                func placeSource(at coordinate: CGFloat) {
                    f.source.center = vertical ? CGPoint(x: coordinate, y: bounds.midY) : CGPoint(x: bounds.midX, y: coordinate)
                }
                placeSource(at: far ? (vertical ? bounds.maxX : bounds.maxY) - 1 : 1)
                let probe = try await f.show(native: false, directions: direction, configure: {
                    $0.popoverBackgroundViewClass = type
                    $0.popoverLayoutMargins = margins
                })
                let probePC = try #require(probe.customPopoverPresentationController)
                let container = try #require(probePC.containerView)
                let limit = container.convert(probePC.frameOfPresentedViewInContainerView, to: f.host.view)
                await f.dismiss(probe)
                let edge = vertical ? (far ? limit.maxX : limit.minX) : (far ? limit.maxY : limit.minY)
                var nativeEdge = edge
                if let option {
                    placeSource(at: edge + (far ? -24 : 24))
                    // 显式小圆角会改变系统背景的可用外框。分别量出边界，使锚点距各自边缘同样远。
                    let native = try await f.show(native: true, directions: direction, configureNative: {
                        $0.popoverLayoutMargins = margins
                        #if DEBUG
                        option.apply(to: $0)
                        #endif
                    })
                    let pc = try #require(native.popoverPresentationController)
                    let host = try #require(pc.containerView)
                    let rect = host.convert(pc.frameOfPresentedViewInContainerView, to: f.host.view)
                    nativeEdge = vertical ? (far ? rect.maxX : rect.minX) : (far ? rect.maxY : rect.minY)
                    await f.dismiss(native)
                }
                var distances: [Int?] = [48, 24, 3]
                if hasCustomBackground && !far { distances.append(nil) }
                for distance in distances {
                    let center = vertical ? bounds.midX : bounds.midY
                    let position = distance.map { "\(far ? "end" : "start")-\($0)" } ?? "center"
                    var reference: CGFloat = 0
                    var nativeSamples: [CGFloat] = []
                    for mode in (hasCustomBackground ? ["system", "wrapper", "custom"] : ["system", "custom"]) {
                        let referenceEdge = mode == "custom" ? edge : nativeEdge
                        placeSource(at: distance.map { referenceEdge + CGFloat(far ? -$0 : $0) } ?? center)
                        let content = try await f.show(native: mode != "custom", directions: direction,
                            background: mode == "wrapper" ? (solid ? SolidPopoverBackground.self : UIOutlinedPopoverBackground.self) : nil,
                            configureNative: {
                                $0.popoverLayoutMargins = margins
                                #if DEBUG
                                option?.apply(to: $0)
                                #endif
                            },
                            configure: {
                                option?.apply(to: $0)
                                $0.popoverLayoutMargins = margins
                                $0.popoverBackgroundViewClass = type
                            })
                        let pc = try #require(content.presentationController)
                        let host = try #require(pc.containerView)
                        let frame = host.convert(pc.frameOfPresentedViewInContainerView, to: f.window)
                        let actual = content.customPopoverPresentationController?.arrowDirection ?? content.popoverPresentationController?.arrowDirection
                        #expect(actual == direction)
                        if mode == "wrapper" {
                            func wrapper(in view: UIView) -> UIPopoverBackgroundView? {
                                view as? UIPopoverBackgroundView ?? view.subviews.lazy.compactMap { wrapper(in: $0) }.first
                            }
                            reference = try #require(wrapper(in: host)).arrowOffset
                        } else if mode == "custom" {
                            let offset = try #require(content.customPopoverPresentationController).arrowOffset
                            if hasCustomBackground {
                                #expect(abs(offset - reference) <= 1, "\(name) \(position): UIKit \(reference), QuickLayoutKit \(offset)")
                            }
                            let span = vertical ? frame.width : frame.height
                            if let distance {
                                #expect(abs(span / 2 - abs(offset) - CGFloat(distance)) <= 1)
                            } else {
                                #expect(abs(offset) <= 1)
                            }
                        }
                        let crop = frame.insetBy(dx: -8, dy: -8)
                        let image = UIGraphicsImageRenderer(size: crop.size).image { ctx in
                            ctx.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
                            f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true)
                        }
                        let prefix = option.map { "\($0 == .radius ? "uniform" : "mixed")-\(solid ? "solid" : "outline")-" } ?? ""
                        Attachment.record(try #require(image.pngData()), named: "\(prefix)\(name)-\(position)-\(mode).png")
                        if #available(iOS 27.2, *) {
                            let samples = try contourSamples(image, direction: direction, far: far,
                                centered: distance == nil, outlined: outlined && mode != "system", allCorners: hasCustomBackground,
                                arrowHeight: solid && mode != "system" ? SolidPopoverBackground.arrowHeight() : 13)
                            if mode == "system" {
                                nativeSamples = samples
                            } else {
                                // 前六项量箭头两侧；显式圆角在主体四角的各采样深度最多允许相差两个物理像素。
                                let cornerTolerance = option == nil ? 3 + 1 / image.scale : 2 / image.scale
                                for (index, pair) in zip(samples, nativeSamples).enumerated() {
                                    let tolerance: CGFloat = index < 6 ? 1.5 : cornerTolerance
                                    #expect(abs(pair.0 - pair.1) <= tolerance + 0.001,
                                            "\(name) \(position) \(mode) 采样 \(index)：\(pair.0) / UIKit \(pair.1)")
                                }
                            }
                        }
                        await f.dismiss(content)
                    }
                }
            }
        }
    }

    /// 普通视图接收实时箭头布局；切回默认背景后，应移除旧视图并恢复默认尺寸。
    @Test func customDrawingRelayoutAndReplacement() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let content = try await f.show(native: false, directions: .up, configure: {
            $0.popoverBackgroundViewClass = WideArrowBackground.self
        })
        let pc = try #require(content.customPopoverPresentationController)
        let container = try #require(pc.containerView)
        func drawing(in root: UIView) -> WideArrowBackground? {
            root as? WideArrowBackground ?? root.subviews.lazy.compactMap { drawing(in: $0) }.first
        }
        let background = try #require(drawing(in: container))
        #expect(background.accessibilityIdentifier == "wideOutlinedBackground")
        #expect(background.appearanceController === pc)
        for direction: UIPopoverArrowDirection in [.up, .down, .left, .right] {
            pc.permittedArrowDirections = direction
            container.layoutIfNeeded()
            #expect(background.arrowDirection == direction)
            pc.arrowOffset = -19
            #expect(background.arrowOffset == -19)
            if direction == .up {
                // 在加宽后的箭翼内部取色，同时在箭翼外侧确认主体从 24 pt 之后才开始。
                let tipX = background.bounds.midX + background.arrowOffset
                let inside = try f.pixel(at: background.convert(CGPoint(x: tipX + 12, y: 17), to: f.window))
                let outside = try f.pixel(at: background.convert(CGPoint(x: tipX + 50, y: 17), to: f.window))
                #expect(inside[1] > 240 && inside[0] < 15 && inside[2] < 15)
                #expect(f.difference(inside, outside) > 100)
            }
            let rect = content.view.convert(content.view.bounds, to: background)
            let insets = WideArrowBackground.contentViewInsets()
            let height = WideArrowBackground.arrowHeight()
            #expect(rect.minX == insets.left + (direction == .left ? height : 0))
            #expect(rect.minY == insets.top + (direction == .up ? height : 0))
            #expect(background.bounds.width - rect.maxX == insets.right + (direction == .right ? height : 0))
            #expect(background.bounds.height - rect.maxY == insets.bottom + (direction == .down ? height : 0))
        }
        pc.shouldHideArrow = true
        container.layoutIfNeeded()
        #expect(background.arrowDirection.isEmpty)
        let customSize = pc.frameOfPresentedViewInContainerView.size
        pc.popoverBackgroundViewClass = nil
        container.layoutIfNeeded()
        #expect(background.superview == nil)
        #expect(pc.frameOfPresentedViewInContainerView.width < customSize.width)
        pc.popoverBackgroundViewClass = WideArrowBackground.self
        container.layoutIfNeeded()
        #expect(drawing(in: container) != nil)
        #expect(pc.frameOfPresentedViewInContainerView.size == customSize)
        await f.dismiss(content)
    }

    @Test func invalidAnchorAndKeyboardRelayout() async throws {
        let f = try PopoverFixture()
        defer { f.close() }
        let rejected = UIViewController()
        #expect(!f.host.presentPopover(rejected) { $0.sourceView = UIView() })
        #expect(rejected.transitioningDelegate == nil)
        let content = try await f.show(native: false, directions: .down)
        let pc = try #require(content.customPopoverPresentationController)
        let before = pc.frameOfPresentedViewInContainerView
        let container = try #require(pc.containerView)
        let keyboard = CGRect(x: 0, y: before.midY, width: container.bounds.width, height: container.bounds.maxY - before.midY)
        let screen = f.window.screen
        NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: screen,
                                        userInfo: [UIResponder.keyboardFrameEndUserInfoKey: container.convert(keyboard, to: screen.coordinateSpace)])
        container.layoutIfNeeded()
        #expect(pc.frameOfPresentedViewInContainerView.maxY <= keyboard.minY + 1)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: screen)
        container.layoutIfNeeded()
        #expect(pc.frameOfPresentedViewInContainerView == before)
        await f.dismiss(content)
    }
}

extension PopoverPresentationTests {
    /// 在同一个窗口截取弹层外框及其阴影；折叠设备的测试进程可能位于另一块显示器。
    @Test func defaultGlassOutlineMatchesUIKit() async throws {
        guard #available(iOS 26, *) else { return }
        let f = try PopoverFixture()
        defer { f.close() }
        f.window.overrideUserInterfaceStyle = .light
        f.host.view.backgroundColor = .white
        f.source.center = CGPoint(x: f.window.bounds.width * 0.30, y: f.window.bounds.midY)
        var reference: (edge: Int, body: Int)?
        for native in [true, false] {
            let content = try await f.show(native: native, directions: .down)
            let pc = try #require(content.presentationController)
            let container = try #require(pc.containerView)
            let rect = container.convert(pc.frameOfPresentedViewInContainerView, to: f.window).insetBy(dx: -25, dy: -25)
            let format = UIGraphicsImageRendererFormat()
            format.preferredRange = .standard
            format.scale = f.window.traitCollection.displayScale
            let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
                ctx.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                #expect(f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true))
            }
            // 左侧直边取最低亮度，容许轮廓在相邻物理像素间发生抗锯齿偏移。
            let scale = format.scale
            let strip = CGRect(x: 22 * scale, y: image.size.height * scale / 2,
                               width: 32 * scale, height: 1).integral
            let pixels = try #require(image.cgImage?.cropping(to: strip))
            var row = [UInt8](repeating: 0, count: pixels.width)
            try row.withUnsafeMutableBytes { bytes in
                let gray = try #require(CGContext(data: bytes.baseAddress, width: pixels.width, height: 1,
                                                  bitsPerComponent: 8, bytesPerRow: pixels.width,
                                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
                gray.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: 1))
            }
            let edge = Int(try #require(row.prefix(Int(7 * scale)).min()))
            let body = Int(try #require(row.last))
            // 系统在不同版本上的边线对比度不同，先确认有边线，再与同机截图比较。
            #expect(edge < body)
            if let reference {
                #expect(abs(edge - reference.edge) <= 15)
                #expect(abs(body - reference.body) <= 5)
            } else {
                reference = (edge, body)
            }
            Attachment.record(try #require(image.pngData()), named: native ? "UIKit-Outline.png" : "QuickLayoutKit-Outline.png")
            await f.dismiss(content)
        }
    }
}
