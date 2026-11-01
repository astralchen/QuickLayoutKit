//
//  PhotoPickerController+SheetHost.swift
//  Demo
//

import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 承载系统照片选择器并提供可测量面板。
@available(iOS 17.0, *)
extension PhotoPickerController {

    /// PHPicker 在 iOS 26 会使用全屏透明承载视图；独立 Sheet Host 保证公开的
    /// `UIPresentationController.presentedView` 就是可见面板，便于逐帧读取几何。
    final class SheetHostController: UIViewController {
        /// 作为子控制器嵌入可测量面板的系统照片选择器。
        let picker: PHPickerViewController
        var finishSelection: (() -> Void)?
        private let doneButton = UIButton(type: .system)
        private var attachedConstraints: [NSLayoutConstraint] = []
        private var detachedConstraints: [NSLayoutConstraint] = []
        private var showsDoneButton = false

        /// 创建承载指定照片选择器的面板宿主控制器。
        init(picker: PHPickerViewController) {
            self.picker = picker
            super.init(nibName: nil, bundle: nil)
        }

        /// 不支持从归档创建 `SheetHostController`。
        ///
        /// 请使用代码初始化方法创建此对象。
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 建立照片选择器的子控制器关系，由系统管理网格内容边距。
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            view.clipsToBounds = true
            addChild(picker)
            view.addSubview(picker.view)
            picker.didMove(toParent: self)
            doneButton.configuration = .plain()
            doneButton.setTitle(Localization.text("common.done"), for: .normal)
            doneButton.accessibilityIdentifier = "imessage.picker.done"
            doneButton.addAction(UIAction { [weak self] _ in self?.finishSelection?() }, for: .touchUpInside)
            view.addSubview(doneButton)
            picker.view.translatesAutoresizingMaskIntoConstraints = false
            doneButton.translatesAutoresizingMaskIntoConstraints = false
            doneButton.isHidden = true
            NSLayoutConstraint.activate([
                picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                doneButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
                doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
                doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])
            attachedConstraints = [picker.view.topAnchor.constraint(equalTo: view.topAnchor)]
            detachedConstraints = [
                picker.view.topAnchor.constraint(equalTo: doneButton.bottomAnchor, constant: 8),
            ]
            NSLayoutConstraint.activate(attachedConstraints)
        }

        /// 使用实际面板位置识别浮动呈现；约束随窗口尺寸与按钮固有尺寸更新。
        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            let detached: Bool
            if let presenter = presentingViewController {
                detached = !BottomObstructionCoordinator.isBottomAttached(
                    view.convert(view.bounds, to: presenter.view),
                    to: presenter.view.safeAreaLayoutGuide.layoutFrame
                )
            } else { detached = false }
            guard showsDoneButton != detached else { return }
            showsDoneButton = detached
            doneButton.isHidden = !detached
            NSLayoutConstraint.deactivate(detached ? attachedConstraints : detachedConstraints)
            NSLayoutConstraint.activate(detached ? detachedConstraints : attachedConstraints)
        }
    }
}
