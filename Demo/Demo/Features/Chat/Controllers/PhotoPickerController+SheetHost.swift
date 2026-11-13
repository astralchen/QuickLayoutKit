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

        private weak var sourceView: UIView?
        private var keyboardHeight: CGFloat = 0
        private var compactDetentAdjustment: CGFloat = 0
        private var calibratedSafeFrame: CGRect?
        private(set) var calibratedCompactObstruction: CGFloat?

        /// 创建承载指定照片选择器的面板宿主控制器。
        init(picker: PHPickerViewController, sourceView: UIView) {
            self.sourceView = sourceView
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
            view.accessibilityIdentifier = "imessage.picker.panel"
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

        private var compactDetent: PhotoPickerCompactDetent {
            let pageBottom = sourceView?.safeAreaInsets.bottom ?? 0
            return PhotoPickerCompactDetent(keyboardHeight: keyboardHeight, pageBottom: pageBottom,
                windowBottom: sourceView?.window?.safeAreaInsets.bottom ?? pageBottom)
        }

        func configureDetents(of sheet: UISheetPresentationController, keyboardHeight: CGFloat) {
            self.keyboardHeight = keyboardHeight
            calibratedSafeFrame = nil
            calibratedCompactObstruction = nil
            compactDetentAdjustment = 0
            let small = UISheetPresentationController.Detent.custom(identifier: PhotoPickerController.keyboardDetentIdentifier) {
                [weak self] context in
                guard let self else { return nil }
                let height = max(1, compactDetent.sheetHeight + compactDetentAdjustment)
                return min(height, context.maximumDetentValue)
            }
            sheet.detents = [small, .large()]
        }

        /// 面板保持打开期间，旋转、折叠或安全区改变时采用新布局的目标高度。
        func updateKeyboardHeight(_ height: CGFloat) {
            guard height > 0, abs(height - keyboardHeight) > 0.5,
                  !isBeingDismissed, let sheet = sheetPresentationController else { return }
            keyboardHeight = height
            calibratedSafeFrame = nil
            calibratedCompactObstruction = nil
            compactDetentAdjustment = 0
            sheet.invalidateDetents()
        }

        /// 系统会为 Sheet 留出悬浮边缘，也可能缩放整个面板。用模型层的最终位置
        /// 将聊天页的键盘顶边换算到面板坐标，在入场布局时校准小档。
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let sheet = sheetPresentationController,
                  sheet.selectedDetentIdentifier == PhotoPickerController.keyboardDetentIdentifier,
                  let source = sourceView,
                  view.window != nil, !isBeingDismissed,
                  calibratedSafeFrame != source.safeAreaLayoutGuide.layoutFrame else { return }

            let frame = view.convert(view.bounds, to: source)
            guard BottomObstructionCoordinator.overlapsComposerBottom(frame, in: source.safeAreaLayoutGuide.layoutFrame),
                  frame.height > 0, frame.minY < source.bounds.maxY else { return }
            let safeFrame = source.safeAreaLayoutGuide.layoutFrame
            calibratedSafeFrame = safeFrame
            let visibleObstruction = safeFrame.maxY - frame.minY
            let scale = frame.height / view.bounds.height
            let delta = (compactDetent.composerObstruction - visibleObstruction) / scale
            // 矮键盘也使用其实际高度；展开大档时，输入栏停在校准后的小档顶部。
            let currentDetent = compactDetent.sheetHeight + compactDetentAdjustment
            let nextDetent = max(1, currentDetent + delta)
            let change = nextDetent - currentDetent
            calibratedCompactObstruction = visibleObstruction + change * scale
            guard abs(change) > 0.5 else { return }
            compactDetentAdjustment += change
            sheet.invalidateDetents()
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
