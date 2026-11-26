import Testing
import UIKit
@testable import Demo

@MainActor
struct NavigationLabPhotoTests {
    @Test(arguments: [false, true])
    func automaticCoverScrollMovesOnePageAndWraps(rightToLeft: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        let photos = JournalPhoto.collection
        var selections: [JournalPhoto] = []
        let cover = RouteCover(.guide, photos: photos) { selections.append($0) }
        let pager = cover.photoPager
        pager.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
        cover.frame = CGRect(x: 0, y: 0, width: 300, height: 220)
        controller.view.addSubview(cover)
        cover.layoutIfNeeded()
        let width = pager.bounds.width
        #expect(width > 0)
        for start in [0, photos.count - 1] {
            pager.select(photos[start])
            let origin = pager.contentOffset.x
            let next = (start + 1) % photos.count
            selections.removeAll()
            pager.advanceAutomatically()
            var sawIntermediateOffset = false
            for _ in 0..<150 where selections.isEmpty {
                let distance = (pager.contentOffset.x - origin) * (rightToLeft ? -1 : 1)
                if distance > 0 && distance < width { sawIntermediateOffset = true }
                try await Task.sleep(nanoseconds: 12_000_000)
            }
            #expect(sawIntermediateOffset)
            #expect(selections == [photos[next]])
            #expect(pager.contentInset == .zero)
            #expect(pager.contentOffset.x == CGFloat(rightToLeft ? photos.count - 1 - next : next) * width)
        }

        pager.select(try #require(photos.last))
        let lastOffset = pager.contentOffset.x
        pager.advanceAutomatically()
        for _ in 0..<40 where pager.contentOffset.x == lastOffset {
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        pager.interruptAutomaticAdvance()
        let interrupted = pager.contentOffset.x
        #expect(abs(interrupted - lastOffset) > 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(pager.contentOffset.x == interrupted)
        pager.settleInterruptedAdvance()
        #expect(pager.contentInset == .zero)
        #expect(pager.contentOffset.x == (rightToLeft ? 0 : CGFloat(photos.count - 1) * width))
    }

    @Test func viewportAndPhotoChooseTheScrollAxis() throws {
        let photos = JournalPhoto.collection
        let cover = RouteCover(.fullScreen, photos: photos)
        let landscape = try #require(photos.first { $0.id == "ridge" })
        let portrait = try #require(photos.first { $0.id == "woodland" })
        cover.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        cover.configure(landscape, position: 1, total: photos.count)
        cover.layoutIfNeeded()
        let pager = try #require(cover.allSubviews(of: UIScrollView.self).first { $0.accessibilityIdentifier == "navLab.photoPager" })
        func visiblePhoto() throws -> UIScrollView {
            try #require(pager.subviews.compactMap { $0 as? UIScrollView }.first { $0.frame.contains(CGPoint(x: pager.bounds.midX, y: pager.bounds.midY)) })
        }
        var scroll = try visiblePhoto()
        scroll.layoutIfNeeded()
        #expect(scroll.bounds.size == cover.bounds.size)
        #expect(scroll.contentSize.height == 400)
        #expect(scroll.contentSize.width > 400)
        #expect(abs(scroll.contentOffset.x * 2 - (scroll.contentSize.width - 400)) <= 1)
        scroll.contentOffset.x = 20
        cover.configure(landscape, position: 1, total: photos.count)
        cover.layoutIfNeeded()
        #expect(scroll.contentOffset.x == 20)

        cover.configure(portrait, position: 3, total: photos.count)
        cover.layoutIfNeeded()
        scroll = try visiblePhoto()
        scroll.layoutIfNeeded()
        #expect(scroll.contentSize.width == 400)
        #expect(scroll.contentSize.height > 400)
        #expect(scroll.contentOffset.x == 0)
        #expect(abs(scroll.contentOffset.y * 2 - (scroll.contentSize.height - 400)) <= 1)

        cover.frame.size = CGSize(width: 300, height: 700)
        cover.layoutIfNeeded()
        scroll.layoutIfNeeded()
        #expect(scroll.contentSize.height == 700)
        #expect(scroll.contentSize.width > 300)
        #expect(scroll.contentOffset.y == 0)
        #expect(abs(scroll.contentOffset.x * 2 - (scroll.contentSize.width - 300)) <= 1)
    }
}
