//
//  IMessageChatViewController.swift
//  Demo
//

import Combine
import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

@available(iOS 26.0, *)
final class IMessageChatViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.imessage.title" }

    let viewModel: IMessageChatViewModel
    let conversationView = IMessageConversationView()
    let composerView = IMessageChatComposerView()
    let contactTitleView = IMessageContactTitleView(frame: .zero)

    private let keyboardObserver = QuickLayoutKeyboardObserver()
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(viewModel: IMessageChatViewModel())
    }

    init(viewModel: IMessageChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = IMessageChatViewModel()
        super.init(coder: coder)
    }

    override var body: Layout {
        VStack(spacing: 0) {
            conversationView
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            composerView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
        .safeAreaPadding(.all, 0)
    }

    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        super.viewDidLoad()

        contactTitleView.sizeToFit()
        navigationItem.titleView = contactTitleView
        view.backgroundColor = .systemBackground
        configureInteractions()
        bindViewModel()
        observeKeyboard()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        contactTitleView.configure(
            subtitle: DemoLocalization.text("imessage.contact.subtitle")
        )
        contactTitleView.sizeToFit()
        composerView.configure(
            placeholder: DemoLocalization.text("imessage.composer.placeholder"),
            sendAccessibilityLabel: DemoLocalization.text(
                "imessage.composer.send"
            )
        )
        viewModel.refreshLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticAttribute = direction.appLayoutDirection
            .semanticContentAttribute
        contactTitleView.semanticContentAttribute = semanticAttribute
        composerView.applyLayoutDirection(direction)
        conversationView.applyLayoutDirection(direction)
        setNeedsQuickLayout()
    }

    private func configureInteractions() {
        composerView.sendRequested = { [weak self] text in
            self?.viewModel.send(text) ?? false
        }
        composerView.heightDidChange = { [weak self] in
            guard let self else { return }
            let shouldFollow = conversationView.isNearBottom
            setNeedsQuickLayout()
            quickLayoutIfNeeded()
            if shouldFollow {
                conversationView.scrollToBottom(animated: false)
            }
        }
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state, reason in
            self?.conversationView.render(state, reason: reason)
        }
    }

    private func observeKeyboard() {
        keyboardObserver.$context
            .dropFirst()
            .sink { [weak self] context in
                guard let self else { return }
                let shouldFollow = conversationView.isNearBottom
                DispatchQueue.main.async { [weak self] in
                    guard let self, shouldFollow else { return }
                    quickLayoutIfNeeded()
                    conversationView.scrollToBottom(
                        animated: context.animationDuration > 0
                    )
                }
            }
            .store(in: &cancellables)
    }
}

#Preview {
    UINavigationController(rootViewController: IMessageChatViewController())
}
