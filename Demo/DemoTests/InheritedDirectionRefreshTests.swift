import UIKit
import Testing
import QuickLayoutKit
import AppLocalization
@testable import Demo

@MainActor
@Suite(.serialized)
struct InheritedDirectionRefreshTests {
    @Test func menuParagraphsFollowInheritedDirectionWithoutContentReload() async throws {
        let controller = MainViewController()
        let host = try MediaDirectionTestHost(content: controller)
        defer { host.window.isHidden = true }
        for semantic: UISemanticContentAttribute in [.forceLeftToRight, .forceRightToLeft, .forceLeftToRight, .unspecified] {
            host.setBoundary(semantic)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
            let collection = controller.collectionView
            collection.layoutIfNeeded()
            let rtl = collection.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let cells = collection.visibleCells.compactMap { $0 as? UICollectionViewListCell }
            try #require(!cells.isEmpty)
            for cell in cells {
                let content = try #require(cell.contentConfiguration as? UIListContentConfiguration)
                let text = try #require(content.attributedText)
                let style = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                #expect(style.alignment == (rtl ? .right : .left))
            }
            #expect(collection.semanticContentAttribute == .unspecified)
        }
    }

    @Test func navigationDiagnosticsFollowLocalDirectionWithoutChangingLanguage() throws {
        let controller = DirectionalNavigationViewController()
        let host = try MediaDirectionTestHost(content: controller)
        defer { host.window.isHidden = true }
        for semantic: UISemanticContentAttribute in [.forceRightToLeft, .forceLeftToRight, .unspecified] {
            host.setBoundary(semantic)
            let direction = controller.view.effectiveUserInterfaceLayoutDirection
            let edgeKey = direction == .rightToLeft ? "navigation.edge.right" : "navigation.edge.left"
            let expected = Localization.text("navigation.edge.summary", Localization.text(edgeKey),
                DirectionalLayout.backChevronSystemName(layoutDirection: direction))
            #expect(controller.view.allSubviews(of: UILabel.self).contains { $0.text == expected })
            #expect(controller.view.semanticContentAttribute == .unspecified)
        }
    }

    @Test func nativeDrawingAndPreviewControlsRefreshInheritedDirection() throws {
        guard #available(iOS 26.0, *) else { return }
        let host = try MediaDirectionTestHost()
        defer { host.window.isHidden = true }
        let waveform = WaveformView(frame: CGRect(x: 0, y: 50, width: 80, height: 30))
        waveform.samples = Array(repeating: 1, count: 8)
        waveform.barWidth = 4
        waveform.fillsAvailableWidth = true
        waveform.progress = 0.25
        waveform.playedColor = .red
        waveform.unplayedColor = .blue
        let link = LinkPreviewView(link: .init(url: URL(string: "https://example.com")!, title: "Example"))
        link.frame = CGRect(x: 0, y: 100, width: 220, height: 70)
        let badge = LivePhotoBadgeButton(frame: CGRect(x: 0, y: 180, width: 120, height: 30))
        for view in [waveform, link, badge] { host.content.view.addSubview(view) }
        let arrow = try #require(badge.subviews.compactMap { $0 as? UIImageView }.first)
        for semantic: UISemanticContentAttribute in [.forceLeftToRight, .forceRightToLeft, .forceLeftToRight, .unspecified] {
            host.setBoundary(semantic)
            let rtl = host.content.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            link.layoutIfNeeded()
            badge.layoutIfNeeded()
            for label in link.allSubviews(of: UILabel.self) {
                #expect(label.textAlignment == (rtl ? .right : .left))
            }
            #expect(rtl ? arrow.frame.midX < badge.bounds.midX : arrow.frame.midX > badge.bounds.midX)
            waveform.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: waveform.bounds, format: format).image {
                waveform.layer.render(in: $0.cgContext)
            }
            let pixel = try #require(image.cgImage?.cropping(to: CGRect(x: rtl ? 78 : 2, y: 15, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            rgba.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            #expect(rgba[0] > 200 && rgba[2] < 30, "已播放波形应随继承方向换边：\(rgba)")
            #expect(waveform.semanticContentAttribute == .unspecified)
        }
    }

    @Test func localizedPagesRefreshLayoutsWithoutLanguageCallbacks() throws {
        for controller in [UIKitLocalizationShowcaseViewController(), ContentConfigurationCollectionViewController()] as [UIViewController] {
            let host = try MediaDirectionTestHost(content: controller)
            defer { host.window.isHidden = true }
            host.setBoundary(.forceLeftToRight)
            let collection = try #require(controller.view.allSubviews(of: UICollectionView.self).first)
            for semantic: UISemanticContentAttribute in [.forceRightToLeft, .forceLeftToRight, .forceRightToLeft, .unspecified] {
                let oldDirection = collection.effectiveUserInterfaceLayoutDirection
                let oldLayout = collection.collectionViewLayout
                host.setBoundary(semantic)
                controller.view.layoutIfNeeded()
                collection.layoutIfNeeded()
                #expect(collection.semanticContentAttribute == .unspecified)
                #expect(controller.view.semanticContentAttribute == .unspecified)
                if collection.effectiveUserInterfaceLayoutDirection != oldDirection {
                    #expect(collection.collectionViewLayout !== oldLayout)
                }
                let stable = collection.collectionViewLayout
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                #expect(collection.collectionViewLayout === stable)
            }
        }
    }

    @Test func independentChatListsFollowTheirInheritedDirection() throws {
        let host = try MediaDirectionTestHost()
        defer { host.window.isHidden = true }
        let conversation = ConversationView()
        let room = RoomPublicChatView(frame: .zero)
        for view in [conversation, room] as [UIView] {
            view.frame = CGRect(x: 0, y: 60, width: 320, height: 240)
            host.content.view.addSubview(view)
        }
        host.setBoundary(.forceLeftToRight)
        for semantic: UISemanticContentAttribute in [.forceRightToLeft, .forceLeftToRight, .forceRightToLeft, .unspecified] {
            let pairs: [(UIView, UICollectionView)] = [(conversation, conversation.collectionView), (room, room.collectionView)]
            let previous = pairs.map { ($0.1.effectiveUserInterfaceLayoutDirection, $0.1.collectionViewLayout) }
            host.setBoundary(semantic)
            for (index, pair) in pairs.enumerated() {
                pair.0.layoutIfNeeded()
                pair.1.layoutIfNeeded()
                #expect(pair.1.semanticContentAttribute == .unspecified)
                if pair.1.effectiveUserInterfaceLayoutDirection != previous[index].0 {
                    #expect(pair.1.collectionViewLayout !== previous[index].1)
                }
                let stable = pair.1.collectionViewLayout
                pair.0.setNeedsLayout()
                pair.0.layoutIfNeeded()
                #expect(pair.1.collectionViewLayout === stable)
            }
        }
    }

    @Test func composerRefreshesAttachmentsWithoutChangingSelection() throws {
        guard #available(iOS 26.0, *) else { return }
        let host = try MediaDirectionTestHost()
        defer { host.window.isHidden = true }
        let composer = ComposerView(frame: CGRect(x: 0, y: 60, width: 360, height: 180))
        composer.configure(strings: ConversationPreviewData.composerStrings)
        host.content.view.addSubview(composer)
        composer.insertDocument(.init(attachment: .link(.init(url: URL(string: "https://example.com")!, title: "Example"))))
        let editor = composer.textView
        let attachment = try #require(composer.textAttachments.values.first)
        let selection = editor.selectedRange
        for semantic: UISemanticContentAttribute in [.forceRightToLeft, .forceLeftToRight, .unspecified] {
            host.setBoundary(semantic)
            composer.layoutIfNeeded()
            #expect(attachment.direction == editor.effectiveUserInterfaceLayoutDirection)
            #expect(composer.textView === editor)
            #expect(editor.selectedRange == selection)
            #expect(editor.semanticContentAttribute == .unspecified)
        }
        host.setBoundary(.forceRightToLeft)
        for semantic: UISemanticContentAttribute in [.forceLeftToRight, .playback, .spatial, .unspecified] {
            editor.semanticContentAttribute = semantic
            editor.layoutIfNeeded()
            #expect(attachment.direction == editor.effectiveUserInterfaceLayoutDirection)
            #expect(editor.selectedRange == selection)
            #expect(editor.semanticContentAttribute == semantic)
        }
    }

    @Test func waterfallRefreshesInheritedDirectionWithoutManualInvalidation() async throws {
        let host = try MediaDirectionTestHost()
        defer { host.window.isHidden = true }
        let source = WaterfallLayoutTestSource(counts: [4])
        let layout = source.makeLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 80, width: 360, height: 240), collectionViewLayout: layout)
        collection.dataSource = source
        collection.delegate = source
        host.content.view.addSubview(collection)
        collection.reloadData()
        for semantic: UISemanticContentAttribute in [.forceLeftToRight, .forceRightToLeft, .forceLeftToRight, .unspecified] {
            host.setBoundary(semantic)
            collection.layoutIfNeeded()
            let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let second = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
            let rtl = collection.effectiveUserInterfaceLayoutDirection == .rightToLeft
            #expect(rtl ? first.center.x > second.center.x : first.center.x < second.center.x)
            try await Task.sleep(for: .milliseconds(30))
            collection.layoutIfNeeded()
            let firstCell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            let secondCell = try #require(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
            #expect(rtl ? firstCell.center.x > secondCell.center.x : firstCell.center.x < secondCell.center.x)
            #expect(collection.semanticContentAttribute == .unspecified)
            #expect(collection.collectionViewLayout === layout)
        }
    }

    @Test func gradientRespondsToDirectionWithoutColorOrSizeChanges() throws {
        let host = try MediaDirectionTestHost()
        defer { host.window.isHidden = true }
        let gradient = QuickLayoutLinearGradientView(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        host.content.view.addSubview(gradient)
        gradient.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        host.setBoundary(.forceLeftToRight)
        let layer = try #require(gradient.layer as? CAGradientLayer)
        for rtl in [true, false, true] {
            // 仅提交 trait 更新，不靠额外 layoutIfNeeded 掩盖图层刷新遗漏。
            host.content.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
            host.content.updateTraitsIfNeeded()
            gradient.updateTraitsIfNeeded()
            #expect(layer.startPoint.x == (rtl ? 1 : 0))
            #expect(layer.endPoint.x == (rtl ? 0 : 1))
            #expect(gradient.semanticContentAttribute == .unspecified)
        }
    }
}
