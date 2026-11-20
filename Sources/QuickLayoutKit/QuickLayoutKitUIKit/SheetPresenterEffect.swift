import UIKit

/// 只修改当前容器中可见的后页。保存调用方原有的变换和裁切，退档或关闭时恢复。
@MainActor
final class SheetPresenterEffect {
    @MainActor private final class Page {
        weak var view: UIView?
        private let transform: CGAffineTransform
        private let radius: CGFloat
        private let clips: Bool
        private var backing: UIView?
        private weak var fullWindow: UIWindow?

        init(_ view: UIView, blackBacking: Bool) {
            self.view = view
            transform = view.transform
            radius = view.layer.cornerRadius
            clips = view.clipsToBounds
            if blackBacking, let parent = view.superview {
                if let window = view.window, view.convert(view.bounds, to: window).equalTo(window.bounds) {
                    fullWindow = window
                }
                let black = UIView(frame: parent.bounds)
                black.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                black.backgroundColor = .black
                black.isUserInteractionEnabled = false
                parent.insertSubview(black, belowSubview: view)
                backing = black
            }
        }

        /// 旋转时 UIKit 会给根视图设置新 frame。已有缩放时，这会反向改变 bounds；
        /// 以新窗口的自然尺寸布局，再叠加当前档位的变换。
        private func updateWindowBounds() {
            guard let view, let window = fullWindow, let parent = view.superview else { return }
            let rect = parent.convert(window.bounds, from: window)
            if view.bounds.size != rect.size { view.bounds.size = rect.size }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if view.center != center { view.center = center }
        }

        func apply(scale: CGFloat, scaleY: CGFloat? = nil, offsetY: CGFloat, cornerFraction: CGFloat?) {
            updateWindowBounds()
            let effect = CGAffineTransform(a: scale, b: 0, c: 0, d: scaleY ?? scale, tx: 0, ty: offsetY)
            let value = transform.concatenating(effect)
            if view?.transform != value { view?.transform = value }
            if let cornerFraction, let view {
                view.layer.cornerRadius = radius + (10 - radius) * cornerFraction
                view.clipsToBounds = true
            }
        }

        func restore() {
            view?.transform = transform
            updateWindowBounds()
            if backing != nil {
                view?.layer.cornerRadius = radius
                view?.clipsToBounds = clips
            }
            backing?.removeFromSuperview()
        }
    }

    let dimming = SheetDimming()

    func installDimming(in backdrop: UIView, surface: UIView) {
        dimming.install(in: backdrop, surface: surface, above: lowerEffect?.dimming)
    }

    private var page: Page?
    /// 多层 sheet 共用一个根页面变换，任何一层重新布局都不会覆盖另一层。
    @MainActor private final class RootStack {
        let page: Page
        let fractions = NSMapTable<SheetPresenterEffect, NSNumber>.weakToStrongObjects()
        init(_ view: UIView) { page = Page(view, blackBacking: true) }
        func render(in window: UIWindow) {
            let levels = fractions.objectEnumerator()?.allObjects.compactMap { ($0 as? NSNumber)?.doubleValue }.sorted(by: >) ?? []
            guard let t = levels.first else { page.restore(); return }
            // XR 上的触摸采样显示，宽度变化略领先手指，顶边位移略滞后。
            let ease = t * (1 - t) * (1 - 0.2 * t)
            let scale = max(0.01, 1 - 40 * (t + 0.38 * ease) / window.bounds.width)
            let top = window.safeAreaInsets.top * (t - 0.08 * ease) + 10 * (levels.dropFirst().first ?? 0)
            page.apply(scale: scale, offsetY: top - window.bounds.height * (1 - scale) / 2, cornerFraction: t)
        }
    }
    private static let roots = NSMapTable<UIWindow, RootStack>.weakToStrongObjects()
    private weak var rootWindow: UIWindow?
    private func updateRoot(_ t: CGFloat, in window: UIWindow) {
        guard let host = window.rootViewController?.view else { return }
        let stack = Self.roots.object(forKey: window) ?? RootStack(host)
        Self.roots.setObject(stack, forKey: window)
        rootWindow = window
        stack.fractions.setObject(NSNumber(value: Double(t)), forKey: self)
        stack.render(in: window)
    }
    private weak var presenter: UIViewController?
    private weak var lowerSurface: UIView?
    private var hasPresentedSheet = false
    private(set) var isLifted = false
    private enum Cover: Equatable {
        case topInWindow(CGFloat)
        case minimumDetent
    }
    private var cover: Cover?
    private weak var lowerEffect: SheetPresenterEffect?
    private var layoutLower: (() -> Void)?

    private func setLower(lifted: Bool, cover: Cover? = nil) {
        guard let lowerEffect, lowerEffect.isLifted != lifted || lowerEffect.cover != cover else { return }
        lowerEffect.isLifted = lifted
        lowerEffect.cover = cover
        layoutLower?()
    }

    /// 较矮的前页限制下层的布局高度，文本与圆角仍以原比例显示。
    func frameWhenCovered(_ frame: CGRect, minimumTop: @autoclosure () -> CGFloat, in container: UIView) -> CGRect {
        guard let cover, let window = container.window else { return frame }
        let top: CGFloat
        switch cover {
        case .minimumDetent: top = minimumTop()
        case .topInWindow(let y): top = min(minimumTop(), container.convert(CGPoint(x: 0, y: y), from: window).y)
        }
        let inset = min(frame.height, max(0, top - frame.minY))
        return CGRect(x: frame.minX, y: frame.minY + inset, width: frame.width, height: frame.height - inset)
    }

    private var lowerIsLarge: (() -> Bool)?

    func configure(presenter: UIViewController) {
        hasPresentedSheet = false
        lowerEffect = nil
        layoutLower = nil
        lowerSurface = nil
        lowerIsLarge = nil
        self.presenter = presenter
        var ancestor: UIViewController? = presenter
        while let controller = ancestor {
            if let panel = controller as? AdaptivePanelController {
                panel.presenterEffect.hasPresentedSheet = true
                panel.invalidateDetents()
                lowerSurface = panel.surface
                lowerIsLarge = { [weak panel] in panel?.isAtMaximumDetent == true }
                lowerEffect = panel.presenterEffect
                layoutLower = { [weak panel] in
                    panel?.invalidateDetents()
                    panel?.viewIfLoaded?.layoutIfNeeded()
                }
                return
            }
            if let sheet = controller.customSheetPresentationController {
                sheet.presenterEffect.hasPresentedSheet = true
                sheet.invalidateDetents()
                lowerSurface = sheet.presentedView
                lowerIsLarge = { [weak sheet] in sheet?.isAtMaximumDetent == true }
                lowerEffect = sheet.presenterEffect
                layoutLower = { [weak sheet] in
                    sheet?.invalidateDetents()
                    sheet?.containerView?.layoutIfNeeded()
                }
                return
            }
            if let sheet = controller.sheetPresentationController, controller.presentingViewController != nil {
                lowerSurface = sheet.presentedView
                lowerIsLarge = { [weak sheet] in
                    guard let sheet else { return false }
                    if let selected = sheet.selectedDetentIdentifier { return selected == .large }
                    if #available(iOS 16, *) { return sheet.detents.first?.identifier == .large }
                    return false
                }
                return
            }
            ancestor = controller.parent
        }
    }

    /// 内嵌面板仅在覆盖整个页面时才使用独立于后页的坐标系。
    func panelContainer(for host: UIView) -> UIView {
        if let lowerSurface, let parent = lowerSurface.superview { return parent }
        if #unavailable(iOS 26), let window = host.window, host === window.rootViewController?.view,
           let parent = host.superview, host.convert(host.bounds, to: window).equalTo(window.bounds) { return parent }
        return host
    }

    /// 全屏 iPad 的页首次被另一张页覆盖后，其两侧边距各减少 4 pt，返回时沿用该宽度。
    func readablePageWidth(_ width: CGFloat, available: CGFloat, in container: UIView) -> CGFloat {
        if #available(iOS 26, *), container.traitCollection.userInterfaceIdiom == .pad,
           hasPresentedSheet, width < available, !SheetRegionGeometry.isWindowedPad(container) {
            return max(1, width - 8)
        }
        return width
    }

    func additionalTop(in container: UIView, foldedPage: Bool) -> CGFloat {
        guard #available(iOS 26, *), let lowerSurface else { return 0 }
        if container.traitCollection.verticalSizeClass == .compact {
            return foldedPage && lowerIsLarge?() == true ? 8 : 0
        }
        if container.traitCollection.userInterfaceIdiom == .pad {
            return lowerIsLarge?() == true && lowerSurface.bounds.width < container.bounds.width - 1 ? 20 : 0
        }
        if #available(iOS 27, *), lowerIsLarge?() != true { return 0 }
        return container.traitCollection.horizontalSizeClass == .regular ? 20 : 10
    }

    func update(_ fraction: CGFloat, in container: UIView, frontFrame: CGRect, attachment: SheetRegionGeometry.PageAttachment?, interacting: Bool) {
        let t = min(1, max(0, fraction))
        guard let window = container.window, let host = window.rootViewController?.view,
              presenter != nil, container.traitCollection.verticalSizeClass != .compact || attachment != nil,
              container.convert(container.bounds, to: window).equalTo(window.bounds) else { restore(); return }
        let legacy: Bool
        if #available(iOS 26, *) { legacy = false } else { legacy = true }
        let legacyPage = legacy && container.traitCollection.horizontalSizeClass == .compact
        let lowerLarge = lowerIsLarge?() == true
        guard let target = lowerSurface ?? (legacyPage ? host : nil),
              !container.isDescendant(of: target), let parent = target.superview else { restore(); return }
        if target === host {
            if legacyPage && t > 0 { updateRoot(t, in: window) } else { restore() }
            return
        }
        let bounds = target.bounds
        guard bounds.width > 0, bounds.height > 0 else { restore(); return }
        // 使用未受自身缩放影响的 center/bounds，避免下次布局把已经缩小的尺寸作为输入。
        let natural = CGRect(x: target.center.x - bounds.width / 2, y: target.center.y - bounds.height / 2,
                             width: bounds.width, height: bounds.height)
        let base = parent.convert(natural, to: window)
        let front = container.convert(frontFrame, to: window)
        guard abs(front.midX - base.midX) <= 1 else { restore(); return }
        if let attachment, !lowerLarge, lowerEffect != nil {
            // 在两个浮起档位间，下层随前页顶边重新布局；从浮起过渡到贴底时，UIKit
            // 临时使用下层最矮的有效档位，贴底后恢复调用方所选的档位。
            let betweenAttachments = frontFrame.minY < attachment.floatingTop && frontFrame.minY > attachment.attachedTop
            page?.restore()
            page = nil
            setLower(lifted: false, cover: interacting && betweenAttachments ? .minimumDetent : .topInWindow(front.minY))
            return
        }
        // 系统将非最大档下层页的可见高度限制在前页以内，较矮的前页会盖住它的顶边。
        if !lowerLarge, abs(front.maxY - base.maxY) <= 1, front.minY > base.minY {
            setLower(lifted: false)
            if rootWindow != nil { restore() }
            let heightRatio = min(1, front.height / base.height)
            if page?.view !== target { page?.restore(); page = Page(target, blackBacking: false) }
            page?.apply(scale: 1, scaleY: heightRatio, offsetY: bounds.height * (1 - heightRatio) / 2, cornerFraction: nil)
            return
        }
        guard t > 0, legacyPage || lowerLarge else { restore(); return }
        if legacyPage { updateRoot(t, in: window) }
        if !legacy, container.traitCollection.userInterfaceIdiom == .pad, base.width < window.bounds.width - 1 {
            restore()
            return
        }
        let inset: CGFloat = legacyPage || container.traitCollection.userInterfaceIdiom == .pad ? 20 : 16
        let ease = t * (1 - t) * (1 - 0.2 * t)
        let shrink = t + 0.38 * ease
        let shift = legacyPage ? t - 0.08 * ease : t
        let scale = max(0.01, 1 - 2 * inset * shrink / base.width)
        let finalTop: CGFloat
        if legacyPage {
            finalTop = lowerLarge ? window.safeAreaInsets.top : window.safeAreaInsets.top + base.minY * (1 - 2 * inset / base.width)
        } else { finalTop = base.minY - (container.traitCollection.userInterfaceIdiom == .pad ? 20 : 0) }
        setLower(lifted: attachment != nil)
        // 前页匀速经过叠层顶距，后页缩放略领先；两者的进度差产生短暂的向上位移。
        let lift = (attachment?.stackedTopGap ?? 0) * (shrink - t)
        if page?.view !== target { page?.restore(); page = Page(target, blackBacking: false) }
        page?.apply(scale: scale, offsetY: (finalTop - base.minY) * shift - lift - bounds.height * (1 - scale) / 2,
                    cornerFraction: nil)
    }

    func reset() {
        dimming.remove()
        hasPresentedSheet = false
        restore()
        lowerEffect = nil
        layoutLower = nil
        lowerSurface = nil
        lowerIsLarge = nil
        presenter = nil
    }

    func restore() {
        setLower(lifted: false)
        page?.restore()
        page = nil
        if let window = rootWindow, let stack = Self.roots.object(forKey: window) {
            stack.fractions.removeObject(forKey: self)
            stack.render(in: window)
            if stack.fractions.count == 0 { Self.roots.removeObject(forKey: window) }
        }
        rootWindow = nil
    }
}
