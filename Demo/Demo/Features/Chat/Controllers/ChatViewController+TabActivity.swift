import UIKit
import QuickLayoutKit

@available(iOS 26.0, *)
extension ChatViewController: AppTabActivity {
    /// 录音结束为有效预览，保留所有已完成附件；此处不执行永久退出清理。
    func resignActiveTab() {
        attachmentPreviewTask?.cancel()
        attachmentPreviewGeneration += 1
        (attachmentPreviewController as? AttachmentPreviewController)?.completeDismissal()
        if !photoController.isPresented { presentedViewController?.dismiss(animated: false) }
        audioController.stopAll()
        conversationView.invalidateMessageMenu()
        view.endEditing(true)
        photoController.dismissPicker(animated: false)
        bottomObstructionCoordinator.stop()
        bottomObstruction = 0
        setNeedsQuickLayout()
        flushDraftBeforeLeaving()
    }
}
