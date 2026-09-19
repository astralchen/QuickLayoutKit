import AppLocalization
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    @Test(arguments: ["zh-Hans", "en", "ar"])
    func followButtonKeepsSizeAcrossStates(locale: String) throws {
        Localization.setLocale(identifier: locale)
        defer { Localization.setLocale(identifier: "en-US") }
        let button = FollowButton(frame: .zero)
        let host = UIViewController()
        host.view.addSubview(button)
        let window = try makeVisibleTestWindow(rootViewController: host, size: CGSize(width: 320, height: 852))
        defer { window.isHidden = true }
        var sizes: [CGSize] = []
        for (following, requesting) in [(false, false), (false, true), (true, false), (true, true), (true, false), (false, false)] {
            configureFollow(button, following: following, requesting: requesting)
            button.frame = CGRect(origin: CGPoint(x: 20, y: 100), size: button.sizeThatFits(CGSize(width: 292, height: 100)))
            button.layoutIfNeeded()
            sizes.append(button.bounds.size)
            #expect(button.allSubviews(of: UILabel.self).count == 2)
            #expect(button.isEnabled == !requesting)
            #expect(button.isSelected == following)
            #expect(button.accessibilityTraits.contains(.selected) == following)
        }
        let size = try #require(sizes.first)
        #expect(size.width >= 88)
        #expect(size.height >= 28)
        #expect(sizes.allSatisfy { abs($0.width - size.width) < 0.5 && abs($0.height - size.height) < 0.5 })
        #expect(button.minimumHitTargetSize == CGSize(width: 44, height: 44))
    }

    @Test func followButtonInterruptionsAndReducedMotionSettleCorrectly() async throws {
        let button = FollowButton(frame: CGRect(x: 20, y: 100, width: 100, height: 28))
        let host = UIViewController()
        host.view.addSubview(button)
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        configureFollow(button, following: false, requesting: false)
        button.layoutIfNeeded()
        configureFollow(button, following: false, requesting: true)
        configureFollow(button, following: true, requesting: false)
        #expect(button.isTransitionAnimating)
        // 尚未结束的成功动画被取消请求与失败恢复打断。
        configureFollow(button, following: true, requesting: true)
        configureFollow(button, following: true, requesting: false)
        // 相同状态刷新应直接呈现终态，不重播成功动效。
        configureFollow(button, following: true, requesting: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!button.isTransitionAnimating)
        let spinner = try #require(button.allSubviews(of: UIActivityIndicatorView.self).first)
        let checkmark = try #require(button.allSubviews(of: UIImageView.self).first { $0.accessibilityIdentifier == "liveRoom.follow.checkmark" })
        #expect(!spinner.isAnimating)
        #expect(spinner.alpha == 0)
        #expect(checkmark.alpha == 1)
        #expect(checkmark.transform == .identity)
        #expect(button.isSelected && button.isEnabled)

        button.isReduceMotionEnabled = { true }
        configureFollow(button, following: true, requesting: true)
        configureFollow(button, following: false, requesting: false)
        configureFollow(button, following: false, requesting: true)
        configureFollow(button, following: true, requesting: false)
        #expect(checkmark.transform == .identity)
        try await Task.sleep(for: .milliseconds(160))
        #expect(!button.isTransitionAnimating)
        #expect(!spinner.isAnimating)
        #expect(checkmark.alpha == 1)

        configureFollow(button, following: true, requesting: true)
        button.removeFromSuperview()
        configureFollow(button, following: false, requesting: false)
        #expect(!button.isTransitionAnimating)
        #expect(!spinner.isAnimating)
        #expect(checkmark.alpha == 0)
        #expect(button.transform == .identity)
    }

    @Test(arguments: [false, true])
    func followButtonRestoresConfirmedStateAfterFailure(initiallyFollowing: Bool) async throws {
        let handler = ControlledFollowRequestHandler()
        let model = VoiceRoomViewModel(isFollowing: initiallyFollowing, followRequestHandler: handler)
        let room = VoiceRoomViewController(viewModel: model)
        let window = try makeVisibleTestWindow(rootViewController: room)
        defer { window.isHidden = true }
        room.view.layoutIfNeeded()
        let button = try #require(room.roomHeaderView.allSubviews(of: FollowButton.self).first)
        let width = button.bounds.width
        room.toggleFollowing()
        #expect(await waitForCondition { model.state.pendingFollowingState != nil })
        handler.fail()
        #expect(await waitForCondition { model.state.pendingFollowingState == nil && room.followRequestTask == nil })
        try await Task.sleep(for: .milliseconds(240))
        room.view.layoutIfNeeded()
        #expect(model.state.isFollowing == initiallyFollowing)
        #expect(button.isSelected == initiallyFollowing)
        #expect(button.isEnabled)
        #expect(abs(button.bounds.width - width) < 0.5)
        #expect(button.allSubviews(of: UIActivityIndicatorView.self).allSatisfy { !$0.isAnimating })
        #expect(!button.isTransitionAnimating)
    }

    private func configureFollow(_ button: FollowButton, following: Bool, requesting: Bool) {
        button.configure(followTitle: Localization.text("liveRoom.follow.shortTitle"),
                         followedTitle: Localization.text("liveRoom.messages.followed"),
                         accessibilityTitle: Localization.text(requesting ? "liveRoom.messages.followRequesting" : "liveRoom.messages.follow"),
                         isFollowing: following, isRequesting: requesting)
    }
}
