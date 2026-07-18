//
//  CounterViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import QuickLayout
import QuickLayoutKit

class CounterViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.counter.title" }

    private var count = 0 {
        didSet {
            updateLabels()
            setNeedsQuickLayout()
        }
    }

    let counterLabel = UILabel()
    let incrementButton = UIButton(type: .system)
    let decrementButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        counterLabel.font = .systemFont(ofSize: 48, weight: .bold)
        counterLabel.textAlignment = .center

        incrementButton.addTarget(self, action: #selector(increment), for: .touchUpInside)

        decrementButton.addTarget(self, action: #selector(decrement), for: .touchUpInside)

        updateLabels()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        incrementButton.setTitle(DemoLocalization.text("counter.increment"), for: .normal)
        decrementButton.setTitle(DemoLocalization.text("counter.decrement"), for: .normal)
    }

    override var body: Layout {
        VStack(alignment: .center, spacing: 32) {
            Spacer()

            counterLabel

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    decrementButton
                    incrementButton
                }

                VStack(spacing: 12) {
                    decrementButton
                        .resizable(axis: .horizontal)
                        .frame(height: 44)
                    incrementButton
                        .resizable(axis: .horizontal)
                        .frame(height: 44)
                }
            }

            Spacer()
        }
        .safeAreaPadding(24)
    }

    @objc private func increment() {
        count += 1
    }

    @objc private func decrement() {
        count -= 1
    }

    private func updateLabels() {
        counterLabel.text = "\(count)"
    }
}

#Preview {
   UINavigationController(rootViewController: CounterViewController())
}
