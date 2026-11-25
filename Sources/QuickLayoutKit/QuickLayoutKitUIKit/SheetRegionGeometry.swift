import UIKit

@MainActor
protocol SheetMediumDetentGeometry {
    var availableRegion: CGRect { get }
    var divisionRegions: [CGRect] { get }
    var minimumMediumHeight: CGFloat { get }
}

enum SheetRegionGeometry {
    @MainActor
    static func resolvedMediumHeight(maximum: CGFloat, traits: UITraitCollection, geometry: (any SheetMediumDetentGeometry)?) -> CGFloat? {
        guard traits.verticalSizeClass != .compact else { return nil }
        if #available(iOS 18, *) {
            guard let geometry else { return maximum * 0.56 }
            let height = mediumHeight(maximum: maximum, region: geometry.availableRegion, divisions: geometry.divisionRegions)
            return min(maximum, max(geometry.minimumMediumHeight, height))
        }
        return maximum * 0.5
    }

    static let defaultPageInset: CGFloat = {
        if #available(iOS 26, *) { return 8 }
        return 0
    }()

    static func formCenterY(in region: CGRect, bounds: CGRect, height: CGFloat, preferredY: CGFloat) -> CGFloat {
        let upperLimit = max(region.minY, bounds.minY + 8) + 10
        let lowerLimit = region.maxY - 10
        return min(lowerLimit - height / 2, max(upperLimit + height / 2, preferredY))
    }

    @MainActor
    static func isWindowedPad(_ view: UIView) -> Bool {
        guard #available(iOS 26, *), view.traitCollection.userInterfaceIdiom == .pad,
              let scene = view.window?.windowScene else { return false }
        let size = scene.coordinateSpace.bounds.size
        let screen = scene.screen.coordinateSpace.bounds.size
        return size.width < screen.width - 1 || size.height < screen.height - 1
    }

    static func pageFrame(x: CGFloat, bottom: CGFloat, width: CGFloat, height: CGFloat,
                          maximum: CGFloat, highestFloatingHeight: CGFloat, safeBottom: CGFloat,
                          sideGap: CGFloat, bottomGap: CGFloat, floatingPage: Bool, compactHeight: Bool) -> CGRect {
        let fraction = min(1, max(0, (maximum - height) / max(1, maximum - highestFloatingHeight)))
        let inset = min(max(0, sideGap), width / 4) * fraction
        let includedBottom = compactHeight && height < 100 ? 0 : safeBottom
        let displayWidth = width - 2 * inset
        let displayHeight = (height + includedBottom) * displayWidth / max(1, width)
        var lift = floatingPage ? bottomGap * fraction : 0
        if #available(iOS 27, *), compactHeight { lift = bottomGap * fraction + safeBottom - includedBottom }
        return CGRect(x: x + inset, y: bottom - lift - displayHeight, width: displayWidth, height: displayHeight)
    }

    /// 折叠手机的页式卡片会在到达最高档之前贴底。用面板顶边位置同步底部间距与圆角。
    struct PageAttachment {
        let bottom: CGFloat
        let gap: CGFloat
        let floatingTop: CGFloat
        let largestTop: CGFloat
        let attachedTop: CGFloat
        let stackedTopGap: CGFloat

        init(bottom: CGFloat, gap: CGFloat, safeBottom: CGFloat, maximum: CGFloat, floatingHeight: CGFloat, folded: Bool, stackedTopGap: CGFloat) {
            self.bottom = bottom
            self.gap = gap
            self.stackedTopGap = stackedTopGap
            floatingTop = bottom - safeBottom - floatingHeight - gap
            largestTop = bottom - safeBottom - maximum
            attachedTop = stackedTopGap > 0 ? largestTop : largestTop + (folded ? 10 : 20)
        }

        func fraction(at top: CGFloat) -> CGFloat {
            min(1, max(0, (top - attachedTop) / max(1, floatingTop - attachedTop)))
        }

        func adjusting(_ frame: CGRect) -> CGRect {
            // 小于浮起档位的自定义高度保留自身布局，包括紧凑高度下的底部安全区。
            guard frame.minY < floatingTop else { return frame }
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                   height: max(0, bottom - gap * fraction(at: frame.minY) - frame.minY))
        }
    }

    @MainActor
    static func updateCorners(of surface: UIView, relativeTo backdrop: UIView, frame: CGRect,
                              preferredRadius: CGFloat?, fullScreen: Bool, logicalWidth: CGFloat, attachment: PageAttachment? = nil, isLifted: Bool = false) {
        let bounds = backdrop.bounds
        let lift = max(0, bounds.maxY - frame.maxY)
        let attached = lift < 0.5 / max(1, backdrop.traitCollection.displayScale)
        if #available(iOS 26, *) {
            let wide = backdrop.traitCollection.horizontalSizeClass == .regular
            let scale = logicalWidth > 0 ? min(1, frame.width / logicalWidth) : 1
            // 只在靠近显示器对应角时使用同心半径。折叠外屏的窄角可以小于 40 pt。
            func pageRadius(_ corner: UIRectCorner, distance: CGFloat) -> CGFloat {
                let displayRadius = backdrop.effectiveRadius(corner: corner)
                return distance <= max(8, displayRadius) ? max(8, displayRadius - distance) : 40
            }
            func top(_ corner: UIRectCorner, sideGap: CGFloat) -> UICornerRadius {
                if fullScreen { return .fixed(0) }
                let base: CGFloat = attachment != nil || wide ? 40 : 38
                guard let attachment, preferredRadius == nil else { return .fixed(max(0, preferredRadius ?? base) * scale) }
                let travel = attachment.floatingTop - attachment.largestTop
                let t = travel > 0 ? min(1, max(0, (attachment.floatingTop - frame.minY) / travel))
                    : (frame.minY <= attachment.largestTop + 0.5 ? 1.0 : 0.0)
                // 叠层的顶边在收起时还包含卡片的浮动间距，用当帧的间距求同心圆角。
                let topDistance = attachment.largestTop - bounds.minY - min(attachment.gap, attachment.stackedTopGap) * (1 - t)
                let radius = backdrop.effectiveRadius(corner: corner)
                let originalDistance = max(attachment.largestTop - bounds.minY - attachment.stackedTopGap, sideGap)
                let expanded: CGFloat = originalDistance <= max(8, radius) ? max(8, radius - max(topDistance, sideGap)) : 40
                return .fixed((base + (expanded - base) * t) * scale)
            }
            func bottom(_ corner: UIRectCorner, sideGap: CGFloat) -> UICornerRadius {
                let lifted = isLifted && attachment != nil
                let progress = lifted ? 1 : attachment?.fraction(at: frame.minY) ?? 1
                let touchesBottom = !lifted && (attachment.map { $0.gap == 0 || progress == 0 } ?? attached)
                if fullScreen || touchesBottom { return .fixed(0) }
                if let preferredRadius { return .fixed(max(0, preferredRadius) * scale * progress) }
                if let attachment {
                    return .fixed(pageRadius(corner, distance: max(attachment.gap, sideGap)) * scale * progress)
                }
                let minimum: CGFloat = wide ? 40 : 24
                if #unavailable(iOS 27) { return .containerConcentric(minimum: minimum * scale) }
                // UIKit 27 的整页缩放同时作用于每个角。左右分别参考宿主对应的底角。
                let radius = backdrop.effectiveRadius(corner: corner) - max(lift, sideGap)
                return .fixed(max(minimum, radius) * scale)
            }
            let corners = UICornerConfiguration.corners(
                topLeftRadius: top(.topLeft, sideGap: frame.minX - bounds.minX),
                topRightRadius: top(.topRight, sideGap: bounds.maxX - frame.maxX),
                bottomLeftRadius: bottom(.bottomLeft, sideGap: frame.minX - bounds.minX),
                bottomRightRadius: bottom(.bottomRight, sideGap: bounds.maxX - frame.maxX))
            if surface.cornerConfiguration != corners { surface.cornerConfiguration = corners }
        } else {
            surface.layer.cornerRadius = fullScreen ? 0 : max(0, preferredRadius ?? 10)
            surface.layer.maskedCorners = attached ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }

    static func mediumHeight(maximum: CGFloat, region: CGRect, divisions: [CGRect]) -> CGFloat {
        var height = maximum * 0.56
        for division in divisions where division.width > division.height
            && division.minX <= region.minX + 1 && division.maxX >= region.maxX - 1
            && division.maxY > region.minY && division.maxY < region.maxY {
            height = min(height, region.maxY - division.maxY)
        }
        return height
    }

    /// 仅使用贯穿宿主可见区域的分隔带切分空间，坐标统一为宿主坐标。
    static func regions(in bounds: CGRect, divisions: [CGRect]) -> [CGRect] {
        var regions = [bounds]
        for division in divisions {
            regions = regions.flatMap { region -> [CGRect] in
                let intersection = region.intersection(division)
                guard !intersection.isNull, intersection.width >= 0, intersection.height >= 0,
                      intersection.width > 0 || intersection.height > 0 else { return [region] }
                if division.height > division.width,
                   division.minY <= region.minY + 1, division.maxY >= region.maxY - 1 {
                    return [CGRect(x: region.minX, y: region.minY, width: intersection.minX - region.minX, height: region.height),
                            CGRect(x: intersection.maxX, y: region.minY, width: region.maxX - intersection.maxX, height: region.height)]
                        .filter { $0.width > 0 }
                }
                if division.width > division.height,
                   division.minX <= region.minX + 1, division.maxX >= region.maxX - 1 {
                    return [CGRect(x: region.minX, y: region.minY, width: region.width, height: intersection.minY - region.minY),
                            CGRect(x: region.minX, y: intersection.maxY, width: region.width, height: region.maxY - intersection.maxY)]
                        .filter { $0.height > 0 }
                }
                return [region]
            }
        }
        return regions
    }
}
