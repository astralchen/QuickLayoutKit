//
//  ScrollViewWithKeyboardViewController.swift
//  Demo
//
//  Created by 辰宸 on 2026/1/27.
//

import UIKit
import QuickLayout
import QuickLayoutKit
import Combine

// MARK: - 页头视图

@QuickLayout
class FormHeaderView: UIView {

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemBlue.withAlphaComponent(0.1)
        layer.cornerRadius = 16

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .systemBlue

        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
    }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        setNeedsLayout()
    }

    func applySemanticContentAttribute(
        _ semanticContentAttribute: UISemanticContentAttribute
    ) {
        self.semanticContentAttribute = semanticContentAttribute
        [titleLabel, subtitleLabel].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
        }
        setNeedsLayout()
    }

    var body: Layout {
        VStack(spacing: 4) {
            titleLabel
            subtitleLabel
        }
        .padding(20)
    }
}

// MARK: - 表单字段视图

@QuickLayout
class FormFieldView: UIView {

    let textField: UITextField
    let iconView = UIImageView()
    let containerView = UIView()

    init(textField: UITextField, placeholder: String, icon: String) {
        self.textField = textField
        super.init(frame: .zero)
        setupViews(placeholder: placeholder, icon: icon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(placeholder: String, icon: String) {
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 12

        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit

        textField.placeholder = placeholder
    }

    func updatePlaceholder(_ placeholder: String) {
        textField.placeholder = placeholder
        setNeedsLayout()
    }

    func applySemanticContentAttribute(
        _ semanticContentAttribute: UISemanticContentAttribute
    ) {
        self.semanticContentAttribute = semanticContentAttribute
        [textField, iconView, containerView].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
        }
        setNeedsLayout()
    }

    var body: Layout {
        ZStack {
            containerView

            HStack(spacing: 12) {
                iconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                textField
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 50)
    }
}

// MARK: - 备注字段视图

@QuickLayout
class NotesFieldView: UIView {

    let label = UILabel()
    let textView: UITextView

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
    }

    func configure(title: String) {
        label.text = title
        setNeedsLayout()
    }

    func applySemanticContentAttribute(
        _ semanticContentAttribute: UISemanticContentAttribute
    ) {
        self.semanticContentAttribute = semanticContentAttribute
        [label, textView].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
        }
        setNeedsLayout()
    }

    var body: Layout {
        VStack(spacing: 8) {
            label

            textView
                .frame(height: 120)
        }
    }
}

// MARK: - 主控制器

class ScrollViewWithKeyboardViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.form.title" }

    private let viewModel: FormViewModel

    let scrollView = QuickLayoutScrollView()
    let keyboardObserver = QuickLayoutKeyboardObserver()
    private lazy var keyboardAvoider = QuickLayoutKeyboardAvoider(
        scrollView: scrollView,
        observer: keyboardObserver
    )

    // 界面组件
    let headerView = FormHeaderView()

    let nameTextField = UITextField()
    let emailTextField = UITextField()
    let phoneTextField = UITextField()
    let addressTextField = UITextField()
    let notesTextView = UITextView()
    let customInputButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.cornerStyle = .large
        configuration.image = UIImage(systemName: "keyboard.badge.eye")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        return UIButton(configuration: configuration)
    }()
    let submitButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .init(
            top: 14,
            leading: 32,
            bottom: 14,
            trailing: 32
        )
        configuration.image = UIImage(systemName: "checkmark.circle.fill")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        return UIButton(configuration: configuration)
    }()

    // 表单字段视图
    lazy var nameFieldView = FormFieldView(textField: nameTextField, placeholder: "", icon: "person.fill")
    lazy var emailFieldView = FormFieldView(textField: emailTextField, placeholder: "", icon: "envelope.fill")
    lazy var phoneFieldView = FormFieldView(textField: phoneTextField, placeholder: "", icon: "phone.fill")
    lazy var addressFieldView = FormFieldView(textField: addressTextField, placeholder: "", icon: "location.fill")
    lazy var notesFieldView = NotesFieldView(textView: notesTextView)

    private var keyboardContext = QuickLayoutKeyboardContext.hidden {
        didSet {
            if oldValue != keyboardContext {
                animateKeyboardChange()
                if keyboardContext.isVisible {
                    scrollToCurrentActiveField()
                }
            }
        }
    }

    private var currentActiveField: UIView?
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(viewModel: FormViewModel())
    }

    init(viewModel: FormViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = FormViewModel()
        super.init(coder: coder)
    }

    override var body: Layout {
        ScrollView(scrollView, .vertical) {
            VStack(spacing: 20) {
                // 页头
                headerView
                    .frame(height: 100)

                // 表单字段
                nameFieldView
                emailFieldView
                phoneFieldView
                addressFieldView

                // 备注字段
                notesFieldView

                // 自定义输入控件
                customInputButton
                    .frame(height: 48)

                // 提交按钮
                submitButton
                    .frame(height: 50)
            }
        }
        .contentMargins(.horizontal, 20)
        .contentMargins(.top, 20)
        .contentMargins(.bottom, 10)
        .safeAreaPadding(0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        bindViewModel()
        setupKeyboardObservers()
        setupGestures()
        _ = keyboardAvoider
    }

    private func setupViews() {
        scrollView.backgroundColor = .systemBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive

        // 配置文本输入框。
        [nameTextField, emailTextField, phoneTextField, addressTextField].forEach { textField in
            textField.borderStyle = .roundedRect
            textField.backgroundColor = .secondarySystemBackground
            textField.layer.cornerRadius = 12
            textField.font = .systemFont(ofSize: 16)
            textField.returnKeyType = .next
            textField.delegate = self
            textField.addTarget(
                self,
                action: #selector(textFieldDidChange(_:)),
                for: .editingChanged
            )
        }

        addressTextField.returnKeyType = .done

        // 配置邮箱输入框。
        emailTextField.keyboardType = .emailAddress
        emailTextField.autocapitalizationType = .none

        // 配置电话输入框。
        phoneTextField.keyboardType = .phonePad

        // 配置多行文本视图。
        notesTextView.backgroundColor = .secondarySystemBackground
        notesTextView.layer.cornerRadius = 12
        notesTextView.font = .systemFont(ofSize: 16)
        notesTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        notesTextView.delegate = self

        customInputButton.addTarget(self, action: #selector(customInputTapped), for: .touchUpInside)

        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        keyboardAvoider.extraBottomPadding = 12
        keyboardAvoider.safeAreaStrategy = .ignore
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.refreshLocalizedContent()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        let attribute = view.semanticContentAttribute

        scrollView.semanticContentAttribute = attribute
        headerView.applySemanticContentAttribute(attribute)
        [
            nameFieldView,
            emailFieldView,
            phoneFieldView,
            addressFieldView,
        ].forEach {
            $0.applySemanticContentAttribute(attribute)
        }
        notesFieldView.applySemanticContentAttribute(attribute)

        // 重新应用配置，刷新 UIButton.Configuration 内部的图文排列。
        [customInputButton, submitButton].forEach {
            $0.semanticContentAttribute = attribute
            if let configuration = $0.configuration {
                $0.configuration = configuration
            }
            $0.setNeedsLayout()
        }
        [nameTextField, emailTextField, phoneTextField, addressTextField].forEach {
            $0.textAlignment = direction == .rightToLeft ? .right : .left
        }
        notesTextView.textAlignment = direction == .rightToLeft ? .right : .left

        scrollView.setNeedsLayout()
        setNeedsQuickLayout()
    }

    private func setupKeyboardObservers() {
        keyboardObserver.$context
            .sink { [weak self] context in
                self?.keyboardContext = context
            }
            .store(in: &cancellables)

        // 监听输入框开始编辑
        NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
            .merge(with: NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification))
            .sink { [weak self] notification in
                if let field = notification.object as? UIView {
                    self?.currentActiveField = field
                    self?.keyboardAvoider.setActiveView(field)
                    self?.scrollToActiveField(field)
                }
            }
            .store(in: &cancellables)
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
        viewModel.onSubmission = { [weak self] submission in
            self?.present(submission)
        }
    }

    private func render(_ state: FormViewModel.State) {
        headerView.configure(
            title: state.headerTitle,
            subtitle: state.headerSubtitle
        )
        nameFieldView.updatePlaceholder(state.namePlaceholder)
        emailFieldView.updatePlaceholder(state.emailPlaceholder)
        phoneFieldView.updatePlaceholder(state.phonePlaceholder)
        addressFieldView.updatePlaceholder(state.addressPlaceholder)
        notesFieldView.configure(title: state.notesTitle)
        updateButton(customInputButton, title: state.customInputTitle)
        updateButton(submitButton, title: state.submitTitle)
        setNeedsQuickLayout()
    }

    private func updateButton(_ button: UIButton, title: String) {
        guard var configuration = button.configuration else {
            assertionFailure("Form buttons require UIButton.Configuration")
            return
        }
        configuration.title = title
        button.configuration = configuration
    }

    private func animateKeyboardChange() {
        performLayoutUpdate(
            duration: keyboardContext.animationDuration,
            options: keyboardContext.animationOptions
        )
    }

    private func scrollToCurrentActiveField() {
        guard let field = currentActiveField else { return }
        scrollToActiveField(field)
    }

    private func scrollToActiveField(_ field: UIView?) {
        keyboardAvoider.setActiveView(field)
        keyboardAvoider.scrollActiveViewIntoVisibleArea(animated: keyboardContext.isVisible)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
        if currentActiveField === customInputButton {
            NotificationCenter.default.post(name: .quickLayoutKeyboardActiveInputDidEndEditing, object: customInputButton)
        }
        currentActiveField = nil
        keyboardAvoider.setActiveView(nil)
    }

    @objc private func customInputTapped() {
        view.endEditing(true)
        currentActiveField = customInputButton
        NotificationCenter.default.post(
            name: .quickLayoutKeyboardActiveInputDidBeginEditing,
            object: customInputButton,
            userInfo: ["activeView": customInputButton]
        )
        scrollToActiveField(customInputButton)
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        guard let field = formField(for: textField) else { return }
        viewModel.update(textField.text ?? "", for: field)
    }

    @objc private func submitTapped() {
        dismissKeyboard()
        syncFormValues()
        viewModel.submit()
    }

    private func syncFormValues() {
        viewModel.update(nameTextField.text ?? "", for: .name)
        viewModel.update(emailTextField.text ?? "", for: .email)
        viewModel.update(phoneTextField.text ?? "", for: .phone)
        viewModel.update(addressTextField.text ?? "", for: .address)
        viewModel.update(notesTextView.text ?? "", for: .notes)
    }

    private func present(_ submission: FormViewModel.Submission) {
        let alert = UIAlertController(
            title: submission.title,
            message: submission.message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: submission.actionTitle, style: .default)
        )
        present(alert, animated: true)
    }

    private func formField(for textField: UITextField) -> FormViewModel.Field? {
        switch textField {
        case nameTextField: .name
        case emailTextField: .email
        case phoneTextField: .phone
        case addressTextField: .address
        default: nil
        }
    }

    private func focus(_ field: FormViewModel.Field) {
        switch field {
        case .name: nameTextField.becomeFirstResponder()
        case .email: emailTextField.becomeFirstResponder()
        case .phone: phoneTextField.becomeFirstResponder()
        case .address: addressTextField.becomeFirstResponder()
        case .notes: notesTextView.becomeFirstResponder()
        }
    }
}

// MARK: - UITextField 代理

extension ScrollViewWithKeyboardViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let field = formField(for: textField),
              let nextField = viewModel.nextField(after: field) else {
            textField.resignFirstResponder()
            return true
        }

        focus(nextField)
        return true
    }
}

// MARK: - UITextView 代理

extension ScrollViewWithKeyboardViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel.update(textView.text ?? "", for: .notes)
    }
}

// MARK: - 预览

#Preview {
    UINavigationController(rootViewController: ScrollViewWithKeyboardViewController())
}
