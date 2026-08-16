//
//  AnimatedKeyboardResponsiveView.swift
//  Demo
//
//  Created by Sondra on 2026/1/27.
//
import UIKit
import QuickLayout
import QuickLayoutKit
import Combine


@QuickLayout
class AnimatedKeyboardResponsiveView: UIView {

    let textField = UITextField()
    let submitButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        return UIButton(configuration: configuration)
    }()
    let diagnosticsBackgroundView = UIView()
    let diagnosticsLabel = UILabel()

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
        keyboardContext.resolved(in: self).height
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
        textField.borderStyle = .roundedRect

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
        textField.placeholder = DemoLocalization.text("keyboard.placeholder")
        if var configuration = submitButton.configuration {
            configuration.title = DemoLocalization.text("common.submit")
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
        textField.textAlignment = direction == .rightToLeft ? .right : .left
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
            }
        )
    }

    private func updateKeyboardDiagnostics() {
        let resolved = keyboardContext.resolved(in: self)
        diagnosticsLabel.text = [
            DemoLocalization.text("keyboard.diagnostics.title"),
            DemoLocalization.text(
                "keyboard.diagnostics.event",
                keyboardContext.event.demoDescription
            ),
            DemoLocalization.text(
                "keyboard.diagnostics.rawFrame",
                keyboardContext.endFrame.demoDescription
            ),
            DemoLocalization.text(
                "keyboard.diagnostics.intersection",
                resolved.intersection.demoDescription
            ),
            DemoLocalization.text(
                "keyboard.diagnostics.height",
                Int64(resolved.height)
            ),
        ].joined(separator: "\n")
    }

    var body: Layout {
        VStack(spacing: 16) {
            Spacer()

            diagnosticsLabel
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    diagnosticsBackgroundView
                }

            textField
                .frame(height: 44)

            submitButton
                .frame(height: 50)
        }
        .padding(.horizontal, 20)
        .padding(.horizontal, quickLayoutSafeAreaInsets.maximumHorizontalInset)
        .padding(.bottom, max(keyboardHeight + 20, safeAreaInsets.bottom))
    }
}



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
