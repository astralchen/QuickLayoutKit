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

    private let viewModel: CounterViewModel

    let counterLabel = UILabel()
    let incrementButton = UIButton(configuration: .plain())
    let decrementButton = UIButton(configuration: .plain())

    convenience init() {
        self.init(viewModel: CounterViewModel())
    }

    init(viewModel: CounterViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = CounterViewModel()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        counterLabel.font = .systemFont(ofSize: 48, weight: .bold)
        counterLabel.textAlignment = .center

        incrementButton.addTarget(self, action: #selector(increment), for: .touchUpInside)

        decrementButton.addTarget(self, action: #selector(decrement), for: .touchUpInside)

        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.reloadLocalizedContent()
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
        viewModel.increment()
    }

    @objc private func decrement() {
        viewModel.decrement()
    }

    private func render(_ state: CounterViewModel.State) {
        counterLabel.text = state.countText
        updateTitle(state.incrementTitle, for: incrementButton)
        updateTitle(state.decrementTitle, for: decrementButton)
        setNeedsQuickLayout()
    }

    private func updateTitle(_ title: String, for button: UIButton) {
        guard var configuration = button.configuration else { return }
        configuration.title = title
        button.configuration = configuration
    }
}

#Preview {
   UINavigationController(rootViewController: CounterViewController())
}
