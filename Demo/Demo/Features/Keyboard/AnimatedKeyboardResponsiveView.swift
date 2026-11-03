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

    let keyboardObserver = QuickLayoutKeyboardObserver()

    private var keyboardContext = QuickLayoutKeyboardContext.hidden {
        didSet {
            updateKeyboardDiagnostics()
            if oldValue != keyboardContext { // 避免首次出现动画
                animateLayoutChange()
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
            .sink { [weak self] context in
                self?.keyboardContext = context
            }
            .store(in: &cancellables)
    }


    private func animateLayoutChange() {
        UIView.animate(
            withDuration: keyboardContext.animationDuration,
            delay: 0,
            options: keyboardContext.animationOptions,
            animations: {
                self.setNeedsLayout()
                self.layoutIfNeeded()
                if self.keyboardContext.isVisible {
                    self.contentScrollView.scrollTo(.bottom, animated: false)
                }
            }
        )
    }

    private func updateKeyboardDiagnostics() {
        let resolved = keyboardContext.resolved(in: self)
        diagnosticsLabel.text = [
            Localization.text("keyboard.diagnostics.title"),
            Localization.text(
                "keyboard.diagnostics.event",
                keyboardContext.event.demoDescription
            ),
            Localization.text(
                "keyboard.diagnostics.rawFrame",
                keyboardContext.endFrame.demoDescription
            ),
            Localization.text(
                "keyboard.diagnostics.intersection",
                resolved.intersection.demoDescription
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
    var demoDescription: String {
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
    var demoDescription: String {
        guard !isNull else { return "null" }
        return "(\(Int(origin.x)), \(Int(origin.y)), \(Int(width)), \(Int(height)))"
    }
}
