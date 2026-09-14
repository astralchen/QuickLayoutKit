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
        // iOS 26.5 中保留 Sheet 拖动条时，嵌入式 Picker 仍有 15 pt 顶部留白。
        // 只调整公开的子控制器视口，不访问 Photos 的内部滚动视图。
        /// 用于抵消嵌入式照片选择器顶部留白的视口偏移量，单位为点。
        private let pickerTopContentInset: CGFloat = 15
        /// 作为子控制器嵌入可测量面板的系统照片选择器。
        let picker: PHPickerViewController

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

        /// 建立照片选择器的子控制器关系，并补偿顶部安全区。
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            view.clipsToBounds = true
            addChild(picker)
            // 抵消子视图向上延伸时 UIKit 自动补入的顶部安全区。
            picker.additionalSafeAreaInsets.top = -pickerTopContentInset
            view.addSubview(picker.view)
            picker.didMove(toParent: self)
        }

        /// 按宿主边界和顶部补偿量更新照片选择器的视口。
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            picker.view.frame = CGRect(
                x: 0,
                y: -pickerTopContentInset,
                width: view.bounds.width,
                height: view.bounds.height + pickerTopContentInset
            )
        }
    }
}
