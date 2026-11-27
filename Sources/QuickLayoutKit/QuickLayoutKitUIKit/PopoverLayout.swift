import UIKit

/// 外框使用呈现容器坐标，主体与内容区域使用背景视图的局部坐标。
struct PopoverLayout {
    let direction: UIPopoverArrowDirection
    let frame: CGRect
    let body: CGRect
    let content: CGRect
    let contentSafeArea: UIEdgeInsets
    let offset: CGFloat
    let anchor: CGRect

    init(anchor source: CGRect, keyboardTop: CGFloat?, region: CGRect, preferred: CGSize, directions: UIPopoverArrowDirection,
         overlap: Bool, hidesArrow: Bool, extendsContent: Bool, usesClassicPhonePlacement: Bool,
         layoutInsets: UIEdgeInsets, insets: UIEdgeInsets, arrowHeight: CGFloat, scale: CGFloat) {
        self.anchor = source
        var anchor = source
        if let keyboardTop {
            // 按来源的可见部分布局，完全遮住时停在键盘上缘；保留原始来源用于追踪移动。
            let top = min(source.minY, keyboardTop)
            anchor.origin.y = top
            anchor.size.height = min(source.maxY, keyboardTop) - top
        }
        let desired = CGSize(width: max(1, preferred.width + insets.left + insets.right),
                             height: max(1, preferred.height + insets.top + insets.bottom))
        let allowed: [UIPopoverArrowDirection] = [UIPopoverArrowDirection.down, .up, .left, .right].filter { directions.contains($0) }
        var ranksByVisibleArea = usesClassicPhonePlacement
        var centersOnSource = usesClassicPhonePlacement
        if #unavailable(iOS 26) {
            ranksByVisibleArea = overlap
            centersOnSource = true
        }
        var bestShift = CGFloat.infinity
        var leastOverlap = CGFloat.infinity
        var bestArea: CGFloat = -1
        var bestFrame = CGRect.zero
        var bestDirection = UIPopoverArrowDirection(rawValue: 0)
        // 按每一侧能容纳的主体面积选择方向。
        for side in allowed.isEmpty ? [UIPopoverArrowDirection(rawValue: 0)] : allowed {
            let vertical = side == .up || side == .down
            let limits = side.isEmpty ? region : region.inset(by: layoutInsets)
            let height = side.isEmpty ? 0 : min(arrowHeight, vertical ? limits.height : limits.width)
            var available = limits
            // 主轴从来源边缘量到远端边界。来源在侧栏内时，箭尖仍可伸入侧栏。
            var attachment: CGFloat = 0
            switch side {
            case .up: attachment = anchor.maxY; available.size.height = limits.maxY - attachment
            case .down: attachment = anchor.minY; available.size.height = attachment - limits.minY
            case .left: attachment = anchor.maxX; available.size.width = limits.maxX - attachment
            case .right: attachment = anchor.minX; available.size.width = attachment - limits.minX
            default: break
            }
            let target = CGSize(width: desired.width + (vertical ? 0 : height),
                                height: desired.height + (vertical ? height : 0))
            // 先检查源矩形外侧的有向距离。即使允许重叠，没有正向空间的一侧也不能成为候选。
            if !side.isEmpty && (vertical ? available.size.height : available.size.width) <= 0 { continue }
            // 左右箭头空间不足时可以退到源矩形中线；上下箭头压缩高度时仍贴着来源边缘。
            if !side.isEmpty && !vertical && available.width < target.width {
                available.size.width += abs(anchor.midX - attachment)
                attachment = anchor.midX
            }
            if overlap { available = limits }
            let w = max(0, min(available.width, target.width))
            let h = max(0, min(available.height, target.height))
            var area = max(0, w - (vertical ? 0 : height)) * max(0, h - (vertical ? height : 0))
            if ranksByVisibleArea, !side.isEmpty {
                // 经典布局先比较理想外框在布局区域内的面积，再移动胜出的外框。
                // 奇数点宽的来源向下取半宽，左右角的候选面积可能因此不同。
                var ideal = CGRect(origin: CGPoint(x: anchor.minX + floor(anchor.width / 2) - target.width / 2,
                                                   y: anchor.minY + floor(anchor.height / 2) - target.height / 2),
                                   size: target)
                switch side {
                case .up: ideal.origin.y = anchor.maxY
                case .down: ideal.origin.y = anchor.minY - target.height
                case .left: ideal.origin.x = anchor.maxX
                case .right: ideal.origin.x = anchor.minX - target.width
                default: break
                }
                let visible = ideal.intersection(limits)
                area = (visible.width * visible.height).rounded()
            }

            var x = anchor.midX - w / 2
            var y = anchor.midY - h / 2
            if !centersOnSource {
                if vertical { x = anchor.minX + floor(anchor.width / 2) - w / 2 }
                else if !side.isEmpty { y = anchor.minY + floor(anchor.height / 2) - h / 2 }
            } else if side == .down {
                // 经典浮层的底边保持在布局区域内，即使来源延伸到了底部留白。
                attachment = min(attachment, limits.maxY)
            }
            switch side {
            case .up: y = attachment
            case .down: y = attachment - h
            case .left: x = attachment
            case .right: x = attachment - w
            default: break
            }
            // 横轴滑动补偿箭头偏移。保留点坐标，避免像素取整改变并列方向的顺序。
            let clampX = vertical || side.isEmpty || overlap
            let clampY = !vertical || overlap
            let candidate = CGRect(x: clampX ? max(limits.minX, min(limits.maxX - w, x)) : x,
                                   y: clampY ? max(limits.minY, min(limits.maxY - h, y)) : y,
                                   width: w, height: h)
            // 同样能容纳主体时，优先避开来源，再按箭头所在边的长度比较横向偏移。
            let intersection = candidate.intersection(anchor)
            let covered = intersection.width * intersection.height
            let shift = vertical
                ? abs(candidate.minX - x) / max(1, w)
                : abs(candidate.minY - y) / max(1, h)
            guard area > bestArea || (area == bestArea &&
                (covered < leastOverlap || (covered == leastOverlap && shift < bestShift))) else { continue }
            bestFrame = candidate
            bestShift = shift
            bestArea = area
            leastOverlap = covered
            bestDirection = side
        }
        if bestArea < 0 {
            // 所有允许方向都无空间时，从来源原点摆放无箭头主体，再把外框移入可用区域。
            let w = min(desired.width, max(0, region.size.width))
            let h = min(desired.height, max(0, region.size.height))
            bestFrame = CGRect(x: max(region.minX, min(region.maxX - w, anchor.minX)),
                               y: max(region.minY, min(region.maxY - h, anchor.minY)),
                               width: w, height: h)
        }
        direction = hidesArrow ? [] : bestDirection
        let vertical = bestDirection == .up || bestDirection == .down
        let delta = vertical ? anchor.midX - bestFrame.midX : anchor.midY - bestFrame.midY
        // 横轴对齐显示像素。左右箭头压缩后也对齐起点，保留 UIKit 给出的分数宽度。
        if vertical || (!bestDirection.isEmpty && bestFrame.width < desired.width + arrowHeight) {
            bestFrame.origin.x = (bestFrame.minX * scale).rounded() / scale
        }
        if !vertical && bestArea >= 0 {
            bestFrame.origin.y = (bestFrame.minY * scale).rounded() / scale
        }
        frame = bestFrame
        offset = bestDirection.isEmpty ? 0 : delta
        var arrowInsets = UIEdgeInsets.zero
        switch direction {
        case .up: arrowInsets.top = min(arrowHeight, frame.height)
        case .down: arrowInsets.bottom = min(arrowHeight, frame.height)
        case .left: arrowInsets.left = min(arrowHeight, frame.width)
        case .right: arrowInsets.right = min(arrowHeight, frame.width)
        default: break
        }
        body = CGRect(origin: .zero, size: frame.size).inset(by: arrowInsets)
        contentSafeArea = extendsContent ? arrowInsets : .zero
        let container = extendsContent ? CGRect(origin: .zero, size: frame.size) : body
        content = CGRect(x: container.minX + insets.left, y: container.minY + insets.top,
                         width: max(0, container.width - insets.left - insets.right),
                         height: max(0, container.height - insets.top - insets.bottom))
    }
}
