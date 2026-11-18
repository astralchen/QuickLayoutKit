import UIKit
import Testing
import QuickLayout
@testable import QuickLayoutKit

/// UIKit 17 的局部 trait API；旧系统由测试控制器边界提供原生 trait。
@MainActor
func setNativeTestDirection(_ direction: UIUserInterfaceLayoutDirection, on view: UIView) {
    if #available(iOS 17.0, *) {
        view.traitOverrides.layoutDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
        view.updateTraitsIfNeeded()
    } else {
        view.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
    }
    view.setNeedsLayout()
}

@MainActor
@Suite(.serialized)
struct NativeDirectionInheritanceTests {
    @Test(arguments: [false, true])
    func gradientKeepsNativeSemanticsAcrossBoundaryChanges(useLegacyTraitOverride: Bool) throws {
        let fixture = DirectionFixture(useLegacyTraitOverride: useLegacyTraitOverride)
        defer { fixture.window.isHidden = true }
        let gradient = QuickLayoutLinearGradientView(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        gradient.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        fixture.child.view.addSubview(gradient)
        let layer = try #require(gradient.layer as? CAGradientLayer)
        for direction: UIUserInterfaceLayoutDirection? in [.leftToRight, .rightToLeft, nil] {
            fixture.setDirection(direction)
            for semantic: UISemanticContentAttribute in [.unspecified, .forceLeftToRight, .playback, .spatial, .unspecified] {
                gradient.semanticContentAttribute = semantic
                gradient.layoutIfNeeded()
                let rtl = gradient.effectiveUserInterfaceLayoutDirection == .rightToLeft
                #expect(layer.startPoint.x == (rtl ? 1 : 0))
                #expect(layer.endPoint.x == (rtl ? 0 : 1))
                #expect(gradient.semanticContentAttribute == semantic)
            }
        }
    }

    @Test(arguments: [false, true])
    func removingControllerBoundaryRestoresNativeInheritance(useLegacyTraitOverride: Bool) {
        let fixture = DirectionFixture(useLegacyTraitOverride: useLegacyTraitOverride)
        defer { fixture.window.isHidden = true }
        let nativePeer = UIView()
        let nested = QuickLayoutView()
        let host = QuickLayoutView { nested.resizable() }
        host.frame = CGRect(x: 0, y: 0, width: 160, height: 60)
        fixture.child.view.addSubview(host)
        fixture.child.view.addSubview(nativePeer)
        for direction: UIUserInterfaceLayoutDirection? in [.leftToRight, .rightToLeft, nil, .rightToLeft, .leftToRight, nil] {
            fixture.setDirection(direction)
            host.layoutIfNeeded()
            nested.layoutIfNeeded()
            let expected = direction ?? fixture.parent.view.effectiveUserInterfaceLayoutDirection
            #expect(nativePeer.effectiveUserInterfaceLayoutDirection == expected)
            for view in [host, nested] {
                #expect(view.semanticContentAttribute == .unspecified)
                #expect(view.effectiveUserInterfaceLayoutDirection == expected)
                #expect(view.quickLayoutEnvironment.layoutDirection == expected.quickLayoutDirection)
            }
            if direction == nil {
                #expect(fixture.child.view.semanticContentAttribute == .unspecified)
            }
        }
    }

    @Test func hostsInheritTraitsWithoutWritingSemanticAttributes() {
        let fixture = DirectionFixture()
        defer { fixture.window.isHidden = true }
        let hosts: [UIView] = [
            QuickLayoutView(), QuickLayoutScrollView(), QuickLayoutButton(action: {}),
            QuickLayoutVisualEffectView(effect: nil),
            QuickLayoutCollectionViewCell(frame: .zero),
            QuickLayoutTableViewCell(style: .default, reuseIdentifier: nil),
            QuickLayoutTableViewHeaderFooterView(reuseIdentifier: nil),
            QuickLayoutCollectionReusableView(frame: .zero),
            NativeProbeContent(configuration: NativeProbeConfiguration()),
        ]
        for host in hosts {
            host.frame = CGRect(x: 0, y: 0, width: 160, height: 60)
            fixture.child.view.addSubview(host)
        }
        for direction: UIUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft, .leftToRight] {
            fixture.setDirection(direction)
            for host in hosts {
                host.setNeedsLayout()
                host.layoutIfNeeded()
                _ = host.sizeThatFits(CGSize(width: 160, height: 60))
                #expect(host.semanticContentAttribute == .unspecified)
                #expect(host.effectiveUserInterfaceLayoutDirection == direction)
                #expect(host.quickLayoutEnvironment.layoutDirection == direction.quickLayoutDirection)
            }
        }
    }

    @Test func explicitSemanticsSurviveReuseMeasurementAndConfiguration() {
        let fixture = DirectionFixture()
        defer { fixture.window.isHidden = true }
        fixture.setDirection(.rightToLeft)
        for semantic: UISemanticContentAttribute in [.playback, .spatial, .forceLeftToRight, .forceRightToLeft] {
            let cell = QuickLayoutCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 160, height: 60))
            let content = NativeProbeContent(configuration: NativeProbeConfiguration())
            cell.semanticContentAttribute = semantic
            content.semanticContentAttribute = semantic
            cell.contentView.addSubview(content)
            fixture.child.view.addSubview(cell)
            for direction: UIUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
                fixture.setDirection(direction)
                cell.prepareForReuse()
                content.configuration = NativeProbeConfiguration()
                _ = cell.sizeThatFits(CGSize(width: 160, height: 60))
                _ = content.sizeThatFits(CGSize(width: 160, height: 60))
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                #expect(cell.semanticContentAttribute == semantic)
                #expect(content.semanticContentAttribute == semantic)
            }
            content.semanticContentAttribute = .unspecified
            cell.semanticContentAttribute = .unspecified
            #expect(content.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            cell.removeFromSuperview()
        }
    }

    @Test func detachedHostReattachesUsingCurrentTraitsAndRestoresUnspecified() {
        let fixture = DirectionFixture()
        defer { fixture.window.isHidden = true }
        let first = UIView(), second = UIView()
        let host = QuickLayoutView {
            HStack { first.frame(width: 20, height: 20); second.frame(width: 20, height: 20) }
        }
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        fixture.child.view.addSubview(host)
        fixture.setDirection(.leftToRight)
        host.layoutIfNeeded()
        #expect(first.frame.minX < second.frame.minX)
        host.removeFromSuperview()
        fixture.setDirection(.rightToLeft)
        #expect(host.semanticContentAttribute == .unspecified)
        fixture.child.view.addSubview(host)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        #expect(first.frame.minX > second.frame.minX)
        host.semanticContentAttribute = .forceLeftToRight
        host.layoutIfNeeded()
        #expect(first.frame.minX < second.frame.minX)
        host.semanticContentAttribute = .unspecified
        host.layoutIfNeeded()
        #expect(first.frame.minX > second.frame.minX)
        #expect(host.semanticContentAttribute == .unspecified)
    }

    @Test func contentMatchesNativeViewUnderIntermediateSemanticBoundary() {
        let fixture = DirectionFixture()
        defer { fixture.window.isHidden = true }
        fixture.setDirection(.rightToLeft)
        for boundary: UIView in [UITableViewCell(), UITableViewHeaderFooterView(), UICollectionViewCell(), UICollectionReusableView()] {
            fixture.child.view.addSubview(boundary)
            let intermediate = UIView()
            let content = NativeProbeContent(configuration: NativeProbeConfiguration())
            let nativePeer = UIView()
            boundary.addSubview(intermediate)
            intermediate.addSubview(content)
            intermediate.addSubview(nativePeer)
            intermediate.semanticContentAttribute = .forceLeftToRight
            content.configuration = NativeProbeConfiguration()
            _ = content.sizeThatFits(CGSize(width: 160, height: 60))
            #expect(content.semanticContentAttribute == .unspecified)
            // 父视图的 semantic 不保证传播到子树；以同层原生 UIView 为参照。
            #expect(content.effectiveUserInterfaceLayoutDirection == nativePeer.effectiveUserInterfaceLayoutDirection)
            #expect(intermediate.semanticContentAttribute == .forceLeftToRight)
            intermediate.semanticContentAttribute = .unspecified
            content.configuration = NativeProbeConfiguration()
            #expect(content.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        }
    }
}

@MainActor
private final class DirectionFixture {
    let parent = UIViewController()
    let child = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let useLegacyTraitOverride: Bool
    init(useLegacyTraitOverride: Bool = false) {
        self.useLegacyTraitOverride = useLegacyTraitOverride
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.view.frame = window.bounds
        child.didMove(toParent: parent)
        window.rootViewController = parent
        window.isHidden = false
    }
    func setDirection(_ direction: UIUserInterfaceLayoutDirection?) {
        if #available(iOS 17.0, *), !useLegacyTraitOverride {
            if let direction {
                child.traitOverrides.layoutDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
            } else {
                child.traitOverrides.remove(UITraitLayoutDirection.self)
            }
            child.updateTraitsIfNeeded()
            child.view.updateTraitsIfNeeded()
        } else {
            parent.setOverrideTraitCollection(direction.map {
                UITraitCollection(layoutDirection: $0 == .rightToLeft ? .rightToLeft : .leftToRight)
            }, forChild: child)
            child.view.semanticContentAttribute = direction.map {
                $0 == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
            } ?? .unspecified
        }
        window.layoutIfNeeded()
    }
}

private struct NativeProbeConfiguration: UIContentConfiguration {
    func makeContentView() -> UIView & UIContentView { NativeProbeContent(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

private final class NativeProbeContent: QuickLayoutContentView {
    override var body: Layout { EmptyLayout() }
}
