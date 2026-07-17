//
//  HorizontalScrollViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

class HorizontalScrollViewViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.horizontalScroll.title" }

    let scrollView = QuickLayoutScrollView(.horizontal)

    let views: [UIView] =  {

        let colors: [UIColor] = [.systemRed, .systemPink, .systemOrange, .systemPurple, .systemCyan]

        return (1...10).map { _ in
            let view = UIView()
            view.backgroundColor = colors.randomElement()
            view.layer.cornerRadius = 16
            return view
        }

    }()

    override var body: Layout {

        ScrollView(scrollView, .horizontal) {
            HStack(spacing: 16) {
                ForEach(views) { view in
                    view
                        .frame(width: 200)

                }
            }
            .padding(16)
            .padding(view.quickLayoutSafeAreaInsets)

        }

    }


    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .systemGray6
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        prepareInitialScrollPosition()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        scrollView.semanticContentAttribute = direction.appLayoutDirection.semanticContentAttribute
        scrollView.scrollTo(.leading, animated: false)
    }

    private func prepareInitialScrollPosition() {
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            scrollView.scrollTo(.leading, animated: false)
            scrollView.layoutIfNeeded()
        }
    }

}

#Preview {
    UINavigationController(rootViewController: HorizontalScrollViewViewController())
}
