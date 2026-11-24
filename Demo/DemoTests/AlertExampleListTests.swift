import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

@MainActor
struct AlertExampleListTests {
    @available(iOS 26.0, *)
    @Test func pickerMountsItsTableOnlyWhileThePopoverIsInAWindow() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let rows = AlertExampleLocales.countries(phoneCodes: false)
        let picker = AlertExampleList(rows: rows) { _ in }
        let alert = AlertController(title: "Country or Region Picker", preferredStyle: .actionSheet)
        alert.panelWidth = .points(240)
        alert.contentViewController = picker
        alert.addAction(AlertAction(title: "Done"))
        alert.setPopoverAnchor(host.view, sourceRect: CGRect(
            x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1
        ))

        let planned = try #require(alert.prepareForPresentation(from: host))
        #expect(picker.view.allSubviews(of: UITableView.self).isEmpty)
        #expect(planned.contentSize.height == 264)

        let replacementRows = Array(rows.prefix(20))
        picker.setRows(replacementRows)
        #expect(picker.view.allSubviews(of: UITableView.self).isEmpty)

        await withCheckedContinuation { done in host.present(alert, animated: false) { done.resume() } }
        let table = try #require(picker.view.allSubviews(of: UITableView.self).first)
        #expect(table.window != nil)
        #expect(table.bounds.height == 220)
        #expect(await waitForCondition {
            table.numberOfSections == 1 && table.numberOfRows(inSection: 0) == replacementRows.count
        })
        #expect(table.rectForFooter(inSection: 0).height < 1)
        await withCheckedContinuation { done in host.dismiss(animated: false) { done.resume() } }
        #expect(table.superview == nil)
    }

    @available(iOS 26.0, *)
    @Test func nativePopoverFormsLeaveTheWidthUnspecified() throws {
        let host = AlertExamplesViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let source = UIView(frame: CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1))
        host.view.addSubview(source)

        for example in [AlertExamplesViewController.Example.textField, .login] {
            let scenario = host.scenario(for: example, imageMode: .grid, usesPopover: true)
            let form = try #require(scenario.content as? AlertExampleFields)
            let (alert, _) = host.makeNativeAlert(scenario, style: .actionSheet, source: source)
            alert.loadViewIfNeeded()
            form.loadViewIfNeeded()
            #expect(form.preferredContentSize.width == 0)
        }
    }

    @available(iOS 26.0, *)
    @Test func constrainedLocationPopoverKeepsDoneVisibleLikeUIKit() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        // 同一锚点分别留出充足空间、轻微压缩标题边距、压缩正文三种高度。
        for availableHeight: CGFloat in [560, 450, 380] {
            let anchor = CGRect(x: host.view.bounds.midX, y: host.view.safeAreaInsets.top + availableHeight,
                                width: 1, height: 1)
            var nativeFrames: [CGRect] = []
            for native in [true, false] {
                let picker = AlertExampleLocation { _ in }
                let controller: UIViewController
                if native {
                    let alert = UIAlertController(title: "Location Picker", message: nil, preferredStyle: .actionSheet)
                    // 与 Demo 的 UIKit 对照入口使用相同的嵌入方式。
                    alert.setValue(picker, forKey: "contentViewController")
                    alert.addAction(UIAlertAction(title: "Done", style: .default))
                    alert.popoverPresentationController?.sourceView = host.view
                    alert.popoverPresentationController?.sourceRect = anchor
                    controller = alert
                } else {
                    let alert = AlertController(title: "Location Picker", preferredStyle: .actionSheet)
                    alert.contentViewController = picker
                    alert.addAction(AlertAction(title: "Done"))
                    alert.setPopoverAnchor(host.view, sourceRect: anchor)
                    alert.prepareForPresentation(from: host)
                    controller = alert
                }
                controller.popoverPresentationController?.permittedArrowDirections = .down
                await withCheckedContinuation { done in host.present(controller, animated: false) { done.resume() } }
                controller.view.layoutIfNeeded()
                let labels = controller.view.allSubviews(of: UILabel.self)
                let action = try #require(labels.first { $0.text == "Done" && $0.window != nil })
                let title = try #require(labels.first { $0.text == "Location Picker" && $0.window != nil })
                let search = try #require(picker.view.allSubviews(of: UISearchBar.self).first)
                let ancestors = sequence(first: picker.view!, next: { $0.superview })
                let scroll = try #require(ancestors.compactMap { $0 as? UIScrollView }.first)
                let panel = controller.view.safeAreaLayoutGuide.layoutFrame
                let frames = [title, search, scroll, action].map {
                    $0.convert($0.bounds, to: controller.view).offsetBy(dx: -panel.minX, dy: -panel.minY)
                }
                if native {
                    nativeFrames = frames
                } else {
                    for (index, actual) in frames.enumerated() {
                        let expected = nativeFrames[index]
                        #expect(abs(actual.minY - expected.minY) <= 1, "height \(availableHeight), actual \(actual), UIKit \(expected)")
                        #expect(abs(actual.height - expected.height) <= 1, "height \(availableHeight), actual \(actual), UIKit \(expected)")
                    }
                }
                if availableHeight == 380 {
                    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                    }
                    Attachment.record(try #require(image.pngData()), named: native ? "UIKit-location.png" : "QuickLayoutKit-location.png")
                    let overflow = scroll.contentSize.height - scroll.bounds.height
                    #expect(overflow > 0)
                    let buttonFrame = action.convert(action.bounds, to: controller.view)
                    #expect(panel.contains(buttonFrame))
                    if !native {
                        let buttonAncestors = sequence(first: action as UIView, next: { $0.superview })
                        let button = try #require(buttonAncestors.compactMap { $0 as? UIButton }.first)
                        let point = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
                        let hit = try #require(controller.view.hitTest(point, with: nil))
                        #expect(hit.isDescendant(of: button))
                    }
                    scroll.setContentOffset(CGPoint(x: 0, y: overflow), animated: false)
                    #expect(action.convert(action.bounds, to: controller.view) == buttonFrame)
                    let choose = try #require(picker.view.allSubviews(of: UIButton.self).first {
                        $0.accessibilityIdentifier == "alerts.map.choose"
                    })
                    #expect(scroll.bounds.contains(choose.convert(choose.bounds, to: scroll)))
                }
                await withCheckedContinuation { done in host.dismiss(animated: false) { done.resume() } }
            }
        }
    }

    @available(iOS 26.0, *)
    @Test(.serialized, arguments: [true, false])
    func richTextPlacesDetailBelowActionWithBottomPadding(anchored: Bool) async throws {
        let host = AlertExamplesViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let source: UIView? = anchored
            ? UIView(frame: CGRect(x: host.view.bounds.midX, y: host.view.bounds.height * 0.8, width: 1, height: 1))
            : nil
        if let source { host.view.addSubview(source) }
        let style: UIAlertController.Style = anchored ? .actionSheet : .alert
        let scenario = host.scenario(for: .richText, imageMode: .grid, usesPopover: anchored)
        let title = try #require(scenario.actions.first?.title)
        let detail = try #require(scenario.detailMessage)

        for native in [true, false] {
            let controller: UIViewController
            if native {
                controller = host.makeNativeAlert(scenario, style: style, source: source).0
            } else {
                let alert = host.makeAlert(scenario, style: style, source: source)
                alert.prepareForPresentation(from: host)
                controller = alert
            }
            controller.popoverPresentationController?.permittedArrowDirections = .down
            await withCheckedContinuation { done in
                if let alert = controller as? UIAlertController {
                    host.presentNativeAlert(alert, detailMessage: detail, animated: true) { done.resume() }
                } else {
                    host.present(controller, animated: false) { done.resume() }
                }
            }
            defer { host.dismiss(animated: false) }
            controller.view.layoutIfNeeded()
            if anchored { #expect(controller.popoverPresentationController?.arrowDirection == .down) }

            let labels = controller.view.allSubviews(of: UILabel.self)
            let actionLabel = try #require(labels.first { $0.text == title && $0.window != nil })
            let detailLabel = try #require(labels.first { $0.text == detail && $0.window != nil })
            let detailFrame = detailLabel.convert(detailLabel.bounds, to: controller.view)
            let actionFrame = actionLabel.convert(actionLabel.bounds, to: controller.view)
            #expect(detailFrame.minY > actionFrame.maxY)
            let panel = try #require(detailLabel.superview)
            let footerFrame = detailLabel.convert(detailLabel.bounds, to: panel)
            #expect(panel.bounds.contains(footerFrame))
            #expect(abs(panel.bounds.maxY - footerFrame.maxY - 12) < 0.5, "native: \(native)")
            if !native {
                let ancestors = sequence(first: actionLabel as UIView, next: { $0.superview })
                let button = try #require(ancestors.compactMap { $0 as? UIButton }.first)
                let buttonFrame = button.convert(button.bounds, to: controller.view)
                #expect(detailFrame.minY > buttonFrame.maxY)
                let hit = try #require(controller.view.hitTest(CGPoint(x: buttonFrame.midX, y: buttonFrame.midY), with: nil))
                #expect(hit.isDescendant(of: button))
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            Attachment.record(try #require(image.pngData()), named: native ? "UIKit-rich-text.png" : "QuickLayoutKit-rich-text.png")
        }
    }

    @available(iOS 26.0, *)
    @Test func customContentPopoverActionFramesMatchUIKit() async throws {
        typealias Example = AlertExamplesViewController.Example
        let host = AlertExamplesViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let anchor = CGRect(x: host.view.bounds.midX, y: host.view.safeAreaInsets.top + 182, width: 1, height: 1)
        let examples: [Example] = [.date, .height, .calendar, .country, .phone, .currency, .contacts,
                                   .imagePicker, .photoLibrary, .color, .text, .attachments, .textField, .login]
        for example in examples {
            let modes: [AlertExamplesViewController.ImageMode] = example == .imagePicker ? [.grid, .multiple, .pages] : [.grid]
            for mode in modes {
                try await checkPopoverActions("\(example.rawValue) \(mode.rawValue)", host: host, anchor: anchor) {
                    var scenario = host.scenario(for: example, imageMode: mode, usesPopover: true)
                    // 使用同一布局和本地数据，避免布局测试访问系统图库或通讯录。
                    if example == .contacts { (scenario.content as? AlertExampleList)?.loadOnAppearance = nil }
                    if example == .photoLibrary || example == .attachments {
                        let photos = AlertExampleImages(items: [], multiple: true, paging: false) { _ in }
                        scenario.content = example == .attachments ? AlertExampleAttachments { _ in photos } : photos
                    }
                    return scenario
                }
            }
        }
    }

    @available(iOS 26.0, *)
    @Test func customHeaderPopoverActionFramesMatchUIKit() async throws {
        let host = AlertExamplesViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        for (count, shortHeader) in [(1, false), (2, false), (5, false), (5, true), (1, true)] {
            let anchor = CGRect(x: host.view.bounds.midX, y: host.view.safeAreaInsets.top + 280, width: 1, height: 1)
            try await checkPopoverActions("header, \(count) actions, short: \(shortHeader)", host: host, anchor: anchor) {
                AlertExamplesViewController.Scenario(
                    title: "Calendar", header: shortHeader ? AlertExampleContent(UIView(), height: 32) : AlertExampleCalendar(),
                    actions: (1...count).map { AlertAction(title: "Action \($0)") }
                )
            }
        }
    }

    @available(iOS 26.0, *)
    private func checkPopoverActions(_ name: String, host: AlertExamplesViewController, anchor: CGRect,
                                     makeScenario: () -> AlertExamplesViewController.Scenario) async throws {
        let expected = try await popoverActionPositions(makeScenario(), native: true, host: host, anchor: anchor)
        let actual = try await popoverActionPositions(makeScenario(), native: false, host: host, anchor: anchor)
        #expect(actual.count == expected.count)
        for (position, reference) in zip(actual, expected) {
            #expect(abs(position - reference) <= 1, "\(name): \(position), UIKit \(reference)")
        }
    }

    @available(iOS 26.0, *)
    private func popoverActionPositions(_ scenario: AlertExamplesViewController.Scenario, native: Bool,
                                        host: AlertExamplesViewController, anchor: CGRect) async throws -> [CGFloat] {
        let source = UIView(frame: anchor)
        host.view.addSubview(source)
        defer { source.removeFromSuperview() }
        let controller: UIViewController
        if native {
            controller = host.makeNativeAlert(scenario, style: .actionSheet, source: source).0
        } else {
            let alert = host.makeAlert(scenario, style: .actionSheet, source: source)
            alert.prepareForPresentation(from: host)
            controller = alert
        }
        controller.popoverPresentationController?.permittedArrowDirections = .down
        await withCheckedContinuation { done in host.present(controller, animated: false) { done.resume() } }
        defer { host.dismiss(animated: false) }
        controller.view.layoutIfNeeded()
        let panel = controller.view.safeAreaLayoutGuide.layoutFrame
        let content = try #require(scenario.header ?? scenario.content)
        let parent = try #require(content.view.superview)
        let ancestors = sequence(first: parent, next: { $0.superview })
        let scroll = try #require(ancestors.compactMap { $0 as? UIScrollView }.first)
        let actionTitles = scenario.actions.filter { $0.style != .cancel }.map(\.title)
        let labels = controller.view.allSubviews(of: UILabel.self)
        let buttons = try actionTitles.map { title in try #require(labels.first { $0.text == title && $0.window != nil }) }
        let firstLabel = try #require(buttons.first)
        let buttonAncestors = sequence(first: firstLabel as UIView, next: { $0.superview })
        let actionsScroll = try #require(buttonAncestors.compactMap { $0 as? UIScrollView }.first)
        #expect(actionsScroll !== scroll)
        var positions = [scroll.bounds.height, actionsScroll.bounds.height, actionsScroll.bounds.width]
        func recordButtons() {
            for label in buttons {
                positions.append(panel.maxY - label.convert(label.bounds, to: controller.view).midY)
            }
        }
        func checkHit(_ label: UILabel) throws {
            let frame = label.convert(label.bounds, to: controller.view)
            let point = CGPoint(x: frame.midX, y: frame.midY)
            #expect(panel.contains(point))
            if !native {
                let ancestors = sequence(first: label as UIView, next: { $0.superview })
                let button = try #require(ancestors.compactMap { $0 as? UIButton }.first)
                let hit = try #require(controller.view.hitTest(point, with: nil))
                #expect(hit.isDescendant(of: button))
            }
        }
        recordButtons()
        try checkHit(firstLabel)
        let overflow = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: overflow), animated: false)
        recordButtons()
        try checkHit(firstLabel)
        let actionOverflow = max(0, actionsScroll.contentSize.height - actionsScroll.bounds.height)
        actionsScroll.setContentOffset(CGPoint(x: 0, y: actionOverflow), animated: false)
        recordButtons()
        try checkHit(try #require(buttons.last))
        return positions
    }

    @Test func filteredContactsKeepTheirIdentityWhenRowsAreReplaced() async throws {
        typealias Row = AlertExampleList.Row
        let first = Row(id: "A", title: "Sam", detail: "123")
        let second = Row(id: "B", title: "Sam", detail: "123")
        let other = Row(id: "C", title: "Morgan", detail: nil)
        var selection: Row?
        let list = AlertExampleList { selection = $0 }
        list.setRows([first, other, second])
        let window = try makeVisibleTestWindow(rootViewController: list)
        defer { window.isHidden = true }
        list.view.layoutIfNeeded()
        let table = try #require(list.view.allSubviews(of: UITableView.self).first)
        let search = try #require(list.view.allSubviews(of: UISearchBar.self).first)
        search.text = "Sam"
        search.delegate?.searchBar?(search, textDidChange: "Sam")
        #expect(await waitForCondition { table.numberOfSections == 1 && table.numberOfRows(inSection: 0) == 2 })
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 1, section: 0))
        #expect(selection == second)

        let updated = Row(id: second.id, title: "Sam", detail: "456")
        list.setRows([updated, other, first])
        let firstPath = IndexPath(row: 0, section: 0)
        #expect(await waitForCondition {
            table.layoutIfNeeded()
            let content = table.cellForRow(at: firstPath)?.contentConfiguration as? UIListContentConfiguration
            return table.numberOfRows(inSection: 0) == 2 && content?.secondaryText == "456"
        })
        table.delegate?.tableView?(table, didSelectRowAt: firstPath)
        #expect(selection == updated)
    }
}
