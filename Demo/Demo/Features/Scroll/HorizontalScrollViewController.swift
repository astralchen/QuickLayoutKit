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
                ForEach(views) { cardView in
                    cardView
                        .resizable()
                        .containerRelativeFrame(
                            .horizontal,
                            count: 3,
                            span: 2,
                            spacing: 16
                        )
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            min(24, max(12, geometry.size.width * 0.08))
                        } action: { [weak cardView] cornerRadius in
                            cardView?.layer.cornerRadius = cornerRadius
                        }
                }
            }
        }
        .contentMargins(.horizontal, 16)
        .safeAreaPadding(.horizontal, 0)
        .safeAreaPadding(.vertical, 16)
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
