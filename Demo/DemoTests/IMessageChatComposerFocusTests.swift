import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct IMessageChatComposerFocusTests {
    @Test func audioStatesPreserveUserSelectedTextFocus() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let controller = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let composer = IMessageChatComposerView(
            frame: CGRect(x: 0, y: 100, width: 390, height: 80)
        )
        controller.view.addSubview(composer)
        composer.layoutIfNeeded()
        let preview = IMessageChatComposerState.audioPreview(
            attachment: IMessageChatAudioAttachment(
                fileURL: URL(fileURLWithPath: "/tmp/composer-focus.m4a"),
                duration: 2,
                waveform: [0.2, 0.5]
            ),
            isPlaying: false,
            progress: 0
        )
        let states: [IMessageChatComposerState] = [
            .recording(elapsed: 0, waveform: [0.2]), preview, .idle
        ]
        // 模拟用户先点文本框，再切换录音、预览、返回文本；过程中不能丢失焦点。
        #expect(composer.textView.becomeFirstResponder())
        for state in states {
            composer.applyState(state)
            composer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(composer.textView.isFirstResponder, "Focus lost in \(state)")
        }
        // 用户主动收起键盘后，相同切换也不能重新取得文本焦点。
        composer.textView.resignFirstResponder()
        for state in states {
            composer.applyState(state)
            composer.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(!composer.textView.isFirstResponder)
        }
    }
}
