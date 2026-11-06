//
//  AnimatedKeyboardResponsiveView.swift
//  Demo
//
//  Created by Sondra on 2026/1/27.
//
import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit
import Combine


class AnimatedKeyboardResponsiveView: QuickLayoutView {

    let textField = UITextField()
    private lazy var inputBinding = Localization.inputContext(for: self).makeTextInputBinding(to: textField)
    let submitButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        return UIButton(configuration: configuration)
    }()
    let diagnosticsBackgroundView = UIView()
    let diagnosticsLabel = UILabel()
    let contentScrollView = QuickLayoutScrollView()

    private lazy var keyboardObserver = QuickLayoutKeyboardObserver()

    private var keyboardContext: QuickLayoutKeyboardContext? {
        didSet {
            updateKeyboardDiagnostics()
            if let keyboardContext, oldValue != keyboardContext {
                animateLayoutChange(keyboardContext)
            }
        }
    }

    private var keyboardHeight: CGFloat {
        // 原始相交高度也包含悬浮／分离键盘。让 Kit 结合当前容器和
        // UIKeyboardLayoutGuide 判定停靠，只为真正覆盖底边的键盘抬升内容。
        let bottom = quickLayoutKeyboardSafeAreaInsets.bottom
        return bottom > safeAreaInsets.bottom ? bottom : 0
    }

    private var cancellables : Set<AnyCancellable> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupKeyboardObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        quickLayoutKeyboardSafeAreaBehavior = .followsDockedKeyboard()
        textField.borderStyle = .roundedRect
        textField.accessibilityIdentifier = "keyboard.input"
        submitButton.accessibilityIdentifier = "keyboard.submit"

        diagnosticsLabel.numberOfLines = 0
        diagnosticsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        diagnosticsLabel.textColor = .secondaryLabel

        diagnosticsBackgroundView.backgroundColor = .secondarySystemBackground
        diagnosticsBackgroundView.layer.cornerRadius = 12
        diagnosticsBackgroundView.layer.masksToBounds = true

        submitButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        reloadLocalizedContent()
    }

    func reloadLocalizedContent() {
        textField.placeholder = Localization.text("keyboard.placeholder")
        if var configuration = submitButton.configuration {
            configuration.title = Localization.text("common.submit")
            submitButton.configuration = configuration
        }
        updateKeyboardDiagnostics()
        setNeedsLayout()
    }

    func applyLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        let attribute: UISemanticContentAttribute = direction == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
        semanticContentAttribute = attribute
        [
            diagnosticsBackgroundView,
            diagnosticsLabel,
            textField,
            submitButton,
        ].forEach {
            $0.semanticContentAttribute = attribute
        }
        if let configuration = submitButton.configuration {
            submitButton.configuration = configuration
        }
        inputBinding.refresh()
        setNeedsLayout()
    }

    @objc private func dismissKeyboard() {
        textField.resignFirstResponder()
    }

    private func setupKeyboardObservers() {
        keyboardObserver.$context
            // @Published 的首值是观察器的初始状态，并非收到的 UIKit 通知。
            .dropFirst()
            .sink { [weak self] context in
                self?.keyboardContext = context
            }
            .store(in: &cancellables)
    }


    private func animateLayoutChange(_ keyboardContext: QuickLayoutKeyboardContext) {
        UIView.animate(
            withDuration: keyboardContext.animationDuration,
            delay: 0,
            options: keyboardContext.animationOptions.union([
                .beginFromCurrentState,
                .allowUserInteraction,
            ]),
            animations: {
                self.setNeedsLayout()
                self.layoutIfNeeded()
                if keyboardContext.isVisible {
                    // scrollTo(animated: false) 会清除滚动容器的 position 动画，
                    // 连带取消输入框和提交按钮随键盘移动的动画。这里让偏移量
                    // 参与当前键盘动画，不另外启动滚动动画或移除容器动画。
                    let scrollView = self.contentScrollView
                    scrollView.contentOffset.y = max(
                        -scrollView.adjustedContentInset.top,
                        scrollView.contentSize.height - scrollView.bounds.height
                            + scrollView.adjustedContentInset.bottom
                    )
                }
            }
        )
    }

    private func updateKeyboardDiagnostics() {
        let title = Localization.text("keyboard.diagnostics.title")
        guard let keyboardContext else {
            diagnosticsLabel.text = [
                title,
                Localization.text("keyboard.diagnostics.waiting"),
            ].joined(separator: "\n")
            return
        }
        let resolved = keyboardContext.resolved(in: self)
        diagnosticsLabel.text = [
            title,
            Localization.text(
                "keyboard.diagnostics.event",
                keyboardContext.event.displayDescription
            ),
            Localization.text(
                "keyboard.diagnostics.visible",
                Localization.text(keyboardContext.isVisible ? "common.boolean.true" : "common.boolean.false")
            ),
            Localization.text(
                "keyboard.diagnostics.rawFrame",
                keyboardContext.endFrame.displayDescription
            ),
            Localization.text(
                "keyboard.diagnostics.intersection",
                resolved.intersection.displayDescription
            ),
            Localization.text(
                "keyboard.diagnostics.height",
                Int64(resolved.height)
            ),
        ].joined(separator: "\n")
    }

    override var body: Layout {
        ContentFittingScroll(contentScrollView) {
            VStack(spacing: 16) {
                diagnosticsLabel
                    .resizable(axis: .horizontal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        diagnosticsBackgroundView
                    }

                textField
                    .resizable()
                    .frame(height: 44)

                submitButton
                    .resizable()
                    .frame(height: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 分栏的安全区可能只在一侧；逐边消费，避免将侧栏宽度重复扣到另一侧。
        .safeAreaPadding([.top, .horizontal], 20)
        .padding(.bottom, max(keyboardHeight + 20, safeAreaInsets.bottom))
    }
}



@available(iOS 17.0, *)
#Preview {
    AnimatedKeyboardResponsiveView()
}

private extension QuickLayoutKeyboardEvent {
    var displayDescription: String {
        switch self {
        case .willShow:
            return "willShow"
        case .willHide:
            return "willHide"
        case .willChangeFrame:
            return "willChangeFrame"
        case .didChangeFrame:
            return "didChangeFrame"
        case .unknown:
            return "unknown"
        }
    }
}

private extension CGRect {
    var displayDescription: String {
        guard !isNull else { return "null" }
        return "(\(Int(origin.x)), \(Int(origin.y)), \(Int(width)), \(Int(height)))"
    }
}
