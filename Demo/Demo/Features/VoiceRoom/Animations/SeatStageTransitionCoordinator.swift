//
//  SeatStageTransitionCoordinator.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import OSLog
import UIKit

/// 协调麦位 CollectionView、舞台高度和公屏位置的场景级动画。
///
/// 麦位自身的增删、移动、缩放和内容淡变由 `SeatStageView` 的真实 Cell
/// 完成；Coordinator 只保留跨视图时间线，不再创建逐麦快照或 Overlay。
@MainActor
final class SeatStageTransitionCoordinator {

    /// 记录当前组件诊断信息的日志记录器。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "VoiceRoomSeatTransition"
    )

    /// 常规舞台转场的持续时间，单位为秒。
    private static let standardDuration: TimeInterval = 0.35
    /// 减少动态效果时淡入转场的持续时间，单位为秒。
    private static let reducedMotionDuration: TimeInterval = 0.15

    /// 参与场景转场的麦位舞台；由页面持有。
    private weak var stageView: SeatStageView?
    /// 房间公屏视图。
    private weak var messagesView: RoomPublicChatView?
    /// 查询当前是否启用减少动态效果的闭包。
    private let isReduceMotionEnabled: () -> Bool

    /// 当前运行的属性动画器；没有动画时为 `nil`。
    private var animator: UIViewPropertyAnimator?
    /// 使先前异步完成回调失效的递增代次。
    private var generation = 0
    /// 转场完成或立即结束时用于恢复最终布局的闭包。
    private var finalLayout: (() -> Void)?
    /// 一个布尔值，指示当前转场是否使用减少动态效果路径。
    private var usesReducedMotionTransition = false

    /// 一个布尔值，指示场景转场是否尚未结束。
    private(set) var isTransitioning = false

    /// 创建同步麦位舞台与公屏的转场协调器。
    ///
    /// - Parameters:
    ///   - stageView: 提供真实麦位单元格及舞台布局的视图。
    ///   - messagesView: 随舞台高度变化同步移动的公屏。
    ///   - isReduceMotionEnabled: 减少动态效果查询；为 `nil` 时读取系统设置。
    init(
        stageView: SeatStageView,
        messagesView: RoomPublicChatView,
        isReduceMotionEnabled: (() -> Bool)? = nil
    ) {
        self.stageView = stageView
        self.messagesView = messagesView
        self.isReduceMotionEnabled = isReduceMotionEnabled ?? {
            UIAccessibility.isReduceMotionEnabled
        }
    }

    /// 将舞台更新到指定状态，并同步公屏位置和外层布局。
    ///
    /// 转场期间传入非动画更新时只合并内容；再次请求几何转场时立即结束旧动画并提交最新舞台。
    ///
    /// - Parameters:
    ///   - presentation: 已经过校验的目标舞台数据。
    ///   - animated: 是否请求几何转场；窗口不可见或系统关闭动画时直接提交。
    ///   - rootView: 场景坐标转换和布局测量使用的根视图。
    ///   - applyFinalLayout: 将外层布局更新到目标状态的闭包；一次转场中可能调用多次。
    func transition(
        to presentation: SeatStagePresentation,
        animated: Bool,
        in rootView: UIView,
        applyFinalLayout: @escaping () -> Void
    ) {
        guard let stageView, let messagesView else { return }

        if isTransitioning {
            if !animated {
                stageView.applyDataUpdate(presentation: presentation)
                return
            }

            // 几何切换期间只提交最新合法 revision，不续播第二段方向相反的动画。
            // 取舍掉半帧 Hero 续接，可以避免 Cell 内部内容与 Layout Frame 分别冻结
            // 造成的视觉锚点断层，也不会积累过期房型的临时内容层。
            finishImmediately()
            UIView.performWithoutAnimation {
                stageView.apply(presentation: presentation)
                applyFinalLayout()
                rootView.layoutIfNeeded()
            }
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

        rootView.layoutIfNeeded()
        let sourceStageFrame = visualFrame(of: stageView, in: rootView)
        let sourceMessagesFrame = visualFrame(of: messagesView, in: rootView)

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
        // 起点必须读取 presentation layer，终点必须读取刚完成布局后的 model layer。
        // 若终点继续读取 presentation，Core Animation 是否已经提交当前事务会让同一
        // 次玩法切换偶发拿到旧 Frame，表现为麦位和公屏向相反方向移动或末尾跳变。
        let finalStageFrame = modelFrame(of: stageView, in: rootView)
        let finalMessagesFrame = modelFrame(of: messagesView, in: rootView)
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
        for userID: RoomUserID,
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

    /// 提交目标舞台后淡入舞台和公屏，在过渡期间关闭麦位交互。
    private func performReducedMotionTransition(
        to presentation: SeatStagePresentation,
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

    /// 结束舞台转场、恢复交互，并执行最终布局回调。
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

    /// 返回视图当前可见的矩形，优先读取表示层并转换到根视图坐标。
    private func visualFrame(of view: UIView, in rootView: UIView) -> CGRect {
        let sourceLayer = view.layer.presentation() ?? view.layer
        let rootLayer = rootView.layer.presentation() ?? rootView.layer
        return sourceLayer.convert(sourceLayer.bounds, to: rootLayer)
    }

    /// 返回视图模型层中的最终布局矩形，使用根视图坐标。
    private func modelFrame(of view: UIView, in rootView: UIView) -> CGRect {
        view.layer.convert(view.layer.bounds, to: rootView.layer)
    }

    /// 将根视图坐标中的矩形转换到目标视图的父视图坐标后设置位置。
    private func setFrame(
        _ frame: CGRect,
        for view: UIView,
        in rootView: UIView
    ) {
        guard let superview = view.superview else { return }
        view.frame = rootView.convert(frame, to: superview)
    }

#if DEBUG
    /// 供调试和测试检查的当前转场动画器。
    var testingAnimator: UIViewPropertyAnimator? { animator }

    /// 供测试检查的当前参与转场的用户标识集合。
    var testingActiveUserIDs: Set<RoomUserID> {
        stageView?.transitioningUserIDs ?? []
    }

    /// 供测试检查的减少动态效果转场状态。
    var testingUsesReducedMotionTransition: Bool {
        usesReducedMotionTransition
    }
#endif
}
