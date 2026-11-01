import Testing
import UIKit
import QuickLayout
import QuickLayoutKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct LayoutClosureLifetimeTests {
    @Test func composerContainersOutliveOwnerWithoutRetainingIt() throws {
        guard #available(iOS 26.0, *) else { return }
        weak var owner: ComposerView?
        let containers: [UIView] = autoreleasepool {
            let composer = ComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
            owner = composer
            let views: [UIView] = [
                composer.attachmentGlassView, composer.editorContainer,
                composer.textActionContainer, composer.inputGlassView,
                composer.recordingGlassView, composer.previewGlassView,
                composer.audioCancelGlassView, composer.previewDurationContainer,
            ]
            for view in views {
                _ = view.sizeThatFits(CGSize(width: 390, height: 200))
                view.removeFromSuperview()
            }
            return views
        }
        try #require(owner == nil)
        verifyDetachedLayouts(containers)
    }

    @Test func previewGlassCanLayoutAfterControlsDeallocation() throws {
        guard #available(iOS 26.0, *) else { return }
        weak var owner: AttachmentPreviewControlsView?
        let glass: QuickLayoutVisualEffectView = try autoreleasepool {
            let controls = AttachmentPreviewControlsView(items: [], selectedIndex: 0)
            owner = controls
            controls.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            controls.layoutIfNeeded()
            let glass = try #require(controls.allSubviews(of: QuickLayoutVisualEffectView.self).first)
            glass.removeFromSuperview()
            return glass
        }
        try #require(owner == nil)
        verifyDetachedLayouts([glass])
    }

    @Test func deferredRepresentableCanLoadAfterControllerDeallocation() throws {
        weak var owner: ViewControllerRepresentableDemoViewController?
        let deferred = autoreleasepool {
            let controller = ViewControllerRepresentableDemoViewController()
            owner = controller
            return controller.makeLazyChild(name: "Detached")
        }
        #expect(!deferred.isLoaded)
        try #require(owner == nil)
        let host = deferred.loadIfNeeded()
        #expect(deferred.isLoaded)
        verifyDetachedLayouts([host])
    }

    private func verifyDetachedLayouts(_ views: [UIView]) {
        for view in views {
            for width in [320.0, 720.0] {
                let size = view.sizeThatFits(CGSize(width: width, height: .infinity))
                #expect(size.width.isFinite)
                #expect(size.height.isFinite)
                view.frame = CGRect(x: 0, y: 0, width: width, height: 200)
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
        }
    }
}
