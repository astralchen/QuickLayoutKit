import Foundation

/// 页面内音频和视频共用的播放所有权。先同步停止旧对象，再交给新对象。
@MainActor
final class IMessageChatPlaybackCoordinator {
    private var owner: UUID?
    private var stopOwner: (() -> Void)?

    func acquire(owner newOwner: UUID, stop: @escaping () -> Void) {
        guard owner != newOwner else { return }
        let stopPrevious = stopOwner
        owner = nil
        stopOwner = nil
        stopPrevious?()
        owner = newOwner
        stopOwner = stop
    }

    func release(owner previousOwner: UUID) {
        guard owner == previousOwner else { return }
        owner = nil
        stopOwner = nil
    }
}
