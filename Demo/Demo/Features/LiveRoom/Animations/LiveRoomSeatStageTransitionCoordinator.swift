//
//  LiveRoomSeatStageTransitionCoordinator.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import OSLog
import UIKit

/// 协调麦位 CollectionView、舞台高度和公屏位置的场景级动画。
///
/// 麦位自身的增删、移动、缩放和内容淡变由 `LiveRoomSeatStageView` 的真实 Cell
/// 完成；Coordinator 只保留跨视图时间线，不再创建逐麦快照或 Overlay。
@MainActor
final class LiveRoomSeatStageTransitionCoordinator {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "LiveRoomSeatTransition"
    )

    private static let standardDuration: TimeInterval = 0.35
    private static let reducedMotionDuration: TimeInterval = 0.15

    private weak var stageView: LiveRoomSeatStageView?
    private weak var messagesView: LiveRoomMessagesView?
    private let isReduceMotionEnabled: () -> Bool

    private var animator: UIViewPropertyAnimator?
    private var generation = 0
    private var finalLayout: (() -> Void)?
    private var usesReducedMotionTransition = false

    private(set) var isTransitioning = false

    init(
        stageView: LiveRoomSeatStageView,
        messagesView: LiveRoomMessagesView,
        isReduceMotionEnabled: (() -> Bool)? = nil
    ) {
        self.stageView = stageView
        self.messagesView = messagesView
        self.isReduceMotionEnabled = isReduceMotionEnabled ?? {
            UIAccessibility.isReduceMotionEnabled
        }
    }

    /// 将舞台更新到新的 Presentation，并在需要时同步推动公屏。
    func transition(
        to presentation: LiveRoomSeatStagePresentation,
        animated: Bool,
        in rootView: UIView,
        applyFinalLayout: @escaping () -> Void
    ) {
        guard let stageView, let messagesView else { return }

        if isTransitioning, !animated {
            stageView.applyDataUpdate(presentation: presentation)
            return
        }

        let canAnimate = animated
            && stageView.window != nil
            && rootView.window != nil
            && UIView.areAnimationsEnabled
        guard canAnimate else {
            finishImmediately()
            stageView.apply(presentation: presentation)
            applyFinalLayout()
            return
        }

        var sourceStageFrame: CGRect
        var sourceMessagesFrame: CGRect
        if isTransitioning {
            animator?.pauseAnimation()
            sourceStageFrame = visualFrame(of: stageView, in: rootView)
            sourceMessagesFrame = visualFrame(of: messagesView, in: rootView)
            stageView.freezeTransitionAtCurrentPresentation()
            generation &+= 1
            animator?.stopAnimation(true)
            animator = nil
            stageView.layer.removeAllAnimations()
            messagesView.layer.removeAllAnimations()
            setFrame(sourceStageFrame, for: stageView, in: rootView)
            setFrame(sourceMessagesFrame, for: messagesView, in: rootView)
            isTransitioning = false
            usesReducedMotionTransition = false
            finalLayout = nil
        } else {
            rootView.layoutIfNeeded()
            sourceStageFrame = visualFrame(of: stageView, in: rootView)
            sourceMessagesFrame = visualFrame(of: messagesView, in: rootView)
        }

        if isReduceMotionEnabled() {
            performReducedMotionTransition(
                to: presentation,
                rootView: rootView,
                applyFinalLayout: applyFinalLayout
            )
            return
        }

        guard stageView.prepareTransition(to: presentation) else {
            applyFinalLayout()
            return
        }

        UIView.performWithoutAnimation {
            applyFinalLayout()
            rootView.layoutIfNeeded()
        }
        let finalStageFrame = visualFrame(of: stageView, in: rootView)
        let finalMessagesFrame = visualFrame(of: messagesView, in: rootView)
        guard
            sourceStageFrame.width > 0,
            sourceStageFrame.height > 0,
            finalStageFrame.width > 0,
            finalStageFrame.height > 0
        else {
            stageView.finishTransitionImmediately()
            applyFinalLayout()
            return
        }

        setFrame(sourceStageFrame, for: stageView, in: rootView)
        setFrame(sourceMessagesFrame, for: messagesView, in: rootView)
        rootView.layoutIfNeeded()

        generation &+= 1
        let animationGeneration = generation
        isTransitioning = true
        usesReducedMotionTransition = false
        finalLayout = applyFinalLayout

        let animator = UIViewPropertyAnimator(
            duration: Self.standardDuration,
            curve: .easeInOut
        ) { [weak self, weak rootView] in
            guard let self, let rootView else { return }
            self.setFrame(finalStageFrame, for: stageView, in: rootView)
            self.setFrame(finalMessagesFrame, for: messagesView, in: rootView)
            stageView.animatePreparedTransition()
        }
        animator.addCompletion { [weak self] _ in
            guard
                let self,
                self.generation == animationGeneration
            else { return }
            self.completeTransition()
        }
        self.animator = animator
        animator.startAnimation()
    }

    /// 返回用户在当前 Collection Cell presentation layer 上的实时送礼锚点。
    func giftTargetPoint(
        for userID: LiveRoomUserID,
        in view: UIView
    ) -> CGPoint? {
        stageView?.giftTargetPoint(forUserID: userID, in: view)
    }

    /// 立即结束当前动画并恢复最终真实布局。
    func finishImmediately() {
        guard isTransitioning || animator != nil else { return }
        generation &+= 1
        animator?.stopAnimation(true)
        animator = nil
        stageView?.layer.removeAllAnimations()
        messagesView?.layer.removeAllAnimations()
        stageView?.alpha = 1
        messagesView?.alpha = 1
        stageView?.finishTransitionImmediately()
        stageView?.setSeatInteractionEnabled(true)
        isTransitioning = false
        usesReducedMotionTransition = false
        let layout = finalLayout
        finalLayout = nil
        layout?()
    }

    private func performReducedMotionTransition(
        to presentation: LiveRoomSeatStagePresentation,
        rootView: UIView,
        applyFinalLayout: @escaping () -> Void
    ) {
        guard let stageView, let messagesView else { return }
        stageView.alpha = 0
        messagesView.alpha = 0
        stageView.apply(presentation: presentation)
        UIView.performWithoutAnimation {
            applyFinalLayout()
            rootView.layoutIfNeeded()
        }
        stageView.setSeatInteractionEnabled(false)

        generation &+= 1
        let animationGeneration = generation
        isTransitioning = true
        usesReducedMotionTransition = true
        finalLayout = applyFinalLayout
        let animator = UIViewPropertyAnimator(
            duration: Self.reducedMotionDuration,
            curve: .easeInOut
        ) {
            stageView.alpha = 1
            messagesView.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            guard
                let self,
                self.generation == animationGeneration
            else { return }
            self.completeTransition()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func completeTransition() {
        animator = nil
        stageView?.alpha = 1
        messagesView?.alpha = 1
        stageView?.completePreparedTransition()
        stageView?.setSeatInteractionEnabled(true)
        isTransitioning = false
        usesReducedMotionTransition = false
        let layout = finalLayout
        finalLayout = nil
        layout?()
    }

    private func visualFrame(of view: UIView, in rootView: UIView) -> CGRect {
        let sourceLayer = view.layer.presentation() ?? view.layer
        let rootLayer = rootView.layer.presentation() ?? rootView.layer
        return sourceLayer.convert(sourceLayer.bounds, to: rootLayer)
    }

    private func setFrame(
        _ frame: CGRect,
        for view: UIView,
        in rootView: UIView
    ) {
        guard let superview = view.superview else { return }
        view.frame = rootView.convert(frame, to: superview)
    }

#if DEBUG
    var testingAnimator: UIViewPropertyAnimator? { animator }

    var testingActiveUserIDs: Set<LiveRoomUserID> {
        stageView?.transitioningUserIDs ?? []
    }

    var testingUsesReducedMotionTransition: Bool {
        usesReducedMotionTransition
    }
#endif
}
