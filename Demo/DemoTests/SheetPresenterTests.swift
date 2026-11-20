import UIKit
import Testing
@testable import QuickLayoutKitUIKit

@MainActor
struct SheetPresenterTests {
    private enum Engine: String, CaseIterable { case native, sheet, panel }
    private struct Page {
        let controller: UIViewController
        let surface: UIView
        let select: (Int) -> Void
        let close: () async -> Void
    }

    /// 使用相同内容分别覆盖窗口根页和已经展示的 sheet，并实测关闭后的还原。
    @Test func comparesPresentingPage() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .systemBlue
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        var baseline: [String: [CGRect]] = [:]
        func record(_ engine: Engine, _ state: String, _ views: UIView...) {
            let frames = views.map { $0.convert($0.bounds, to: window) }
            print("PRESENTER",window.bounds.size,engine.rawValue,state,frames)
            if engine == .native { baseline[state] = frames; return }
            for (actual, expected) in zip(frames, baseline[state] ?? []) {
                for (a,b) in zip([actual.minX, actual.minY, actual.width, actual.height],
                                 [expected.minX, expected.minY, expected.width, expected.height]) {
                    #expect(abs(a-b) <= 1, "\(engine) \(state) \(actual) vs \(expected)")
                }
            }
        }
        for engine in Engine.allCases {
            let base = try await open(engine, from: host)
            for (index, name) in ["third", "medium", "nearLarge", "large", "mediumAgain"].enumerated() {
                base.select(index == 4 ? 1 : index)
                try await Task.sleep(for: .milliseconds(220))
                record(engine, name, host.view, base.surface)
            }
            for lower in [1,3] {
                base.select(lower)
                try await Task.sleep(for: .milliseconds(220))
                let front = try await open(engine, from: base.controller)
                for upper in [0,2] {
                    front.select(upper)
                    try await Task.sleep(for: .milliseconds(220))
                    record(engine, "stack-\(lower)-custom-\(upper)", host.view, base.surface, front.surface)
                }
                for (step, upper) in [1,3,1].enumerated() {
                    front.select(upper)
                    try await Task.sleep(for: .milliseconds(250))
                    record(engine, "stack-\(lower)-\(step)", host.view, base.surface, front.surface)
                }
                await front.close()
                try await Task.sleep(for: .milliseconds(150))
                record(engine, "unstack-\(lower)", host.view, base.surface)
            }
            await base.close()
            record(engine, "closed", host.view)
        }
    }

    /// 在白底上直接读取合成后的像素，验证两层不会重复遮暗窗口，且上层消失后恢复下层状态。
    @Test func stackedDimmingCompositesPageAndCardSeparately() throws {
        let page = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        page.backgroundColor = .white
        let backdrop = UIView(frame: page.bounds)
        page.addSubview(backdrop)
        let card = UIView(frame: CGRect(x: 0, y: 20, width: 40, height: 20))
        card.backgroundColor = .white
        page.addSubview(card)
        let lower = SheetDimming()
        lower.install(in: backdrop, surface: card, above: nil)
        let upper = SheetDimming()
        upper.install(in: UIView(), surface: UIView(), above: lower)

        func red(at y: CGFloat) throws -> Int {
            var pixel = [UInt8](repeating: 0, count: 4)
            return try pixel.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.translateBy(x: -10, y: -y)
                page.layer.render(in: context)
                return Int(bytes[0])
            }
        }
        upper.amount = 0.5
        #expect(abs(try red(at: 5) - 230) <= 1)
        #expect(abs(try red(at: 25) - 240) <= 1)
        lower.amount = 1
        upper.amount = 1
        #expect(abs(try red(at: 5) - 204) <= 1)
        #expect(abs(try red(at: 25) - 224) <= 1)
        upper.remove()
        #expect(abs(try red(at: 5) - 204) <= 1)
        #expect(try red(at: 25) == 255)
        lower.remove()
        #expect(try red(at: 5) == 255)
    }

    @Test func embeddedPanelLeavesHostAtItsOriginalSize() {
        let host = UIViewController()
        let local = UIView(frame: CGRect(x: 24, y: 60, width: 280, height: 390))
        host.view.addSubview(local)
        local.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        let original = local.transform
        let panel = AdaptivePanelController(contentView: UIView())
        panel.show(in: host, containerView: local, animated: false)
        #expect(panel.view.superview === local)
        #expect(local.transform == original)
        panel.dismiss(animated: false)
        #expect(local.transform == original)
    }

    private func open(_ engine: Engine, from host: UIViewController) async throws -> Page {
        let vc = UIViewController()
        vc.view.backgroundColor = .white
        let ids: [UISheetPresentationController.Detent.Identifier] = [.init("third"), .medium, .init("near"), .large]
        let close = { @MainActor in
            await withCheckedContinuation { c in vc.dismiss(animated: false) { c.resume() } }
        }
        switch engine {
        case .native:
            vc.modalPresentationStyle = .pageSheet
            let sheet = try #require(vc.sheetPresentationController)
            sheet.detents = [.custom(identifier: ids[0]) { $0.maximumDetentValue / 3 }, .medium(),
                             .custom(identifier: ids[2]) { $0.maximumDetentValue * 0.95 }, .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.prefersPageSizing = true
            await withCheckedContinuation { c in host.present(vc, animated: false) { c.resume() } }
            return Page(controller: vc, surface: vc.view, select: { sheet.selectedDetentIdentifier = ids[$0] }, close: close)
        case .sheet:
            let keys: [SheetPresentationController.Detent.Identifier] = ["third", .medium, "near", .large]
            await withCheckedContinuation { c in host.presentSheet(vc, animated: false) { sheet in
                sheet.detents = [.custom(identifier: keys[0]) { $0.maximumDetentValue / 3 }, .medium(),
                                 .custom(identifier: keys[2]) { $0.maximumDetentValue * 0.95 }, .large()]
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.prefersPageSizing = true
            } completion: { c.resume() } }
            let sheet = try #require(vc.customSheetPresentationController)
            return Page(controller: vc, surface: try #require(sheet.presentedView), select: { sheet.selectedDetentIdentifier = keys[$0] }, close: close)
        case .panel:
            let panel = AdaptivePanelController(contentViewController: vc)
            let keys: [AdaptivePanelDetent.Identifier] = ["third", .medium, "near", .large]
            panel.safeAreaSource = .window
            panel.detents = [.custom(identifier: keys[0]) { $0.maximumDetentValue / 3 }, .medium(),
                            .custom(identifier: keys[2]) { $0.maximumDetentValue * 0.95 }, .large()]
            panel.show(in: host, animated: false)
            return Page(controller: vc, surface: panel.surface, select: { panel.selectDetent(keys[$0], animated: false) },
                        close: { panel.dismiss(animated: false) })
        }
    }
}
