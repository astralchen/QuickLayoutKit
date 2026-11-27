import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct LocalizedControlTests {
    @Test func placeholderDirectionDoesNotChangeEditingState() async throws {
        let controller = UIViewController()
        controller.overrideUserInterfaceStyle = .light
        controller.view.backgroundColor = .white
        let field = LocalizedTextField(frame: CGRect(x: 20, y: 60, width: 320, height: 44))
        field.font = .systemFont(ofSize: 20)
        field.placeholder = "الاسم"
        controller.view.addSubview(field)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        for direction: UIUserInterfaceLayoutDirection in [.rightToLeft, .leftToRight, .rightToLeft] {
            applyTestLayoutDirection(direction, to: controller)
            field.setNeedsLayout(); field.layoutIfNeeded(); field.setNeedsDisplay()
            #expect(field.textAlignment == (direction == .rightToLeft ? .right : .left))
            try await Task.sleep(for: .milliseconds(100))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: field.bounds, format: format).image { _ in field.drawHierarchy(in: field.bounds, afterScreenUpdates: true) }
            let pixels = try rgba(image)
            let xs = (0..<320).filter { x in (0..<44).contains { y in
                let i = (y * 320 + x) * 4
                return pixels[i + 3] > 20 && pixels[i] < 230
            } }
            let minX = try #require(xs.min()), maxX = try #require(xs.max())
            #expect(direction == .rightToLeft ? minX > 160 : maxX < 160, "placeholder direction=\(direction.rawValue), ink=\(minX)...\(maxX)")
        }
        try #require(field.becomeFirstResponder())
        field.text = "draft@example.com"
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 3))
        field.selectedTextRange = field.textRange(from: start, to: start)
        field.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
        let draft = field.text
        let selection = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) }
        applyTestLayoutDirection(.leftToRight, to: controller)
        field.layoutIfNeeded()
        #expect(field.text == draft)
        #expect(field.isFirstResponder)
        #expect(field.markedTextRange != nil)
        #expect(field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) } == selection)
        #expect(field.textAlignment == .left)
        field.unmarkText()
    }

    @Test func emptyCaretFollowsDirectionAfterTypingAndClearing() async throws {
        let controller = UIViewController()
        let field = LocalizedTextField(frame: CGRect(x: 20, y: 60, width: 320, height: 44))
        field.placeholder = "الاسم"
        controller.view.addSubview(field)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { field.resignFirstResponder(); window.isHidden = true }
        for direction: UIUserInterfaceLayoutDirection in [.rightToLeft, .leftToRight, .rightToLeft] {
            applyTestLayoutDirection(direction, to: controller)
            field.layoutIfNeeded()
            #expect(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(100))
            func checkCaret() throws {
                let range = try #require(field.selectedTextRange)
                let caret = field.convert(field.caretRect(for: range.start), from: field.textInputView)
                #expect(direction == .rightToLeft ? caret.midX > 280 : caret.midX < 40,
                        "direction=\(direction.rawValue), caret=\(caret)")
            }
            try checkCaret()
            for input in ["433", "draft@example.com", "مرحبا"] {
                field.insertText(input)
                #expect(field.text == input)
                for _ in input { field.deleteBackward() }
                #expect(field.text?.isEmpty == true)
                field.layoutIfNeeded()
                try checkCaret()
            }
            #expect(field.semanticContentAttribute == .unspecified)
        }
        // 显式居中与相同占位文字、相同编辑过程的原生输入框比较。
        // 原生空文本光标位置也受占位文字宽度影响，不等于 bounds.midX。
        let native = UITextField(frame: field.frame)
        native.placeholder = field.placeholder
        controller.view.addSubview(native)
        native.textAlignment = .right
        native.becomeFirstResponder()
        native.insertText("مرحبا")
        for _ in "مرحبا" { native.deleteBackward() }
        native.textAlignment = .center
        field.textAlignment = .center
        applyTestLayoutDirection(.leftToRight, to: controller)
        native.layoutIfNeeded()
        field.layoutIfNeeded()
        #expect(field.textAlignment == .center)
        try await Task.sleep(for: .milliseconds(100))
        let nativeCaret = native.convert(native.caretRect(for: native.beginningOfDocument), from: native.textInputView)
        try #require(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(100))
        let caret = field.convert(field.caretRect(for: field.beginningOfDocument), from: field.textInputView)
        #expect(abs(caret.midX - nativeCaret.midX) < 2, "localized=\(caret), native=\(nativeCaret)")
    }

    @Test func controlsRenderAcrossLanguageRoundTrips() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en") }
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        controller.overrideUserInterfaceStyle = .light
        let slider = LocalizedSlider(frame: CGRect(x: 20, y: 30, width: 400, height: 40))
        slider.tintColor = .magenta
        slider.value = 0.3
        let button = LocalizedButton(type: .system)
        button.frame = CGRect(x: 20, y: 100, width: 400, height: 50)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Button"
        configuration.image = UIImage(systemName: "arrow.forward")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 12
        button.configuration = configuration
        var activations = 0
        button.addAction(UIAction { _ in activations += 1 }, for: .touchUpInside)
        var sliderChanges = 0
        slider.addAction(UIAction { _ in sliderChanges += 1 }, for: .valueChanged)
        controller.view.addSubview(slider)
        controller.view.addSubview(button)
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 440, height: 240))
        defer { window.isHidden = true }
        Localization.register(window: window)
        defer { Localization.unregister(window: window) }
        for (index, locale) in ["zh-Hans", "ar", "zh-Hans", "ar", "en"].enumerated() {
            Localization.setLocale(identifier: locale)
            Localization.synchronize(window: window)
            controller.view.layoutIfNeeded()
            slider.setNeedsLayout(); slider.layoutIfNeeded()
            button.setNeedsLayout(); button.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            let rtl = locale == "ar"
            #expect(slider.semanticContentAttribute == .unspecified)
            #expect(button.semanticContentAttribute == .unspecified)
            #expect(slider.value == 0.3)
            let icon = try #require(button.imageView)
            let title = try #require(button.titleLabel)
            let iconX = icon.convert(icon.bounds, to: button).midX
            let titleX = title.convert(title.bounds, to: button).midX
            #expect(rtl ? iconX > titleX : iconX < titleX)
            button.sendActions(for: .touchUpInside)
            slider.slider.sendActions(for: .valueChanged)
            #expect(activations == index + 1)
            #expect(sliderChanges == index + 1)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: slider.bounds, format: format).image { _ in
                slider.drawHierarchy(in: slider.bounds, afterScreenUpdates: true)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixed-slider-\(index).png")
            try image.pngData()?.write(to: url)
            print("DIRECTION-EVIDENCE \(url.path)")
            let pixels = try rgba(image)
            // 30% 时填充必须接在对应的起点；旧轨道缓存会使 RTL 的两个断言同时失败。
            func filled(_ x: Int) -> Bool {
                let offset = (20 * 400 + x) * 4
                return pixels[offset] > 180 && pixels[offset + 1] < 100 && pixels[offset + 2] > 180
            }
            #expect(filled(rtl ? 380 : 20))
            #expect(!filled(rtl ? 20 : 380))
        }
        let old = slider.slider
        slider.semanticContentAttribute = .playback
        slider.layoutIfNeeded()
        #expect(slider.effectiveUserInterfaceLayoutDirection == .leftToRight)
        slider.semanticContentAttribute = .unspecified
        slider.layoutIfNeeded()
        #expect(slider.slider === old) // 最后一个语言是 LTR，不需要替换。
    }

    @Test func localizedParagraphsRenderAtLeadingAndPreserveExplicitAlignment() throws {
        let parent = UIViewController()
        let label = LocalizedLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        label.font = .systemFont(ofSize: 24)
        label.textColor = .black
        label.numberOfLines = 0
        parent.view.addSubview(label)
        let window = try makeVisibleTestWindow(rootViewController: parent)
        defer { window.isHidden = true }
        for direction: UIUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft, .leftToRight] {
            applyTestLayoutDirection(direction, to: parent)
            label.text = direction == .rightToLeft ? "توضح هذه الصفحة\nالعناصر" : "This page explains\nElements"
            label.setNeedsLayout(); label.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: label.bounds, format: format).image { _ in label.drawText(in: label.bounds) }
            let pixels = try rgba(image)
            let xs = (0..<320).filter { x in (45..<80).contains { y in pixels[(y * 320 + x) * 4 + 3] > 20 } }
            let minX = try #require(xs.min()), maxX = try #require(xs.max())
            #expect(direction == .rightToLeft ? minX > 160 : maxX < 160)
            #expect(label.semanticContentAttribute == .unspecified)
        }
        label.textAlignment = .center
        applyTestLayoutDirection(.rightToLeft, to: parent)
        label.layoutIfNeeded()
        #expect(label.textAlignment == .center)
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try #require(CGContext(data: &pixels, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return pixels
    }
}
