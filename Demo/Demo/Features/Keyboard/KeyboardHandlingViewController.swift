//
//  KeyboardHandlingViewController.swift
//  Demo
//
//  Created by Sondra on 2026/1/27.
//

import UIKit
import QuickLayout
import QuickLayoutKit

class KeyboardHandlingViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.keyboard.title" }

    private let keyboardView = AnimatedKeyboardResponsiveView()

    override var body: any Layout {
        ZStack {
            keyboardView
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        keyboardView.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        keyboardView.applyLayoutDirection(direction)
        setNeedsQuickLayout()
    }

}



#Preview {
    UINavigationController(rootViewController: KeyboardHandlingViewController())
}
