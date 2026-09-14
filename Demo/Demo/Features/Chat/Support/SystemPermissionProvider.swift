//
//  SystemPermissionProvider.swift
//  Demo
//

import AVFAudio
import Foundation
import Speech
import UIKit

/// 请求媒体操作所需权限的对象。
@MainActor
protocol MediaPermissionProviding: AnyObject {
    /// 请求访问音频输入。
    func requestMicrophonePermission() async -> Bool

    /// 请求访问语音识别。
    func requestSpeechPermission() async -> Bool
}

/// 由 AVFAudio 和 Speech 支持的真实权限提供者。
@available(iOS 17.0, *)
@MainActor
final class SystemPermissionProvider:
    MediaPermissionProviding {

    /// 返回麦克风授权结果；尚未决定权限时请求系统授权。
    func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// 返回语音识别授权结果；尚未决定权限时请求系统授权。
    func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}
