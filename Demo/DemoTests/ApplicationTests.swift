import Testing
@testable import Demo

/// 各主题用例通过同目录的 ApplicationTests+*.swift 扩展组织。
/// 保持单一串行套件，避免操作窗口、语言及 UIKit 状态的用例并发执行。
@MainActor
@Suite(.serialized)
struct ApplicationTests {
    init() {
        // Scene 方向是共享状态，每个用例先建立确定的应用语言。
        Localization.setLocale(identifier: "en")
    }
}
