import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

@MainActor
struct TrailPlaceLayoutTests {
    @Test func detailRespectsCurrentDisplayDivision() async throws {
        let photo = try #require(JournalPhoto.collection.first)
        let page = TrailPlaceController(photo: photo)
        let window = try makeVisibleTestWindow(rootViewController: UINavigationController(rootViewController: page))
        defer { window.isHidden = true }
        try #require(await waitForCondition {
            page.view.layoutIfNeeded()
            let safe = page.view.safeAreaLayoutGuide.layoutFrame
            guard let image = page.view.allSubviews(of: UIImageView.self).first(where: { $0.image === photo.thumbnail }),
                  let title = page.view.allSubviews(of: UILabel.self).first(where: { $0.text == photo.title }) else { return false }
            let picture = image.convert(image.bounds, to: page.view)
            let heading = title.convert(title.bounds, to: page.view)
            guard !picture.isEmpty, !heading.isEmpty,
                  picture.minX >= safe.minX - 1, picture.maxX <= safe.maxX + 1,
                  heading.minX >= safe.minX - 1, heading.maxX <= safe.maxX + 1 else { return false }
            #if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                for region in page.view.reservedRegions(kind: .division) {
                    let cut = safe.intersection(region.frame)
                    if cut.isEmpty { continue }
                    guard safe.contains(picture), safe.contains(heading),
                          !picture.intersects(cut), !heading.intersects(cut) else { return false }
                    if cut.height == safe.height && (picture.midX < cut.midX) == (heading.midX < cut.midX) { return false }
                    if cut.width == safe.width && (picture.midY < cut.midY) == (heading.midY < cut.midY) { return false }
                    print("Trail detail division \(cut), photo \(picture), heading \(heading)")
                }
            }
            #endif
            return true
        })
        let scroll = try #require(page.view.allSubviews(of: QuickLayoutScrollView.self).first)
        let preview = try #require(scroll.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "trail.preview" })
        scroll.scrollTo(.bottom, animated: false)
        print("Trail detail display \(window.bounds.size), orientation \(window.windowScene?.interfaceOrientation.rawValue ?? 0)")
        #expect(page.view.safeAreaLayoutGuide.layoutFrame.contains(preview.convert(preview.bounds, to: page.view)))
    }

    @Test(arguments: [UIContentSizeCategory.large, .accessibilityExtraLarge])
    func detailReflowsWithinChangingSafeArea(category: UIContentSizeCategory) async throws {
        let photo = try #require(JournalPhoto.collection.first)
        let page = TrailPlaceController(photo: photo)
        let window = try makeVisibleTestWindow(rootViewController: page, contentSizeCategory: category)
        defer { window.isHidden = true }
        let scroll = try #require(page.view.allSubviews(of: QuickLayoutScrollView.self).first)
        let title = try #require(scroll.allSubviews(of: UILabel.self).first { $0.text == photo.title })
        let preview = try #require(scroll.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == "trail.preview" })
        for (size, left, right) in [
            (CGSize(width: 1024, height: 680), 0.0, 50.0),
            (CGSize(width: 1024, height: 680), 350, 80),
            (CGSize(width: 375, height: 640), 0, 0),
            (CGSize(width: 820, height: 350), 40, 40),
            (CGSize(width: 1024, height: 680), 80, 350),
            (CGSize(width: 1024, height: 680), 0, 50)
        ] {
            window.frame.size = size
            page.view.frame = window.bounds
            page.additionalSafeAreaInsets = UIEdgeInsets(top: 44, left: left, bottom: 34, right: right)
            window.layoutIfNeeded()
            let safe = page.view.safeAreaLayoutGuide.layoutFrame
            func frame(_ view: UIView) -> CGRect { view.convert(view.bounds, to: page.view) }
            let sideBySide = safe.width >= 664 && !category.isAccessibilityCategory
            #expect(await waitForCondition {
                page.view.layoutIfNeeded()
                scroll.scrollTo(.top, animated: false)
                guard let image = page.view.allSubviews(of: UIImageView.self).first(where: { $0.image === photo.thumbnail })
                else { return false }
                let picture = frame(image), heading = frame(title)
                guard image.window === window, title.window === window,
                      !picture.isEmpty, !heading.isEmpty, picture.minY >= safe.minY,
                      [picture, heading].allSatisfy({ $0.minX >= safe.minX + 19 && $0.maxX <= safe.maxX - 19 })
                else { return false }
                return sideBySide ? (!picture.intersects(heading) && heading.midY < picture.maxY)
                    : heading.minY >= picture.maxY
            }, "safe \(safe), title \(frame(title)), side by side \(sideBySide)")
            scroll.scrollTo(.bottom, animated: false)
            let action = preview.convert(preview.bounds, to: page.view)
            #expect(action.width > 0 && action.minY >= safe.minY && action.maxY <= safe.maxY)
            #expect(action.minX >= safe.minX + 19 && action.maxX <= safe.maxX - 19)
        }
    }
}
