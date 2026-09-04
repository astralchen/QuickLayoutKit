//
//  IMessageChatModel.swift
//  Demo
//
//  iMessage 风格单聊演示的内部展示模型。
//

import Foundation
import CoreGraphics

/// 生成实时录音面板使用的固定槽位波形。
///
/// 固定槽位可以保证录音开始、采样增长和滚动期间的柱宽不变，避免波形内容变化
/// 被误认为 Composer 胶囊的内边距发生变化。
nonisolated enum IMessageChatRecordingWaveform {
    /// 录音面板固定显示的细柱槽位数量。
    ///
    /// 六十个 2 点柱形与 2 点间距会占用 238 点宽度，对应 iPhone 16 Pro
    /// 设计图中的整行录音波形。
    static let displaySampleCount = 60

    /// 返回包含固定数量槽位的实时波形。
    ///
    /// 最新采样位于语义结束侧；采样不足时从语义起始侧补入最低振幅，超过上限时
    /// 仅保留最新采样。
    ///
    /// - Parameter samples: 按采集顺序排列的归一化音量采样。
    /// - Returns: 始终包含 ``displaySampleCount`` 个元素的波形。
    static func displaySamples(_ samples: [Float]) -> [Float] {
        let visibleSamples = Array(samples.suffix(displaySampleCount))
        let placeholderCount = displaySampleCount - visibleSamples.count
        return Array(repeating: 0.08, count: placeholderCount)
            + visibleSamples
    }
}

/// 定义音频消息录制所使用的时长边界。
nonisolated enum IMessageChatRecordingPolicy {
    static let minimumDuration: TimeInterval = 1
    static let maximumDuration: TimeInterval = 120

    /// 返回录音是否满足预览和发送条件。
    ///
    /// - Parameters:
    ///   - duration: 录音时长，单位为秒。
    ///   - fileExists: 指示编码后的文件是否可用的布尔值。
    /// - Returns: 时长达到最小值且文件可用时为 `true`；否则为 `false`。
    static func accepts(
        duration: TimeInterval,
        fileExists: Bool
    ) -> Bool {
        fileExists && duration >= minimumDuration
    }

    /// 返回是否应在指定的已录制时长停止录音。
    static func shouldStop(elapsed: TimeInterval) -> Bool {
        elapsed >= maximumDuration
    }
}

nonisolated enum IMessageChatDirection: String, Equatable, Hashable, Sendable {
    case incoming
    case outgoing
}

nonisolated enum IMessageChatDeliveryState: String, Equatable, Hashable, Sendable {
    case delivered
    case read
}

/// iMessage 聊天消息存储的载荷。
///
/// 本地化文本保留其资源键，以便应用内语言变化后重新生成时间线。用户文本和
/// 附件不会在本地化过程中被改写。
nonisolated enum IMessageChatMessageContent: Equatable, Hashable, Sendable {
    case localized(key: String)
    case userText(String)
    case attachment(IMessageChatAttachment)
}

/// 本地音频文件及时间线展示所需的元数据。
///
/// 附件不持有播放器或其他 UIKit 对象。附件文件由页面级附件存储管理，且仅在
/// 聊天页面生命周期内有效。用户录音使用 AAC `.m4a`，模拟语音回复使用本地
/// `.caf` 文件；两种格式使用相同的播放和展示模型。
nonisolated struct IMessageChatAudioAttachment: Equatable, Hashable, Sendable {
    /// 用于播放和 ListKit 刷新身份的稳定标识符。
    let id: UUID

    /// 包含录音或合成回复的本地可回放音频文件。
    let fileURL: URL

    /// 录音的精确时长，单位为秒。
    let duration: TimeInterval

    /// 位于 `0.08...1.0` 范围内的归一化波形采样。
    let waveform: [Float]

    /// 使用本地可回放文件创建音频附件。
    ///
    /// - Parameters:
    ///   - id: 附件的稳定标识符。
    ///   - fileURL: 本地音频文件的 URL。
    ///   - duration: 音频时长，单位为秒。
    ///   - waveform: 归一化波形采样。超出支持范围的值会被截断。
    init(
        id: UUID = UUID(),
        fileURL: URL,
        duration: TimeInterval,
        waveform: [Float]
    ) {
        self.id = id
        self.fileURL = fileURL
        self.duration = duration
        self.waveform = waveform.map { min(1, max(0.08, $0)) }
    }
}

/// 照片消息中单个媒体项目的类型专属元数据。
nonisolated enum IMessageChatMediaKind: Equatable, Hashable, Sendable {
    case image
    case video(duration: TimeInterval)

    var duration: TimeInterval? {
        guard case .video(let duration) = self else { return nil }
        return duration
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

/// 已导入页面附件目录、可以进入照片消息的单个媒体项目。
nonisolated struct IMessageChatMediaItem: Equatable, Hashable, Sendable,
    Identifiable {
    let id: UUID
    let assetIdentifier: String?
    let originalFileURL: URL
    let thumbnailFileURL: URL
    let pixelSize: CGSize
    let kind: IMessageChatMediaKind
    /// 图片原文件是否包含动画帧，或照片资源是否为 Live Photo。
    ///
    /// 当前版本仍使用静态缩略图展示与发送；该值只用于在 Composer 预览项上
    /// 呈现动态媒体标志，不持有 `PHAsset` 或解码器对象。
    let isAnimatedImage: Bool

    init(
        id: UUID = UUID(),
        assetIdentifier: String?,
        originalFileURL: URL,
        thumbnailFileURL: URL,
        pixelSize: CGSize,
        kind: IMessageChatMediaKind,
        isAnimatedImage: Bool = false
    ) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.originalFileURL = originalFileURL
        self.thumbnailFileURL = thumbnailFileURL
        self.pixelSize = pixelSize
        self.kind = kind
        self.isAnimatedImage = isAnimatedImage
    }
}

/// 一次选择并发送的有序照片和视频集合。
nonisolated struct IMessageChatMediaGroupAttachment:
    Equatable,
    Hashable,
    Sendable {
    static let selectionLimit = 20

    let id: UUID
    let items: [IMessageChatMediaItem]

    init(id: UUID = UUID(), items: [IMessageChatMediaItem]) {
        self.id = id
        self.items = items
    }

    var localFileURLs: [URL] {
        items.flatMap { [$0.originalFileURL, $0.thumbnailFileURL] }
    }
}

/// 照片选择器中仍在导入或已经就绪的单项展示状态。
nonisolated enum IMessageChatMediaDraftItemContent: Equatable, Sendable {
    case importing
    case ready(IMessageChatMediaItem)
}

nonisolated struct IMessageChatMediaDraftItemPresentation:
    Equatable,
    Sendable,
    Identifiable {
    let id: UUID
    let assetIdentifier: String?
    let content: IMessageChatMediaDraftItemContent

    var mediaItem: IMessageChatMediaItem? {
        guard case .ready(let item) = content else { return nil }
        return item
    }
}

/// Composer 渲染的有序媒体草稿，不持有系统选择器或媒体框架对象。
nonisolated struct IMessageChatMediaDraftPresentation: Equatable, Sendable {
    let groupID: UUID
    let items: [IMessageChatMediaDraftItemPresentation]

    var canSend: Bool {
        !items.isEmpty && items.allSatisfy { $0.mediaItem != nil }
    }

    var attachment: IMessageChatMediaGroupAttachment? {
        guard canSend else { return nil }
        return IMessageChatMediaGroupAttachment(
            id: groupID,
            items: items.compactMap(\.mediaItem)
        )
    }
}

/// 聊天消息可以携带的页面级本地附件。
///
/// 附件枚举是消息层与具体媒体实现之间的值类型边界。新增图片或视频时，应在
/// 此处增加对应值类型 case，并由时间线渲染层穷举选择 Cell；不要在模型中保存
/// `UIImage`、资源选择器结果、播放器或其他 UIKit、Photos、AVFoundation 对象。
nonisolated enum IMessageChatAttachment: Equatable, Hashable, Sendable {
    /// 包含本地录音或文本合成语音的音频附件。
    case audio(IMessageChatAudioAttachment)

    /// 一次有序选择产生的图片和视频媒体组。
    case mediaGroup(IMessageChatMediaGroupAttachment)

    /// 附件的稳定标识符。
    var id: UUID {
        switch self {
        case .audio(let attachment):
            attachment.id
        case .mediaGroup(let attachment):
            attachment.id
        }
    }

    /// 附件在页面生命周期内拥有的全部本地文件。
    ///
    /// 页面附件存储使用此集合统一删除未发送草稿。未来视频附件可以同时返回
    /// 原始视频与缩略图 URL，图片附件可以返回原图与降采样预览 URL。
    var localFileURLs: [URL] {
        switch self {
        case .audio(let attachment):
            [attachment.fileURL]
        case .mediaGroup(let attachment):
            attachment.localFileURLs
        }
    }

    /// 音频载荷；附件不是音频时为 `nil`。
    var audio: IMessageChatAudioAttachment? {
        guard case .audio(let attachment) = self else { return nil }
        return attachment
    }

    /// 图片/视频媒体组；附件不是媒体组时为 `nil`。
    var mediaGroup: IMessageChatMediaGroupAttachment? {
        guard case .mediaGroup(let attachment) = self else { return nil }
        return attachment
    }
}

nonisolated struct IMessageChatMessage: Equatable, Hashable, Sendable {
    let id: Int
    let direction: IMessageChatDirection
    let content: IMessageChatMessageContent
    let sentAt: Date
    var deliveryState: IMessageChatDeliveryState?
}

nonisolated struct IMessageChatMessagePresentation: Equatable, Sendable {
    let id: Int
    let direction: IMessageChatDirection
    let content: IMessageChatMessagePresentationContent
    let deliveryText: String?

    init(
        id: Int,
        direction: IMessageChatDirection,
        text: String,
        deliveryText: String?
    ) {
        self.id = id
        self.direction = direction
        content = .text(text)
        self.deliveryText = deliveryText
    }

    /// 创建附件消息的展示模型。
    ///
    /// - Parameters:
    ///   - id: 消息的稳定标识符。
    ///   - direction: 语义化的接收或发出方向。
    ///   - attachment: 已解析的本地附件。
    ///   - deliveryText: 本地化的送达状态；没有状态时为 `nil`。
    init(
        id: Int,
        direction: IMessageChatDirection,
        attachment: IMessageChatAttachment,
        deliveryText: String?
    ) {
        self.id = id
        self.direction = direction
        content = .attachment(attachment)
        self.deliveryText = deliveryText
    }

    /// 解析后的文本；消息包含音频时为空字符串。
    var text: String {
        guard case .text(let text) = content else { return "" }
        return text
    }

    /// 音频附件；消息包含文本时为 `nil`。
    var audio: IMessageChatAudioAttachment? {
        guard case .attachment(let attachment) = content else { return nil }
        return attachment.audio
    }

    /// 图片和视频媒体组；消息不包含媒体组时为 `nil`。
    var mediaGroup: IMessageChatMediaGroupAttachment? {
        guard case .attachment(let attachment) = content else { return nil }
        return attachment.mediaGroup
    }

    /// ListKit 用于判断已存在消息是否需要重新配置的内容身份。
    var refreshIdentity: IMessageChatMessageRefreshIdentity {
        switch content {
        case .text(let text):
            .text(
                value: text,
                deliveryText: deliveryText,
                direction: direction
            )
        case .attachment(let attachment):
            .attachment(
                value: attachment,
                deliveryText: deliveryText,
                direction: direction
            )
        }
    }
}

/// 消息 Cell 渲染的载荷。
nonisolated enum IMessageChatMessagePresentationContent: Equatable, Sendable {
    case text(String)
    case attachment(IMessageChatAttachment)
}

/// 消息 Cell 的稳定刷新身份。
///
/// 类型专属元数据由附件值本身提供。新增图片或视频附件后不需要在列表渲染代码中
/// 手工拼接文件、尺寸、缩略图等字符串。
nonisolated enum IMessageChatMessageRefreshIdentity:
    Equatable,
    Hashable,
    Sendable {
    case text(
        value: String,
        deliveryText: String?,
        direction: IMessageChatDirection
    )
    case attachment(
        value: IMessageChatAttachment,
        deliveryText: String?,
        direction: IMessageChatDirection
    )
}

nonisolated struct IMessageChatTimestampPresentation: Equatable, Sendable {
    let sourceMessageID: Int
    let text: String
}

nonisolated enum IMessageChatTimelineItemID: Hashable, Sendable {
    case timestamp(sourceMessageID: Int)
    case message(Int)
    case typing
}

nonisolated enum IMessageChatTimelineContent: Equatable, Sendable {
    case timestamp(IMessageChatTimestampPresentation)
    case message(IMessageChatMessagePresentation)
    case typing(accessibilityLabel: String)
}

nonisolated struct IMessageChatTimelineItem: Equatable, Sendable {
    let id: IMessageChatTimelineItemID
    let content: IMessageChatTimelineContent
}
