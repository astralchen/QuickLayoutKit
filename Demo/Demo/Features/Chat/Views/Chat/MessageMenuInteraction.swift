import AppLocalization
import UIKit

/// 每个 Cell 持有一个交互对象；预览只覆盖消息内容，操作在系统关闭菜单后交付。
@MainActor
final class MessageMenuInteraction: NSObject, UIContextMenuInteractionDelegate {
    struct Source {
        let target: MessageMenuTarget
        let view: UIView
        var path: UIBezierPath? = nil
        var canPresent = true
    }

    private weak var host: UIView?
    private weak var accessibilityView: UIView?
    private lazy var interaction = UIContextMenuInteraction(delegate: self)
    private var source: (() -> Source?)?
    private var items: ((MessageMenuTarget) -> [MessageMenuItem])?
    private var perform: ((MessageMenuOperation, MessageMenuTarget) -> Void)?
    private var preview: UITargetedPreview?
    private var contentPreview: MessageMenuPreviewController?
    private var previewProvider: ((MessageMenuTarget, UIView) -> MessageMenuPreviewController?)?
    private var canPreview: ((MessageMenuTarget) -> Bool)?
    private var openPreview: ((MessageMenuTarget) -> Void)?
    private var displayedTarget: MessageMenuTarget?
    private var accessibilityActions: [UIAccessibilityCustomAction] = []
    private var pendingAction: (() -> Void)?

    func configure(host: UIView, accessibilityView: UIView? = nil,
                   source: @escaping () -> Source?,
                   items: @escaping (MessageMenuTarget) -> [MessageMenuItem],
                   previewProvider: ((MessageMenuTarget, UIView) -> MessageMenuPreviewController?)? = nil,
                   canPreview: ((MessageMenuTarget) -> Bool)? = nil,
                   openPreview: ((MessageMenuTarget) -> Void)? = nil,
                   perform: @escaping (MessageMenuOperation, MessageMenuTarget) -> Void) {
        if self.host !== host {
            self.host?.removeInteraction(interaction)
            host.addInteraction(interaction)
            self.host = host
        }
        self.source = source
        self.items = items
        self.perform = perform
        self.previewProvider = previewProvider
        self.canPreview = canPreview
        self.openPreview = openPreview
        self.accessibilityView = accessibilityView ?? host
        refreshAccessibility()
    }

    func reset() {
        contentPreview?.finish()
        contentPreview = nil
        previewProvider = nil
        canPreview = nil
        openPreview = nil
        source = nil
        items = nil
        perform = nil
        removeAccessibilityActions()
        interaction.dismissMenu()
    }

    func refreshAccessibility() {
        guard let source = source?(), let items else { return }
        removeAccessibilityActions()
        accessibilityActions = items(source.target).filter(\.isEnabled).map { item in
            UIAccessibilityCustomAction(name: Localization.text(item.titleKey)) { [weak self] _ in
                guard let self, let current = self.source?(), current.canPresent else { return false }
                self.perform?(item.operation, current.target)
                return true
            }
        }
        if canPreview?(source.target) == true {
            accessibilityActions.append(UIAccessibilityCustomAction(name: Localization.text("imessage.media.openPreview")) { [weak self] _ in
                guard let self, let source = self.source?(), source.canPresent else { return false }
                self.openPreview?(source.target)
                return true
            })
        }
        accessibilityView?.accessibilityCustomActions = (accessibilityView?.accessibilityCustomActions ?? []) + accessibilityActions
        if let displayedTarget {
            interaction.updateVisibleMenu { [weak self] menu in self?.makeMenu(for: displayedTarget) ?? menu }
        }
    }

    private func removeAccessibilityActions() {
        accessibilityView?.accessibilityCustomActions?.removeAll { old in accessibilityActions.contains { $0 === old } }
        accessibilityActions.removeAll()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let source = source?(), source.canPresent, source.view.window != nil,
              let descriptors = items?(source.target), !descriptors.isEmpty else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = source.view.backgroundColor ?? .clear
        parameters.visiblePath = source.path
        preview = UITargetedPreview(view: source.view, parameters: parameters)
        displayedTarget = source.target
        return UIContextMenuConfiguration(identifier: nil, previewProvider: { [weak self] in
            guard let self else { return nil }
            if contentPreview == nil { contentPreview = previewProvider?(source.target, source.view) }
            return contentPreview
        }) { [weak self] _ in
            self?.makeMenu(for: source.target)
        }
    }

    /// 重建时仍使用打开时的目标，保存反馈变化不会切换到新的媒体封面。
    private func makeMenu(for target: MessageMenuTarget) -> UIMenu {
        let perform = self.perform
        let actions = (items?(target) ?? []).map { item in
            var attributes: UIMenuElement.Attributes = item.isEnabled ? [] : [.disabled]
            if item.operation == .delete { attributes.insert(.destructive) }
            let action = UIAction(title: Localization.text(item.titleKey), image: UIImage(systemName: item.symbol),
                                  identifier: .init("imessage.menu.\(item.operation.rawValue)"), attributes: attributes) { [weak self] _ in
                self?.pendingAction = { perform?(item.operation, target) }
            }
            return (item.operation, action)
        }
        let groups: [[MessageMenuOperation]] = [[.copy, .selectText, .save, .share, .openLink], [.retry], [.delete]]
        return UIMenu(children: groups.compactMap { group in
            let children = actions.filter { group.contains($0.0) }.map(\.1)
            return children.isEmpty ? nil : UIMenu(options: .displayInline, children: children)
        })
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? { preview }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard preview?.view.window != nil else { return nil }
        return preview
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                animator: any UIContextMenuInteractionCommitAnimating) {
        guard let action = contentPreview?.commitAction() else { return }
        animator.preferredCommitStyle = .dismiss
        animator.addCompletion(action)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        contentPreview?.finish()
        contentPreview = nil
        let action = pendingAction
        pendingAction = nil
        displayedTarget = nil
        preview = nil
        if let animator { animator.addCompletion { action?() } }
        else { action?() }
    }
}
