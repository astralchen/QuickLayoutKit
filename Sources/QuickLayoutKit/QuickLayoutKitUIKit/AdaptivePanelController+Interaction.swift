import UIKit

extension AdaptivePanelController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === pan else { return true }
        gestureScrollView = nil
        var touched = touch.view
        while let view = touched, view !== surface {
            // 输入控件保留自己的选择、滑块和长按手势；把手始终可以拖动。
            if view is UIControl || view is UITextView { return false }
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               scroll.alwaysBounceVertical || scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height {
                gestureScrollView = scroll
                break
            }
            touched = view.superview
        }
        if let trackingScrollView, let touched = touch.view,
           touched === trackingScrollView || touched.isDescendant(of: trackingScrollView) {
            gestureScrollView = trackingScrollView
        }
        return true
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return true }
        let velocity = pan.velocity(in: layoutContainer)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        if let scroll = gestureScrollView, !prefersScrollingExpandsWhenScrolledToEdge {
            return velocity.y > 0 && scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && otherGestureRecognizer === gestureScrollView?.panGestureRecognizer
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard !isDismissing else { return }
        let translation = recognizer.translation(in: layoutContainer).y
        switch recognizer.state {
        case .began:
            gestureStartIdentifier = selectedDetentIdentifier
            previousTranslation = translation
            draggingPanel = gestureScrollView == nil
            scrollStartOffset = gestureScrollView?.contentOffset.y ?? 0
            if draggingPanel {
                let curve = SheetOverdrag(offset: finishRebound(at: .current))
                overdrag = curve
                overdragDistance = curve.distance
                overdragOffset = max(0, curve.offset(for: curve.distance))
                if overdragDistance != 0 { interactiveHeight = currentHeight }
            } else {
                finishRebound(at: .end)
            }
        case .changed:
            let delta = translation - previousTranslation
            previousTranslation = translation
            let maximum = resolvedDetents.last?.height ?? currentHeight
            if let scroll = gestureScrollView {
                let top = -scroll.adjustedContentInset.top
                let atTop = scroll.contentOffset.y <= top + 1
                if !draggingPanel {
                    let expands = delta < 0 && currentHeight < maximum - 1 && prefersScrollingExpandsWhenScrolledToEdge
                    let collapses = delta > 0 && atTop
                    guard expands || collapses else { return }
                    draggingPanel = true
                    scrollStartOffset = expands ? max(top, scrollStartOffset) : top
                }
                // 到达最高档后向上拖动，滚动视图继续接管同一次手势。
                if currentHeight >= maximum - 0.5 && delta < 0 {
                    draggingPanel = false
                    interactiveHeight = maximum
                    return
                }
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: scrollStartOffset), animated: false)
            }
            let minimum = resolvedDetents.first?.height ?? 1
            let lowerBound: CGFloat = allowsInteractiveDismissal ? 1 : minimum
            let proposedHeight = currentHeight + overdragDistance - delta
            if let overdrag {
                overdragDistance = max(0, proposedHeight - maximum)
                overdragOffset = overdrag.offset(for: overdragDistance)
            }
            interactiveHeight = min(maximum, max(lowerBound, proposedHeight))
            invalidateDetents()
            view.layoutIfNeeded()
            if overdragOffset == 0 { overdragDistance = 0 }
        case .ended:
            guard interactiveHeight != nil else { clearGesture(); return }
            let velocity = recognizer.velocity(in: layoutContainer).y
            let minimum = resolvedDetents.first?.height ?? currentHeight
            let projected = currentHeight - velocity * 0.18
            if overdragOffset > 0, let largest = resolvedDetents.last {
                let selected = resolvedDetents.first { $0.identifier == selectedDetentIdentifier && $0.height == largest.height }
                settle(to: selected?.identifier ?? largest.identifier, reason: .interaction, reboundVelocity: velocity)
            } else if currentHeight < minimum * 0.7 || (currentHeight < minimum && velocity > 700) {
                attemptDismiss()
            } else {
                let nearest = resolvedDetents.min { abs($0.height - projected) < abs($1.height - projected) }
                settle(to: nearest?.identifier, reason: .interaction)
            }
            clearGesture()
        case .cancelled, .failed:
            if interactiveHeight != nil {
                let largest = resolvedDetents.last?.height
                let startsAtLargest = resolvedDetents.first { $0.identifier == gestureStartIdentifier }?.height == largest
                settle(to: gestureStartIdentifier, reason: .interaction, reboundVelocity: startsAtLargest ? 0 : nil)
            }
            clearGesture()
        default: break
        }
    }

    private func clearGesture() {
        draggingPanel = false
        gestureScrollView = nil
        gestureStartIdentifier = nil
        overdrag = nil
        overdragDistance = 0
    }

    func accessibilityAdjust(increase: Bool) {
        guard let index = resolvedDetents.firstIndex(where: { $0.identifier == selectedDetentIdentifier }) else { return }
        let target = increase ? index + 1 : index - 1
        if resolvedDetents.indices.contains(target) {
            settle(to: resolvedDetents[target].identifier, reason: .interaction)
        }
    }

}
