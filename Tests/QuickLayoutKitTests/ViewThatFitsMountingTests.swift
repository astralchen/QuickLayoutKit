import QuickLayout
import Testing
import UIKit
@testable import QuickLayoutKitCore
@testable import QuickLayoutKitUIKit

/// 验证候选的实际挂载、复用和测量隔离，不以隐藏或零尺寸代替退出层级。
@MainActor
@Suite(.serialized)
struct ViewThatFitsMountingTests {
    private func place(_ host: UIView, width: CGFloat) {
        host.frame = CGRect(x: 0, y: 0, width: width, height: 80)
        host.setNeedsLayout()
        host.layoutIfNeeded()
    }

    @Test func unselectedControlsDetachAndPreserveBusinessState() {
        let primary = UIView()
        let slider = UISlider(frame: CGRect(x: -20, y: -20, width: 200, height: 44))
        primary.addSubview(slider)
        let fallback = UIButton(type: .system)
        let host = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                primary.frame(width: 200, height: 40)
                fallback.frame(width: 50, height: 40)
            }
        }
        place(host, width: 100)
        #expect(primary.superview == nil && fallback.superview === host)
        #expect(!primary.isHidden && !primary.clipsToBounds && slider.superview === primary)
        place(host, width: 300)
        #expect(primary.superview === host && fallback.superview == nil)
        slider.value = 0.7
        primary.isHidden = true
        place(host, width: 100)
        place(host, width: 300)
        #expect(primary.isHidden && slider.value == 0.7)
    }

    @Test func measurementDoesNotMountOrReplaceCurrentSelection() {
        let a = UIView(), b = UIView()
        let host = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                a.frame(width: 200, height: 40)
                b.frame(width: 50, height: 40)
            }
        }
        _ = host.sizeThatFits(CGSize(width: 300, height: 80))
        #expect(a.superview == nil && b.superview == nil)
        place(host, width: 100)
        _ = host.sizeThatFits(CGSize(width: 300, height: 80))
        #expect(a.superview == nil && b.superview === host)
        place(host, width: 300)
        #expect(a.superview === host && b.superview == nil)
    }

    @Test func cachedNodesKeepIndependentSelections() {
        let a = UIView(), b = UIView()
        let element = ViewThatFits(in: .horizontal) {
            a.frame(width: 200, height: 40)
            b.frame(width: 50, height: 40)
        }
        let narrow = element.layoutThatFits(CGSize(width: 100, height: 80))
        let wide = element.layoutThatFits(CGSize(width: 300, height: 80))
        #expect(element.views().count == 2)
        #expect(QuickLayoutMeasuredLayout(element: element, node: narrow).mountedViews == [b])
        #expect(QuickLayoutMeasuredLayout(element: element, node: wide).mountedViews == [a])
        #expect(a.superview == nil && b.superview == nil)
    }

    @Test func sharedViewsAndNestedCandidatesKeepTheirOwnSelection() {
        let shared = UIView(), wide = UIView(), compact = UIView(), outer = UIView()
        var innerWidth: CGFloat = 100
        let host = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                ViewThatFits(in: .horizontal) {
                    QuickLayoutKitCore.HStack { shared.frame(width: 20, height: 20); wide.frame(width: 200, height: 20) }
                    QuickLayoutKitCore.HStack { shared.frame(width: 20, height: 20); compact.frame(width: 30, height: 20) }
                }.frame(width: innerWidth)
                outer.frame(width: 10, height: 20)
            }
        }
        for width: CGFloat in [100, 400, 30, 100] {
            innerWidth = width == 400 ? 300 : 100
            place(host, width: width)
            if width == 30 {
                #expect(shared.superview == nil && wide.superview == nil && compact.superview == nil)
                #expect(outer.superview === host)
            } else {
                #expect(shared.superview === host && outer.superview == nil)
                #expect((wide.superview === host) == (width == 400))
                #expect((compact.superview === host) == (width == 100))
                #expect(host.subviews.filter { $0 === shared }.count == 1)
            }
        }
    }

    @Test func sharedControlNeverDetachesDuringBranchChanges() {
        let shared = MountTrackingView(), wide = UIView(), compact = UIView()
        let host = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                QuickLayoutKitCore.HStack { shared.frame(width: 20, height: 20); wide.frame(width: 200, height: 20) }
                QuickLayoutKitCore.HStack { shared.frame(width: 20, height: 20); compact.frame(width: 30, height: 20) }
            }
        }
        for width: CGFloat in [100, 300, 100, 300] { place(host, width: width) }
        #expect(shared.mounts == 1 && shared.detaches == 0)
        #expect(!shared.wasPlacedWithoutSuperview)
    }

    @Test func disabledHostRemovesMountedBranchWithoutMeasuringBody() {
        let leaf = UIView()
        let host = DisableableHost { leaf.frame(width: 30, height: 20) }
        place(host, width: 100)
        #expect(leaf.superview === host)
        host.enabled = false
        place(host, width: 100)
        #expect(leaf.superview == nil)
        host.enabled = true
        place(host, width: 100)
        #expect(leaf.superview === host)
    }

    @Test func sharedViewOutsideUnselectedBranchStaysMounted() {
        let shared = UIView(), fallback = UIView()
        let host = QuickLayoutView {
            QuickLayoutKitCore.VStack {
                ViewThatFits(in: .horizontal) {
                    shared.frame(width: 200, height: 20)
                    fallback.frame(width: 20, height: 20)
                }
                shared.frame(width: 30, height: 20)
            }
        }
        place(host, width: 100)
        #expect(shared.superview === host && fallback.superview === host)
        #expect(host.subviews.filter { $0 === shared }.count == 1)
    }

    @Test func removingDeclarationAndTransferringDetachedView() {
        let a = UIView(), b = UIView()
        var showsCandidates = true
        let first = QuickLayoutView {
            if showsCandidates {
                ViewThatFits(in: .horizontal) {
                    a.frame(width: 200, height: 40)
                    b.frame(width: 50, height: 40)
                }
            } else { EmptyLayout() }
        }
        place(first, width: 100)
        let second = QuickLayoutView { a.frame(width: 50, height: 40) }
        place(second, width: 100)
        showsCandidates = false
        place(first, width: 100)
        #expect(a.superview === second && b.superview == nil && !a.isHidden)
    }

    @Test func emptyFallbackDetachesAndSelectedZeroSizeStillMounts() {
        let view = UIView()
        var zeroSize = false
        let host = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                view.frame(width: zeroSize ? 0 : 200, height: zeroSize ? 0 : 40)
                EmptyLayout()
            }
        }
        place(host, width: 300)
        place(host, width: 100)
        #expect(view.superview == nil && !view.isHidden)
        zeroSize = true
        place(host, width: 100)
        #expect(view.superview === host && view.bounds.size == .zero && !view.isHidden)
    }

    @Test func scrollHostUsesFinalProposalAndDetachesRemovedCandidates() {
        let a = UIView(), b = UIView()
        let host = QuickLayoutScrollView(.vertical) {
            ViewThatFits(in: .horizontal) {
                a.frame(width: 200, height: 40)
                b.frame(width: 50, height: 40)
            }
        }
        place(host, width: 100)
        #expect(a.superview == nil && b.superview === host)
        _ = host.sizeThatFits(CGSize(width: 300, height: 80))
        #expect(a.superview == nil && b.superview === host)
        place(host, width: 300)
        #expect(a.superview === host && b.superview == nil)
        host.configure(axis: .vertical, showsIndicators: true, content: [b.frame(width: 50, height: 40)])
        place(host, width: 100)
        #expect(a.superview == nil && b.superview === host)
    }

    @Test func geometryReaderMountsOnlyItsSelectedDynamicContent() {
        let a = UIView(), b = UIView()
        let host = QuickLayoutView {
            GeometryReader { _ in
                ViewThatFits(in: .horizontal) {
                    a.frame(width: 200, height: 40)
                    b.frame(width: 50, height: 40)
                }
            }
        }
        for width: CGFloat in [100, 300, 100] {
            place(host, width: width)
            #expect((a.superview === host) == (width == 300))
            #expect((b.superview === host) == (width == 100))
        }
    }

    @Test func nestedHostsMeasureWithoutMountingTheirOwnCandidates() {
        let a = UIView(), b = UIView()
        let child = QuickLayoutView {
            ViewThatFits(in: .horizontal) {
                a.frame(width: 200, height: 40)
                b.frame(width: 50, height: 40)
            }
        }
        let host = QuickLayoutView { child.resizable().frame(maxWidth: .infinity, maxHeight: .infinity) }
        _ = host.sizeThatFits(CGSize(width: 300, height: 80))
        #expect(child.superview == nil && a.superview == nil && b.superview == nil)
        for width: CGFloat in [100, 300, 100] {
            place(host, width: width)
            child.layoutIfNeeded()
            #expect(child.superview === host)
            #expect((a.superview === child) == (width == 300))
            #expect((b.superview === child) == (width == 100))
        }
    }
}

/// 记录真实挂载回调，验证共享控件切换时没有被移除后重新添加。
@MainActor
private final class MountTrackingView: UIView {
    var mounts = 0
    var detaches = 0
    var wasPlacedWithoutSuperview = false
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil { detaches += 1 } else { mounts += 1 }
    }
    override var center: CGPoint {
        didSet { if superview == nil { wasPlacedWithoutSuperview = true } }
    }
}

@MainActor
private final class DisableableHost: QuickLayoutView {
    var enabled = true
    override var isBodyEnabled: Bool { enabled }
}
