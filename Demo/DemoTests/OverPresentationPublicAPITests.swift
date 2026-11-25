import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct OverPresentationPublicAPITests {
    @Test func subclassesCanCustomizePresentationAndCreateTheirOwnDetents() {
        let controller = LeadingPresentation(presentedViewController: UIViewController(), presenting: UIViewController())
        let detent: MaterialDetent = .automatic()
        controller.detent = detent

        #expect(controller.edge == .leading)
        #expect(controller.detent === detent)
        #expect(controller.detent.backgroundEffect != nil)
        #expect(controller.didInvalidate)
        let custom: MaterialDetent = .custom { $0.maximumDetentValue / 2 }
        #expect(custom !== detent)
    }
}

private final class LeadingPresentation: OverPresentationController {
    override var edge: Edge { .leading }
    private(set) var didInvalidate = false

    override func invalidateDetent() {
        didInvalidate = true
        super.invalidateDetent()
    }
}

private final class MaterialDetent: OverPresentationController.Detent {
    override class func automatic() -> Self {
        let detent = super.automatic()
        detent.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        return detent
    }
}
