import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct AlertPublicAPITests {
    @Test(arguments: [UIAlertController.Style.alert, .actionSheet])
    func preferredActionAndIdentifierFollowButtonUpdates(style: UIAlertController.Style) throws {
        let alert = AlertController(preferredStyle: style)
        let save = AlertAction(title: "Save")
        let delete = AlertAction(title: "Delete", style: .destructive)
        let identifiable: any UIAccessibilityIdentification = save
        #expect(identifiable.accessibilityIdentifier == nil)
        #expect(alert.preferredAction == nil)
        identifiable.accessibilityIdentifier = "save"
        delete.accessibilityIdentifier = "delete"
        alert.addAction(save)
        alert.addAction(delete)
        alert.preferredAction = save
        #expect(!alert.isViewLoaded)
        alert.loadViewIfNeeded()

        func button(_ identifier: String) throws -> UIButton {
            try #require(alert.view.allSubviews(of: UIButton.self).first { $0.accessibilityIdentifier == identifier })
        }
        func handlesReturn() -> Bool {
            alert.keyCommands?.contains { $0.input == "\r" && $0.modifierFlags.isEmpty } == true
        }

        let supportsShortcut: Bool
        if #available(iOS 27, *), alert.traitCollection.userInterfaceIdiom == .pad {
            supportsShortcut = false
        } else {
            supportsShortcut = style == .alert
        }
        let firstButton = try button("save")
        identifiable.accessibilityIdentifier = "document.save"
        #expect(firstButton.accessibilityIdentifier == "document.save")
        if #available(iOS 26, *) {
            #expect(firstButton.configuration?.baseBackgroundColor == .tintColor)
            #expect(firstButton.configuration?.baseForegroundColor == .white)
        }
        #expect(handlesReturn() == supportsShortcut)
        save.isEnabled = false
        #expect(handlesReturn() == supportsShortcut)
        save.isEnabled = true
        #expect(handlesReturn() == supportsShortcut)

        alert.preferredAction = delete
        #expect(alert.preferredAction === delete)
        let rebuilt = try button("document.save")
        #expect(rebuilt !== firstButton)
        if #available(iOS 26, *) {
            #expect(rebuilt.configuration?.baseBackgroundColor == .secondarySystemFill)
            let destructive = try button("delete")
            #expect(destructive.configuration?.baseForegroundColor == .systemRed)
        }
        identifiable.accessibilityIdentifier = nil
        #expect(rebuilt.accessibilityIdentifier == nil)
        alert.preferredAction = nil
        #expect(!handlesReturn())
    }

    @Test func returnCommandUsesTheResponderChainAndDismissesOnce() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        let previousKeyWindow = window.windowScene?.windows.first(where: \.isKeyWindow)
        window.makeKey()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let alert = AlertController(preferredStyle: .alert)
        var saves = 0
        let save = AlertAction(title: "Save") { _ in saves += 1 }
        alert.addAction(save)
        await withCheckedContinuation { done in host.presentAlert(alert, animated: false) { done.resume() } }
        defer { host.dismiss(animated: false) }
        alert.preferredAction = save
        let shortcut = alert.keyCommands?.first { $0.input == "\r" && $0.modifierFlags.isEmpty }
        if #available(iOS 27, *), alert.traitCollection.userInterfaceIdiom == .pad {
            #expect(shortcut == nil)
            return
        }
        let command = try #require(shortcut)
        let activate = try #require(command.action)
        func dispatchReturn() {
            _ = UIApplication.shared.sendAction(activate, to: nil, from: command, for: nil)
        }
        save.isEnabled = false
        save.perform()
        #expect(saves == 0)
        dispatchReturn()
        dispatchReturn()
        #expect(await waitForCondition { host.presentedViewController == nil && saves == 1 })
    }

    @Test func presentedAlertOffersTheSameReturnShortcutAsUIKit() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        func hasReturn(_ controller: UIViewController) -> Bool {
            controller.keyCommands?.contains { $0.input == "\r" && $0.modifierFlags.isEmpty } == true
        }
        let native = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        let nativeSave = UIAlertAction(title: "Save", style: .default)
        native.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        native.addAction(nativeSave)
        native.preferredAction = nativeSave
        await withCheckedContinuation { done in host.present(native, animated: false) { done.resume() } }
        let expected = hasReturn(native)
        await withCheckedContinuation { done in native.dismiss(animated: false) { done.resume() } }

        let alert = AlertController(preferredStyle: .alert)
        let save = AlertAction(title: "Save")
        alert.addAction(AlertAction(title: "Cancel", style: .cancel))
        alert.addAction(save)
        alert.preferredAction = save
        await withCheckedContinuation { done in host.presentAlert(alert, animated: false) { done.resume() } }
        #expect(hasReturn(alert) == expected)
        await withCheckedContinuation { done in alert.dismiss(animated: false) { done.resume() } }
    }

    @Test func implicitReturnTracksEnabledChoicesAfterClearingThePreference() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        let alert = AlertController(preferredStyle: .alert)
        var chosen: AlertAction?
        let cancel = AlertAction(title: "Cancel", style: .cancel) { chosen = $0 }
        let save = AlertAction(title: "Save") { chosen = $0 }
        let other = AlertAction(title: "Other") { chosen = $0 }
        [cancel, save, other].forEach { alert.addAction($0) }
        alert.preferredAction = other
        alert.preferredAction = nil
        func returnCommand() -> UIKeyCommand? {
            alert.keyCommands?.first { $0.input == "\r" && $0.modifierFlags.isEmpty }
        }
        #expect(returnCommand() == nil)
        other.isEnabled = false
        await withCheckedContinuation { done in host.presentAlert(alert, animated: false) { done.resume() } }
        alert.addTextField { $0.returnKeyType = .done }
        let field = try #require(alert.textFields?.first)
        field.sendActions(for: .editingDidEndOnExit)
        #expect(await waitForCondition { host.presentedViewController == nil && chosen === save })
        #expect(alert.preferredAction == nil)
    }

    @Test func textFieldReturnAdvancesThenSubmitsThePreferredActionOnce() async throws {
        let host = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: host)
        let previousKeyWindow = window.windowScene?.windows.first(where: \.isKeyWindow)
        window.makeKey()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        let alert = AlertController(preferredStyle: .alert)
        var saves = 0
        let save = AlertAction(title: "Save") { _ in saves += 1 }
        alert.addAction(save)
        alert.preferredAction = save
        alert.addTextField { $0.returnKeyType = .next }
        alert.addTextField { $0.returnKeyType = .done }
        await withCheckedContinuation { done in host.presentAlert(alert, animated: false) { done.resume() } }
        let first = try #require(alert.textFields?.first)
        let last = try #require(alert.textFields?.last)
        first.sendActions(for: .editingDidEndOnExit)
        #expect(last.isFirstResponder && saves == 0)
        last.sendActions(for: .editingDidEndOnExit)
        #expect(await waitForCondition { host.presentedViewController == nil && saves == 1 })
    }

    @Test func actionSupportsUIKitInitializerSignature() {
        let makeAction = AlertAction.init(title:style:handler:)
        var performed: AlertAction?
        let action = makeAction("Delete", .destructive) { performed = $0 }
        #expect(action.title == "Delete")
        #expect(action.attributedTitle == nil)
        #expect(action.style == .destructive)
        #expect(action.isEnabled)
        action.perform()
        #expect(performed === action)

        let untitled = AlertAction(title: nil, style: .cancel)
        #expect(untitled.title == nil)
        untitled.perform()
    }

    @Test func attributedActionUsesItsOwnTitleAndAppearance() {
        var title = AttributedString("Archive")
        title.foregroundColor = UIColor.systemIndigo
        let icon = UIImage(systemName: "archivebox")
        var performed: AlertAction?
        let action = AlertAction(
            attributedTitle: title,
            appearance: .init(image: icon, titleColor: .systemBlue, cornerStyle: .small)
        ) { performed = $0 }

        #expect(action.title == nil)
        #expect(action.attributedTitle == title)
        #expect(action.image === icon)
        #expect(action.titleColor == .systemBlue)
        #expect(action.cornerStyle == .small)
        action.perform()
        #expect(performed === action)
    }

    @Test func subclassesCanCustomizeActionsAndTextFields() {
        let alert = TextEntryAlert(preferredStyle: .alert)
        let action = SubmitAction(title: "Submit")
        alert.addAction(action)
        alert.addTextField { $0.placeholder = "Name" }

        #expect(alert.actions.first === action)
        #expect(action.title == "SUBMIT")
        #expect(action.isEnabled == false)
        #expect(alert.textFields?.first?.placeholder == "Name")
        #expect(alert.textFields?.first?.returnKeyType == .done)
    }
}

private final class TextEntryAlert: AlertController {
    override func addAction(_ action: AlertAction) {
        action.isEnabled = false
        super.addAction(action)
    }

    override func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        super.addTextField { field in
            field.returnKeyType = .done
            configurationHandler?(field)
        }
    }
}

private final class SubmitAction: AlertAction {
    override var title: String? { super.title?.uppercased() }
}
