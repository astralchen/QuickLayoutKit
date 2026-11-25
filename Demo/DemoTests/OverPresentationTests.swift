import Testing
import UIKit
@testable import QuickLayoutKitUIKit

@MainActor
@Suite(.serialized)
struct OverPresentationTests {
    @Test func backgroundEffectFollowsPresentedPanelAndSelectedDetent() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        let content = UIViewController()
        content.view.backgroundColor = .clear
        let initial = OverPresentationController.Detent.absolute(240)
        initial.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        await withCheckedContinuation { c in
            host.presentOver(content, animated: false, configure: { $0.detent = initial }, completion: { c.resume() })
        }
        let controller = try #require(content.overPresentationController)
        let container = try #require(controller.containerView)
        let material = try #require(container.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let materialIndex = try #require(container.subviews.firstIndex(of: material))
        let contentIndex = try #require(container.subviews.firstIndex(of: content.view))
        #expect(materialIndex < contentIndex)
        #expect(material.frame == content.view.frame)
        #expect(material.effect != nil)
        #expect(!material.isUserInteractionEnabled)

        let replacement = OverPresentationController.Detent.absolute(200)
        controller.detent = replacement
        container.layoutIfNeeded()
        #expect(material.effect == nil)
        #expect(material.frame == content.view.frame)
        #expect(material.bounds.width == 200)
        // 切换档位后，只有当前实例的修改应更新可见材质。
        initial.backgroundEffect = UIBlurEffect(style: .light)
        #expect(material.effect == nil)
        replacement.backgroundEffect = UIBlurEffect(style: .dark)
        #expect(material.effect != nil)
        replacement.backgroundEffect = nil
        #expect(material.effect == nil)

        await withCheckedContinuation { c in content.dismiss(animated: false) { c.resume() } }
        #expect(material.superview == nil)
    }

    @Test func automaticWidthUsesContainerSizeClasses() {
        func width(_ w: CGFloat, _ h: CGFloat, _ horizontal: UIUserInterfaceSizeClass,
                   _ vertical: UIUserInterfaceSizeClass) -> CGFloat {
            let traits = UITraitCollection {
                $0.horizontalSizeClass = horizontal
                $0.verticalSizeClass = vertical
            }
            return OverPresentationController.automaticWidth(in: CGRect(x: 0, y: 0, width: w, height: h),
                traits: traits, divisions: [], onRight: true, preferred: 0)
        }
        #expect(width(400, 840, .compact, .regular) == 320)
        #expect(width(800, 400, .compact, .compact) == 400)
        #expect(width(700, 950, .regular, .regular) == 350)
        #expect(width(700, 950, .compact, .regular) == 560)
        #expect(width(320, 180, .compact, .compact) == 256)
        #expect(width(600, 900, .regular, .regular) == 320)
        #expect(width(1366, 1024, .regular, .regular) == 480)
    }

    @Test func automaticWidthUsesActiveDivisionAtPresentationEdge() {
        let bounds = CGRect(x: 20, y: 30, width: 900, height: 650)
        let book = CGRect(x: 400, y: 30, width: 24, height: 650)
        let tabletop = CGRect(x: 20, y: 310, width: 900, height: 20)
        func width(_ division: CGRect, right: Bool = true, preferred: CGFloat = 0) -> CGFloat {
            OverPresentationController.automaticWidth(in: bounds, traits: .init(horizontalSizeClass: .regular),
                divisions: [division], onRight: right, preferred: preferred)
        }
        #expect(width(book, right: false) == 380)
        #expect(width(book) == 496)
        #expect(width(book, preferred: 300) == 300)
        #expect(width(book, preferred: 800) == 496)
        #expect(width(book, preferred: .infinity) == 496)
        #expect(width(CGRect(x: 400, y: 30, width: 0, height: 650)) == 520)
        #expect(width(tabletop) == 450)
        #expect(width(book.insetBy(dx: 0, dy: 120)) == 450)
    }

    @Test func detentAndPresenterEffectsUpdateInPlace() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        host.view.semanticContentAttribute = .forceLeftToRight
        let content = UIViewController()
        content.preferredContentSize.width = 210
        await withCheckedContinuation { c in
            host.presentOver(content, from: .leading, animated: false, completion: { c.resume() })
        }
        let controller = try #require(content.overPresentationController)
        let container = try #require(controller.containerView)
        #expect(abs(content.view.bounds.width - 210) < 1)
        #expect(abs(host.view.transform.tx - 210) < 1)
        content.preferredContentSize.width = 190
        container.layoutIfNeeded()
        #expect(abs(content.view.bounds.width - 190) < 1)
        if #available(iOS 17, *) {
            content.preferredContentSize.width = 0
            container.traitOverrides.verticalSizeClass = .regular
            for horizontal: UIUserInterfaceSizeClass in [.compact, .regular] {
                // 只切换容器的尺寸类别，面板及底页应在下一轮布局一起更新。
                container.traitOverrides.horizontalSizeClass = horizontal
                container.updateTraitsIfNeeded()
                container.layoutIfNeeded()
                let expected = controller.frameOfPresentedViewInContainerView
                #expect(expected.width > 190)
                #expect(abs(content.view.frame.width - expected.width) < 1)
                #expect(abs(host.view.transform.tx - expected.width) < 1)
            }
        }
        controller.detent = .fractional(0.4)
        container.layoutIfNeeded()
        #expect(abs(content.view.bounds.width - container.bounds.width * 0.4) < 1)
        let referenceView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        var resolvedContext: (any OverPresentationControllerDetentResolutionContext)?
        let custom = OverPresentationController.Detent.custom { context in
            resolvedContext = context
            return min(referenceView.bounds.width, context.maximumDetentValue)
        }
        controller.detent = custom
        controller.presentingViewEffect = .parallax(factor: 0.5)
        container.layoutIfNeeded()
        #expect(controller.detent === custom)
        let context = try #require(resolvedContext)
        #expect(context.containerSize == container.bounds.size)
        #expect(context.maximumDetentValue == container.bounds.width)
        #expect(context.containerTraitCollection == container.traitCollection)
        #expect(context.safeAreaInsets == container.safeAreaInsets)
        #expect(context.preferredContentSize == content.preferredContentSize)
        #expect(abs(content.view.bounds.width - 300) < 1)
        #expect(abs(host.view.transform.tx - 150) < 1)
        referenceView.bounds.size.width = 250
        controller.invalidateDetent()
        container.layoutIfNeeded()
        #expect(abs(content.view.bounds.width - 250) < 1)
        controller.detent = .absolute(10_000)
        controller.presentingViewEffect = .overlay
        container.layoutIfNeeded()
        #expect(content.view.bounds.width == container.bounds.width)
        #expect(host.view.transform == .identity)
        await withCheckedContinuation { c in content.dismiss(animated: false) { c.resume() } }
        #expect(content.transitioningDelegate == nil)
        #expect(host.view.transform == .identity)
    }
}
