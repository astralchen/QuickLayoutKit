import QuickLayout
import Testing
import UIKit
@testable import QuickLayoutKitUIKit

@MainActor
struct ScrollIndicatorSafeAreaTests {
    /// 原生 List 同样只补一次安全区，忽略安全区与撤销声明都保留业务基线。
    @Test func nativeListIndicatorsRespectIgnoringAndDeclarationRemoval() {
        let table = IndicatorSafeAreaTableView()
        table.contentInsetAdjustmentBehavior = .never
        table.verticalScrollIndicatorInsets.right = 5
        var ignores = false
        var declared = true
        let host = IndicatorSafeAreaHost {
            if !declared {
                table.resizable()
            } else if ignores {
                List(table).ignoresSafeArea(.container)
            } else {
                List(table).contentMargins(.trailing, 7, for: .scrollIndicators)
            }
        }
        host.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.layoutIfNeeded()
        #expect(table.verticalScrollIndicatorInsets.right == 12)
        ignores = true
        host.setNeedsLayout(); host.layoutIfNeeded()
        #expect(table.verticalScrollIndicatorInsets.right == 5 - IndicatorSafeAreaHost.insets.right)
        declared = false
        host.setNeedsLayout(); host.layoutIfNeeded()
        #expect(table.verticalScrollIndicatorInsets == UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 5))
    }

    /// 内容与指示器的自动调整相互独立，四种组合都只补足各自缺少的安全区。
    @Test func automaticContentAndIndicatorAdjustmentsAreIndependent() {
        for contentAutomatic in [false, true] {
            for indicatorAutomatic in [false, true] {
                let scroll = IndicatorSafeAreaScrollView()
                scroll.adjustsContent = contentAutomatic
                scroll.automaticallyAdjustsScrollIndicatorInsets = indicatorAutomatic
                let host = IndicatorSafeAreaHost {
                    ScrollView(scroll) { UIView().frame(height: 1600) }
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .contentMargins(.trailing, 7, for: .scrollIndicators)
                }
                host.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
                for rtl in [false, true, false] {
                    host.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                    scroll.semanticContentAttribute = host.semanticContentAttribute
                    for _ in 0..<3 { host.setNeedsLayout(); host.layoutIfNeeded(); scroll.layoutIfNeeded() }
                    let safe = IndicatorSafeAreaHost.insets
                    let expectedContent = contentAutomatic ? UIEdgeInsets.zero : safe
                    #expect(scroll.contentInset.left == expectedContent.left + 16)
                    #expect(scroll.contentInset.right == expectedContent.right + 16)
                    var expectedIndicator = indicatorAutomatic ? UIEdgeInsets.zero : safe
                    if rtl { expectedIndicator.left += 7 } else { expectedIndicator.right += 7 }
                    #expect(scroll.verticalScrollIndicatorInsets == expectedIndicator)
                }
            }
        }
    }

    /// 运行中关闭自动调整后由 Kit 补齐；恢复自动调整时撤销补偿，业务基线不累加。
    @Test func changingIndicatorAdjustmentPreservesBaselineAndHorizontalAxis() {
        let scroll = IndicatorSafeAreaScrollView()
        scroll.horizontalScrollIndicatorInsets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        let host = IndicatorSafeAreaHost {
            ScrollView(scroll, .horizontal) { UIView().frame(width: 1600, height: 100) }
                .contentMargins(.bottom, 8, for: .scrollIndicators)
        }
        host.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.layoutIfNeeded()
        for automatic in [true, false, true, false] {
            scroll.automaticallyAdjustsScrollIndicatorInsets = automatic
            scroll.setNeedsLayout()
            scroll.layoutIfNeeded()
            let safe = automatic ? UIEdgeInsets.zero : IndicatorSafeAreaHost.insets
            #expect(scroll.horizontalScrollIndicatorInsets == UIEdgeInsets(
                top: 1 + safe.top, left: 2 + safe.left, bottom: 11 + safe.bottom, right: 4 + safe.right))
            #expect(scroll.verticalScrollIndicatorInsets == .zero)
        }
    }
}

private final class IndicatorSafeAreaHost: QuickLayoutView {
    static let insets = UIEdgeInsets(top: 24, left: 62, bottom: 21, right: 62)
    override var safeAreaInsets: UIEdgeInsets { Self.insets }
}

private final class IndicatorSafeAreaScrollView: QuickLayoutScrollView {
    var adjustsContent = false
    override var safeAreaInsets: UIEdgeInsets { IndicatorSafeAreaHost.insets }
    override var adjustedContentInset: UIEdgeInsets {
        let safe = adjustsContent ? safeAreaInsets : .zero
        return UIEdgeInsets(top: contentInset.top + safe.top, left: contentInset.left + safe.left,
                            bottom: contentInset.bottom + safe.bottom, right: contentInset.right + safe.right)
    }
}

private final class IndicatorSafeAreaTableView: UITableView {
    override var safeAreaInsets: UIEdgeInsets { IndicatorSafeAreaHost.insets }
}
