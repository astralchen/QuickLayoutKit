import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func lazyRepresentableDoesNotLoadUntilIncludedInBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var loadCount = 0
        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "A"))
        }

        var showsChild = false
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded == nil)
        #expect(loadCount == 0)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(loadCount == 1)
    }

    @Test func representableAttachesAndDetachesWithQuickLayoutBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []

        let lazyRepresentable = LazyView {
            let representable = QuickLayoutViewControllerRepresentable(child)
            representable.eventHandler = { events.append($0.name) }
            return representable
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent === parent)
        #expect(parent.children.contains { $0 === child })
        #expect(events.contains("willAttach"))
        #expect(events.contains("didAttach"))

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(!parent.children.contains { $0 === child })
        #expect(lazyRepresentable.isLoaded)
        #expect(events.contains("willDetach"))
        #expect(events.contains("didDetach"))
    }

    @Test func lazyRepresentableReusesLoadedHostAndCanReplaceChild() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var loadCount = 0

        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(firstChild)
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(loadCount == 1)
        #expect(firstChild.parent === parent)

        lazyRepresentable.ifLoaded?.setViewController(secondChild)

        #expect(firstChild.parent == nil)
        #expect(secondChild.parent === parent)
    }

    @Test func representableDetailedEventsIncludeContainmentContext() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var detailedEvents: [QuickLayoutViewControllerRepresentable.DetailedEvent] = []

        let representable = QuickLayoutViewControllerRepresentable(firstChild)
        representable.detailedEventHandler = { detailedEvents.append($0) }
        parent.view.addSubview(representable)
        representable.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        representable.layoutIfNeeded()
        representable.setViewController(secondChild)

        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .willDetach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === secondChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didReplaceViewController && $0.oldViewController === firstChild && $0.newViewController === secondChild
        })
    }

    @Test func representableInvalidatesChildPreferredContentSize() {
        let child = RepresentableTestChildViewController(name: "A")
        let representable = QuickLayoutViewControllerRepresentable(child)

        let firstSize = representable.sizeThatFits(CGSize(width: 400, height: 400))
        child.preferredContentSize = CGSize(width: 240, height: 180)
        representable.invalidateChildLayout()
        let secondSize = representable.sizeThatFits(CGSize(width: 400, height: 400))

        #expect(firstSize.height == 96)
        #expect(secondSize.height == 180)
    }

    @Test func resettingLazyRepresentableCreatesANewHostOnNextLayout() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var hostCreationCount = 0
        func makeLazyRepresentable() -> LazyView<QuickLayoutViewControllerRepresentable> {
            LazyView {
                hostCreationCount += 1
                return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "\(hostCreationCount)"))
            }
        }

        var lazyRepresentable = makeLazyRepresentable()
        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 1)
        #expect(lazyRepresentable.isLoaded)
        let firstHost = lazyRepresentable.ifLoaded!

        firstHost.dismantleViewController()
        showsChild = false
        lazyRepresentable = makeLazyRepresentable()
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 2)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(lazyRepresentable.ifLoaded! !== firstHost)
    }

    @Test func parentlessRepresentableDoesNotAttachWithoutControllerOwnedHierarchy() {
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []
        let representable = QuickLayoutViewControllerRepresentable(child)
        representable.eventHandler = { events.append($0.name) }

        let containerView = QuickLayoutView {
            representable.frame(height: 120)
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(events.contains("missingParent"))
        #expect(!events.contains("didAttach"))
    }

    @Test func representableParentRelaysDirectionToItsExistingChild() throws {
        let viewController = ViewControllerRepresentableDemoViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let stateLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text?.contains("LazyView isLoaded") == true
            }
        )
        let showButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first
        )
        let ltrStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        let rtlStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        #expect(stateLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            isHorizontalMirror(
                rtlStateFrame,
                of: ltrStateFrame,
                in: scrollView.contentSize.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        #expect(
            stateLabel.convert(stateLabel.bounds, to: scrollView)
                .approximatelyEquals(ltrStateFrame)
        )

        showButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        let child = try #require(viewController.children.first)
        let childView = child.view!
        let childIdentity = ObjectIdentifier(child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(ObjectIdentifier(viewController.children[0]) == childIdentity)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let childLabels = childView.subviews.compactMap { $0 as? UILabel }
        let childButtons = childView.subviews.compactMap { $0 as? UIButton }
        #expect(childLabels.count == 2)
        #expect(childButtons.count == 1)
        #expect(childButtons.allSatisfy { $0.configuration != nil })
        #expect(
            childLabels.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )
        #expect(
            childButtons.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)
    }
}

private final class RepresentableTestChildViewController: UIViewController {

    let name: String

    init(name: String) {
        self.name = name
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 180, height: 96)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        self.view = view
    }
}
