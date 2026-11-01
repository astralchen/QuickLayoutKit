import UIKit

extension VoiceRoomViewController: AppTabActivity {
    func resignActiveTab() {
        view.endEditing(true)
        viewModel.stopObservingStageSnapshots()
        seatStageView.finishUpdatesImmediately()
        giftFlightAnimators.values.forEach { $0.cancel() }
        giftFlightAnimators.removeAll()
        if let giftSheetViewController { closeGiftSheet(giftSheetViewController) }
    }
}
