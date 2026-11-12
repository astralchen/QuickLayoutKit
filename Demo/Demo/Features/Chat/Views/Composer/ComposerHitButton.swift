//
//  ComposerHitButton.swift
//  Demo
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 底部操作容器保留按钮原有的扩展命中区域，不受新增容器边界裁剪。
final class ComposerActionContainer: QuickLayoutView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return false }
        return super.point(inside: point, with: event) || subviews.contains { child in
            child.isUserInteractionEnabled && !child.isHidden && child.alpha > 0.01
                && child.point(inside: child.convert(point, from: self), with: event)
        }
    }
}

/// 在系统附件菜单改变键盘候选栏之前，通知页面保留输入栏的位置。
final class ComposerAttachmentButton: UIButton {
    var menuVisibilityDidChange: ((Bool) -> Void)?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        menuVisibilityDidChange?(true)
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.menuVisibilityDidChange?(false) }
        } else {
            menuVisibilityDidChange?(false)
        }
    }
}

/// 保持设计尺寸并把实际命中区域扩展到最小触控尺寸的按钮。
///
/// 视觉尺寸可以小于 44 点；命中测试会围绕按钮中心对称扩展，但不会改变
/// Auto Layout、QuickLayout 或辅助功能报告的视觉边界。
final class ComposerHitButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isPointerInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isPointerInteractionEnabled = true
    }

    /// 按钮响应触控所使用的最小尺寸。
    var minimumHitSize = CGSize(width: 44, height: 44)

    /// 返回指定触点是否位于扩展后的最小触控区域。
    ///
    /// 隐藏、透明或禁止交互时不响应命中；扩展区域不改变视觉边框。
    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return false
        }
        let horizontalInset = min(
            0,
            (bounds.width - minimumHitSize.width) / 2
        )
        let verticalInset = min(
            0,
            (bounds.height - minimumHitSize.height) / 2
        )
        return bounds.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        ).contains(point)
    }
}
