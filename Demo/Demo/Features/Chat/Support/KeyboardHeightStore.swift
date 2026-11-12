import UIKit

/// 保存本聊天页面见过的停靠键盘高度，单位是从窗口底边到键盘顶边的点数。
@MainActor
final class KeyboardHeightStore {
    struct Layout: Hashable {
        let horizontal: UIUserInterfaceSizeClass
        let vertical: UIUserInterfaceSizeClass
        let isWiderThanTall: Bool

        init(window: UIWindow) {
            horizontal = window.traitCollection.horizontalSizeClass
            vertical = window.traitCollection.verticalSizeClass
            isWiderThanTall = window.bounds.width > window.bounds.height
        }

        /// 首次打开照片时使用的估值，来自 Duo 默认英文停靠键盘的全屏测量。
        var estimatedHeight: CGFloat {
            switch (horizontal, vertical, isWiderThanTall) {
            case (.regular, .regular, false): 350
            case (.regular, .regular, true): 264
            case (.compact, .regular, false): 304
            case (.compact, .compact, true): 230
            default: 300
            }
        }
    }

    private var measuredHeights: [Layout: CGFloat] = [:]

    func record(_ windowHeight: CGFloat, for layout: Layout) {
        measuredHeights[layout] = windowHeight
    }

    func height(for layout: Layout) -> CGFloat {
        measuredHeights[layout] ?? layout.estimatedHeight
    }
}
