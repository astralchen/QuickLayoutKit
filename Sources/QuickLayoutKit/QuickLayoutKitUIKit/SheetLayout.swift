import UIKit

@MainActor
struct SheetLayout {
    @MainActor struct Stop {
        let detent: SheetPresentationController.Detent
        var id: SheetPresentationController.Detent.Identifier { detent.identifier }
        let height: CGFloat
        let frame: CGRect
        var dimming: CGFloat = 1
    }

    let contentBottomInset: CGFloat
    let attachment: SheetRegionGeometry.PageAttachment?
    let logicalWidth: CGFloat
    let stops: [Stop]
    let selected: Stop
    let maximumHeight: CGFloat

    init(_ sheet: SheetPresentationController, in container: UIView) {
        let bounds = container.bounds
        var safe = container.safeAreaLayoutGuide.layoutFrame
        if let window = container.window {
            safe = bounds.intersection(container.convert(window.safeAreaLayoutGuide.layoutFrame, from: window))
        }
        let traits = container.traitCollection
        // iPad 窗口化后，页面顶部还要为窗口控件保留一行空间。
        let windowedPad = SheetRegionGeometry.isWindowedPad(container)
        if windowedPad {
            let top = min(44, safe.height)
            safe.origin.y += top
            safe.size.height -= top
        }
        let compactHeight = traits.verticalSizeClass == .compact
        let foldedPage = sheet.hingeClosed
        if foldedPage { safe.origin.x = bounds.minX; safe.size.width = bounds.width }
        let floating = !compactHeight && traits.horizontalSizeClass == .regular
        let preferred = sheet.presentedViewController.preferredContentSize
        let foldablePhone = sheet.hasHinge && traits.userInterfaceIdiom == .phone
        let requestsForm = floating && !sheet.prefersPageSizing && !foldedPage
        // 折叠手机上的表单缺少宽或高时，UIKit 使用页式几何。
        let form = requestsForm && (!foldablePhone || preferred.width > 0 && preferred.height > 0)
        let usesPageSizing = sheet.prefersPageSizing || requestsForm && !form
        let phonePage = foldedPage || floating && usesPageSizing && traits.userInterfaceIdiom == .phone
        // 表单及其页式回退都可放在 Duo 内屏的系统侧栏背后。
        if requestsForm { safe.origin.x = bounds.minX; safe.size.width = bounds.width }
        let source = sheet.sourceView.flatMap { view in
            view.window === container.window ? view.convert(view.bounds, to: container) : nil
        }
        let rtl = container.effectiveUserInterfaceLayoutDirection == .rightToLeft
        var divisions: [CGRect] = []
        var active: [CGRect] = []
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            divisions = container.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
            active = container.reservedRegions(kind: .division).map { $0.frame.inset(by: $0.margins) }
            // 桌面姿态的横向铰链影响中档高度，表单的可用区域仍覆盖整个窗口。
            if usesPageSizing || foldablePhone && form { active = active.filter { $0.height > $0.width } }
        }
        #endif
        let regions = SheetRegionGeometry.regions(in: safe, divisions: active)
        let preferLeft = (sheet.preferredPlacement != .trailing) != rtl
        let sourceRegion = source.flatMap { rect in regions.first { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) } }
        let region = (form && sheet.preferredPlacement != .automatic ? nil : sourceRegion)
            ?? regions.sorted {
                if $0.midY != $1.midY { return $0.midY > $1.midY }
                if sheet.preferredPlacement == .automatic && $0.width != $1.width { return $0.width > $1.width }
                return preferLeft ? $0.minX < $1.minX : $0.maxX > $1.maxX
            }.first ?? safe
        let fullscreen = compactHeight && !sheet.prefersEdgeAttachedInCompactHeight && !phonePage
        let readableWidth = container.readableContentGuide.layoutFrame.width
            + sheet.presentingViewController.view.layoutMargins.left + sheet.presentingViewController.view.layoutMargins.right
        let availableWidth = max(1, region.width)
        let readable = sheet.presenterEffect.readablePageWidth(readableWidth, available: availableWidth, in: container)
        let sideGap = min(max(0, sheet.horizontalInset), availableWidth / 4)
        let bottomGap = min(max(0, sheet.bottomInset), max(0, region.height))
        var width = availableWidth
        if phonePage {
            let target = foldedPage ? region.width - 2 * sideGap : min(readable, min(bounds.width, bounds.height) - 2 * sideGap)
            width = max(1, min(region.width - 2 * sideGap, target))
        } else if floating {
            let formWidth = preferred.width > 0 ? preferred.width : 580
            width = min(width, form ? formWidth : readable)
        } else if compactHeight && !fullscreen && !sheet.prefersPageSizing && sheet.widthFollowsPreferredContentSizeWhenEdgeAttached && preferred.width > 0 {
            width = min(width, preferred.width)
        }
        logicalWidth = fullscreen ? bounds.width : width
        let formMargin: CGFloat = traits.userInterfaceIdiom == .pad ? 25 : 8
        let margin: CGFloat = phonePage ? sideGap : form ? min(formMargin, (region.width - width) / 2) : 0
        let x: CGFloat
        if let source {
            x = min(region.maxX - margin - width, max(region.minX + margin, source.midX - width / 2))
        } else {
            switch sheet.preferredPlacement {
            case .automatic, .center: x = min(region.maxX - margin - width, max(region.minX + margin, (phonePage ? bounds.midX : region.midX) - width / 2))
            case .leading: x = rtl ? region.maxX - margin - width : region.minX + margin
            case .trailing: x = rtl ? region.minX + margin : region.maxX - margin - width
            }
        }

        var topGap: CGFloat = phonePage ? max(0, 8 - (safe.minY - bounds.minY)) : 0
        if #unavailable(iOS 26), traits.userInterfaceIdiom == .phone, !floating, !compactHeight {
            // 旧版普通手机的页式 sheet 在顶部安全区下再留 10 pt。
            topGap = 10
        }
        let stackedTopGap = form || fullscreen ? 0 : sheet.presenterEffect.additionalTop(in: container, foldedPage: foldedPage)
        topGap += stackedTopGap
        let usable = region.height - topGap
        // 浮动表单的首选内容高之外还保留内容边距，显隐 grabber 不改变该高度。
        let formHeight = (preferred.height > 0 ? preferred.height : 640) + 20
        var maximum = max(1, form ? min(formHeight, usable) : usable)
        if #available(iOS 26, *), compactHeight && !fullscreen {
            if #unavailable(iOS 27) { maximum = max(maximum, min(384, bounds.height)) }
        }
        maximumHeight = maximum
        let context = SheetDetentContext(availableRegion: region, divisionRegions: divisions,
            maximumDetentValue: maximum, containerTraitCollection: traits,
            minimumMediumHeight: windowedPad ? 266 : 0)
        let centerY = SheetRegionGeometry.formCenterY(in: region, bounds: bounds, height: maximum,
            preferredY: source?.midY ?? (regions.count == 1 || region.height == safe.height ? bounds.midY : region.midY))
        let fillsRegion = !compactHeight && !phonePage && (!floating || usesPageSizing && readable >= region.width)
        let safeBottom = (!floating || phonePage || fillsRegion) && abs(region.maxY - safe.maxY) < 1 ? bounds.maxY - safe.maxY : 0
        let bottom = (form ? centerY + maximum / 2 : region.maxY) + safeBottom
        let medium = SheetPresentationController.Detent.medium().resolvedValue(in: context) ?? maximum

        let heights = sheet.detents.compactMap { detent in detent.resolvedValue(in: context).map { (detent, $0) } }
        let lastFloatingHeight = heights.map(\.1).filter { $0 < maximum - 0.5 }.max() ?? medium
        let floatingHeight = compactHeight ? heights.map(\.1).filter { $0 < maximum }.max() ?? medium : medium
        let pageAttachment: SheetRegionGeometry.PageAttachment? = phonePage && sheet.hasHinge
            ? .init(bottom: bottom, gap: bottomGap, safeBottom: safeBottom, maximum: maximum,
                    floatingHeight: floatingHeight, folded: foldedPage, stackedTopGap: stackedTopGap) : nil
        attachment = pageAttachment

        func stop(_ detent: SheetPresentationController.Detent, height: CGFloat) -> Stop {
            let frame = SheetRegionGeometry.pageFrame(x: x, bottom: bottom, width: width, height: height,
                maximum: maximum, highestFloatingHeight: lastFloatingHeight, safeBottom: safeBottom, sideGap: fillsRegion ? sideGap : 0,
                bottomGap: bottomGap, floatingPage: phonePage || fillsRegion, compactHeight: compactHeight)
            return Stop(detent: detent, height: height, frame: fullscreen ? bounds : pageAttachment?.adjusting(frame) ?? frame)
        }

        var resolved = heights.map { stop($0.0, height: $0.1) }.sorted { $0.height < $1.height }
        if resolved.isEmpty { resolved = [stop(.large(), height: maximum)] }
        if let threshold = resolved.first(where: { $0.id == sheet.largestUndimmedDetentIdentifier }) {
            for i in resolved.indices where resolved[i].height <= threshold.height { resolved[i].dimming = 0 }
        }
        stops = resolved
        selected = resolved.first { $0.id == sheet.selectedDetentIdentifier } ?? resolved[0]
        contentBottomInset = compactHeight && selected.height < 100 ? 0 : safeBottom
    }

    func presenterFraction(at top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard let last = stops.last, abs(last.height - maximumHeight) < 0.5 else { return 0 }
        let start = stops.last(where: { $0.height < last.height - 0.5 })?.frame.minY ?? bottom
        return min(1, max(0, (start - top) / max(1, start - last.frame.minY)))
    }

    /// 手势可跨越多个档位，外框和背景在相邻两个档位之间连续插值。
    func sample(at top: CGFloat) -> (frame: CGRect, dimming: CGFloat) {
        guard let upper = stops.firstIndex(where: { $0.frame.minY <= top }) else {
            let largest = stops[stops.count - 1]
            return (largest.frame, largest.dimming)
        }
        let b = stops[upper]
        guard upper > 0 else { return (b.frame, b.dimming) }
        let a = stops[upper - 1]
        let t = (a.frame.minY - top) / max(1, a.frame.minY - b.frame.minY)
        func mix(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { lhs + (rhs - lhs) * t }
        let frame = CGRect(x: mix(a.frame.minX, b.frame.minX), y: top,
                           width: mix(a.frame.width, b.frame.width), height: mix(a.frame.height, b.frame.height))
        return (attachment?.adjusting(frame) ?? frame, mix(a.dimming, b.dimming))
    }
}
