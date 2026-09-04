//
//  IMessageChatBottomObstructionCoordinator.swift
//  Demo
//
//  Keeps the photo sheet and UIKit keyboard on one stable composer lift.
//

import QuickLayoutKit
import UIKit

@available(iOS 26.0, *)
@MainActor
final class IMessageChatBottomObstructionCoordinator {
    private final class DisplayLinkProxy {
        weak var owner: IMessageChatBottomObstructionCoordinator?

        @objc func tick() {
            owner?.refreshGeometry()
        }
    }

    private weak var hostView: UIView?
    private weak var pickerViewController: UIViewController?
    private let displayLinkProxy = DisplayLinkProxy()
    private var displayLink: CADisplayLink?
    private var keyboardContext: QuickLayoutKeyboardContext?
    private var pickerLiftHeight: CGFloat?
    private var keyboardHandoffTargetHeight: CGFloat?
    private var isAwaitingKeyboard = false
    private(set) var currentHeight: CGFloat = 0
    private(set) var storedKeyboardContentHeight: CGFloat = 300

    var heightDidChange: ((CGFloat, QuickLayoutKeyboardContext?) -> Void)?

    init(hostView: UIView) {
        self.hostView = hostView
        displayLinkProxy.owner = self
    }

    /// 更新键盘状态，并返回该事件是否可以驱动 Composer 与列表布局。
    ///
    /// 照片 Sheet 展示且尚未开始切回键盘时仍缓存稳定键盘高度，但返回 `false`，
    /// 调用方不得据此滚动列表或更新输入栏位置。
    @discardableResult
    func updateKeyboard(_ context: QuickLayoutKeyboardContext) -> Bool {
        let wasKeyboardVisible = keyboardContext?.isVisible == true
        keyboardContext = context
        if context.isVisible {
            if let hostView {
                let targetHeight = targetKeyboardContentHeight(
                    for: context,
                    in: hostView
                )
                if isAwaitingKeyboard {
                    keyboardHandoffTargetHeight = targetHeight
                }
                if targetHeight > 0,
                   context.event == .willShow || !wasKeyboardVisible {
                    storedKeyboardContentHeight = max(220, targetHeight)
                }
            }
        }

        let shouldTrackKeyboardGeometry = Self.shouldTrackKeyboardGeometry(
            isPickerPresented: pickerViewController != nil,
            isAwaitingKeyboard: isAwaitingKeyboard,
            keyboardIsVisible: context.isVisible
        )
        if shouldTrackKeyboardGeometry {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }

        // 照片 Sheet 展示期间由打开时锁定的 pickerLiftHeight 独占 Composer
        // 位置。键盘通知仍可更新下一次使用的稳定高度，但不能触发布局；只有用户
        // 明确从照片切回键盘、beginKeyboardHandoff() 生效后，键盘才重新接管。
        let shouldApplyKeyboardLayout = Self.shouldApplyKeyboardLayout(
            isPickerPresented: pickerViewController != nil,
            isAwaitingKeyboard: isAwaitingKeyboard
        )
        guard shouldApplyKeyboardLayout else { return false }
        refreshGeometry(animationContext: context)
        return true
    }

    func trackPicker(_ picker: UIViewController) {
        pickerViewController = picker
        pickerLiftHeight = max(220, storedKeyboardContentHeight)
        keyboardHandoffTargetHeight = nil
        isAwaitingKeyboard = false
        stopDisplayLink()
        refreshGeometry(animationContext: keyboardContext ?? .hidden)
    }

    /// 照片 Sheet 关闭前冻结当前遮挡，直到 keyboard layout guide 接管。
    func beginKeyboardHandoff() {
        isAwaitingKeyboard = true
        keyboardHandoffTargetHeight = nil
        startDisplayLink()
    }

    func stopTrackingPicker() {
        pickerViewController = nil
        pickerLiftHeight = nil
        if isAwaitingKeyboard && keyboardContext?.isVisible != true {
            // 外接键盘不会产生可见的软件键盘。此时 Sheet 消失后没有新的
            // 遮挡源，必须解除交接冻结，避免输入栏停在旧 Sheet 顶部。
            isAwaitingKeyboard = false
            keyboardHandoffTargetHeight = nil
        }
        if keyboardContext?.isVisible != true && !isAwaitingKeyboard {
            stopDisplayLink()
        }
        refreshGeometry(animationContext: keyboardContext ?? .hidden)
    }

    func refreshGeometry() {
        refreshGeometry(animationContext: nil)
    }

    func stop() {
        stopDisplayLink()
        pickerViewController = nil
        keyboardContext = nil
        pickerLiftHeight = nil
        keyboardHandoffTargetHeight = nil
        isAwaitingKeyboard = false
    }

    private func refreshGeometry(
        animationContext: QuickLayoutKeyboardContext?
    ) {
        guard let hostView else { return }
        let keyboardHeight = visibleKeyboardHeight(in: hostView)
        if isAwaitingKeyboard,
           pickerViewController == nil,
           let targetHeight = keyboardHandoffTargetHeight,
           abs(keyboardHeight - targetHeight) <= 0.5 {
            // Sheet 已经关闭且 keyboard layout guide 到达通知声明的最终高度后，
            // 才恢复逐帧键盘几何，避免两个反向动画产生中间低谷。
            isAwaitingKeyboard = false
            keyboardHandoffTargetHeight = nil
        }
        let resolved = Self.resolvedObstruction(
            keyboardHeight: keyboardHeight,
            pickerLiftHeight: pickerViewController == nil
                ? nil
                : pickerLiftHeight ?? storedKeyboardContentHeight,
            isAwaitingKeyboard: isAwaitingKeyboard,
            keyboardHandoffTargetHeight: keyboardHandoffTargetHeight
        )
        guard abs(resolved - currentHeight) > 0.5 else { return }
        currentHeight = resolved
        heightDidChange?(resolved, animationContext)
    }

    private func visibleKeyboardHeight(in view: UIView) -> CGFloat {
        guard keyboardContext?.isVisible == true else { return 0 }
        let frame = view.keyboardLayoutGuide.layoutFrame
        guard !frame.isNull, frame.minY < view.bounds.maxY else { return 0 }
        return Self.contentObstruction(
            containerMaxY: view.bounds.maxY,
            obstructionMinY: frame.minY,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    /// 把键盘通知的最终 frame 转成不含底部安全区的稳定内容高度。
    private func targetKeyboardContentHeight(
        for context: QuickLayoutKeyboardContext,
        in view: UIView
    ) -> CGFloat {
        let resolved = context.resolved(in: view)
        guard context.isVisible,
              !resolved.isFloatingOrSplitKeyboard,
              !resolved.isHardwareKeyboardLikely else { return 0 }
        return max(resolved.height - view.safeAreaInsets.bottom, 0)
    }

    nonisolated static func contentObstruction(
        containerMaxY: CGFloat,
        obstructionMinY: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        max(containerMaxY - obstructionMinY - safeAreaBottom, 0)
    }

    /// 照片 Sheet 展示时停止键盘逐帧采样；显式开始照片到键盘的交接后才恢复。
    nonisolated static func shouldTrackKeyboardGeometry(
        isPickerPresented: Bool,
        isAwaitingKeyboard: Bool,
        keyboardIsVisible: Bool
    ) -> Bool {
        keyboardIsVisible && shouldApplyKeyboardLayout(
            isPickerPresented: isPickerPresented,
            isAwaitingKeyboard: isAwaitingKeyboard
        )
    }

    /// 照片 Sheet 是当前遮挡源时，键盘事件只更新缓存，不驱动页面布局。
    nonisolated static func shouldApplyKeyboardLayout(
        isPickerPresented: Bool,
        isAwaitingKeyboard: Bool
    ) -> Bool {
        !isPickerPresented || isAwaitingKeyboard
    }

    /// 统一解析输入栏底部抬升量。
    ///
    /// 照片 Sheet 展示期间始终使用打开时锁定的键盘等高值，不读取 Sheet 的实时
    /// frame。Sheet 继续展开到大档时由系统覆盖下层内容；键盘正常显示时才读取实时
    /// layout guide。照片切回键盘期间使用键盘通知声明的最终目标高度。
    nonisolated static func resolvedObstruction(
        keyboardHeight: CGFloat,
        pickerLiftHeight: CGFloat?,
        isAwaitingKeyboard: Bool = false,
        keyboardHandoffTargetHeight: CGFloat? = nil
    ) -> CGFloat {
        if isAwaitingKeyboard {
            return max(
                0,
                keyboardHandoffTargetHeight ?? pickerLiftHeight ?? 0
            )
        }
        if let pickerLiftHeight {
            return max(0, pickerLiftHeight)
        }
        return max(0, keyboardHeight)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: displayLinkProxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
