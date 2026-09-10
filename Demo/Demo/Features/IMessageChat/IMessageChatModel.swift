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
    /// 允许保留和发送录音的最短时长，单位为秒。
    static let minimumDuration: TimeInterval = 1
    /// 触发自动停止录音的最长时长，单位为秒。
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

/// 消息相对于当前用户的语义收发方向。
nonisolated enum IMessageChatDirection: String, Equatable, Hashable, Sendable {
    /// 由对方发出、当前用户收到的消息。
    case incoming
    /// 由当前用户发出的消息。
    case outgoing
}

/// 发出消息在本地演示发送流程中的状态。
nonisolated enum IMessageChatDeliveryState: String, Equatable, Hashable, Sendable {
    /// 正在等待发送结果。
    case sending
    /// 模拟收件端已确认收到消息。
    case delivered
    /// 消息已被模拟标记为已读。
    case read
    /// 发送失败，可由用户请求重试。
    case failed
}

/// iMessage 聊天消息存储的载荷。
///
/// 本地化文本保留其资源键，以便应用内语言变化后重新生成时间线。用户文本和
/// 附件不会在本地化过程中被改写。
nonisolated enum IMessageChatMessageContent: Equatable, Hashable, Sendable {
    /// 通过资源键延迟解析的本地化文本。
    case localized(key: String)
    /// 保留用户输入内容的普通文本。
    case userText(String)
    /// 由页面附件存储管理的本地附件。
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

    /// 整段文件识别完成后的文本；未识别或没有有效结果时为 nil。
    var transcript: String?

    /// 使用本地可回放文件创建音频附件。
    ///
    /// - Parameters:
    ///   - id: 附件的稳定标识符。
    ///   - fileURL: 本地音频文件的 URL。
    ///   - duration: 音频时长，单位为秒。
    ///   - waveform: 归一化波形采样。超出支持范围的值会被截断。
    ///   - transcript: 可选的完整识别文本；空白文本按无结果处理。
    init(
        id: UUID = UUID(),
        fileURL: URL,
        duration: TimeInterval,
        waveform: [Float],
        transcript: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.duration = duration
        self.waveform = waveform.map { min(1, max(0.08, $0)) }
        let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcript = text?.isEmpty == false ? text : nil
    }
}

/// 照片消息中单个媒体项目的类型专属元数据。
nonisolated enum IMessageChatMediaKind: Equatable, Hashable, Sendable {
    /// 静态或以静态缩略图呈现的图像媒体。
    case image
    /// 包含以秒计的有效时长的视频媒体。
    case video(duration: TimeInterval)

    /// 视频时长，单位为秒；图像媒体返回 `nil`。
    var duration: TimeInterval? {
        guard case .video(let duration) = self else { return nil }
        return duration
    }

    /// 指示当前媒体是否为视频的布尔值。
    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

/// 已导入页面附件目录、可以进入照片消息的单个媒体项目。
nonisolated struct IMessageChatMediaItem: Equatable, Hashable, Sendable,
    Identifiable {
    /// 媒体项目的稳定标识符，与照片库资源身份分离。
    let id: UUID
    /// 照片选择器提供的资源标识符；非照片库来源可为 `nil`。
    let assetIdentifier: String?
    /// 页面拥有的媒体原件 URL。
    let originalFileURL: URL
    /// 页面生成的静态缩略图 URL。
    let thumbnailFileURL: URL
    /// 用于计算展示宽高比的媒体像素尺寸。
    let pixelSize: CGSize
    /// 媒体类型及视频专属时长信息。
    let kind: IMessageChatMediaKind
    /// 图片原文件是否包含动画帧，或照片资源是否为 Live Photo。
    ///
    /// 当前版本仍使用静态缩略图展示与发送；该值只用于在 Composer 预览项上
    /// 呈现动态媒体标志，不持有 `PHAsset` 或解码器对象。
    let isAnimatedImage: Bool

    /// 使用已导入的原件、缩略图与元数据创建媒体项目。
    ///
    /// - Parameters:
    ///   - id: 项目的稳定标识符，默认生成新身份。
    ///   - assetIdentifier: 可选的照片库资源标识符。
    ///   - originalFileURL: 页面拥有的原件 URL。
    ///   - thumbnailFileURL: 静态缩略图 URL。
    ///   - pixelSize: 用于展示比例计算的像素尺寸。
    ///   - kind: 图像或包含时长的视频类型。
    ///   - isAnimatedImage: 是否需要显示动态图像标记，默认值为 `false`。
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
    /// 系统照片选择器单次允许选择的最大项目数量。
    static let selectionLimit = 20

    /// 整组附件的稳定标识符。
    let id: UUID
    /// 按用户选择顺序排列的媒体项目。
    let items: [IMessageChatMediaItem]

    /// 创建保留指定项目顺序的媒体组；省略标识符时生成新身份。
    init(id: UUID = UUID(), items: [IMessageChatMediaItem]) {
        self.id = id
        self.items = items
    }

    /// 按媒体项目顺序返回原件与缩略图 URL，供页面存储统一管理。
    var localFileURLs: [URL] {
        items.flatMap { [$0.originalFileURL, $0.thumbnailFileURL] }
    }
}

/// 照片选择器中仍在导入或已经就绪的单项展示状态。
nonisolated enum IMessageChatMediaDraftItemContent: Equatable, Sendable {
    /// 原始文件或媒体元数据仍在导入。
    case importing
    /// 媒体原件和元数据已经就绪，可参与发送。
    case ready(IMessageChatMediaItem)
}

/// 单个媒体草稿的稳定身份、照片资源引用与展示内容。
nonisolated struct IMessageChatMediaDraftItemPresentation:
    Equatable,
    Sendable,
    Identifiable {
    /// 草稿项目从导入占位到就绪状态保持不变的标识符。
    let id: UUID
    /// 关联照片库项目的资源标识符；不可用时为 `nil`。
    let assetIdentifier: String?
    /// 当前项目的导入占位或已就绪内容。
    let content: IMessageChatMediaDraftItemContent

    /// 已经导入的媒体项目；仍在导入时为 `nil`。
    var mediaItem: IMessageChatMediaItem? {
        guard case .ready(let item) = content else { return nil }
        return item
    }
}

/// Composer 渲染的有序媒体草稿，不持有系统选择器或媒体框架对象。
nonisolated struct IMessageChatMediaDraftPresentation: Equatable, Sendable {
    /// 当前有序媒体草稿所属的附件组标识符。
    let groupID: UUID
    /// 按用户选择顺序排列的媒体草稿项目。
    let items: [IMessageChatMediaDraftItemPresentation]

    /// 指示草稿非空且全部项目已完成导入的布尔值。
    var canSend: Bool {
        !items.isEmpty && items.allSatisfy { $0.mediaItem != nil }
    }

    /// 可以发送的有序媒体组；任一项目未就绪或集合为空时为 `nil`。
    var attachment: IMessageChatMediaGroupAttachment? {
        guard canSend else { return nil }
        return IMessageChatMediaGroupAttachment(
            id: groupID,
            items: items.compactMap(\.mediaItem)
        )
    }
}

/// 文件草稿与消息共享值模型；录音转换后不再携带录音会话或波形状态。
nonisolated struct IMessageChatFileAttachment: Equatable, Hashable, Sendable {
    /// 文件附件的稳定标识符。
    let id: UUID
    /// 页面拥有的文件原件 URL。
    let fileURL: URL
    /// 卡片展示及系统导出时使用的文件名称。
    let displayName: String
    /// 文件内容的统一类型标识符。
    let typeIdentifier: String
    /// 文件大小，单位为字节。
    let byteCount: Int64
    /// 可选的本地文件缩略图 URL；尚未生成或不支持时为 `nil`。
    var thumbnailURL: URL? = nil
}

/// 网页元数据失败时仍可按原始 URL 发送，不伪造应用协作身份。
nonisolated struct IMessageChatLinkAttachment: Equatable, Hashable, Sendable {
    /// 链接附件的稳定标识符，默认生成新身份。
    var id = UUID()
    /// 用户输入或粘贴的原始网页 URL。
    let url: URL
    /// 系统元数据提供的网页标题；尚未取得时为 `nil`。
    var title: String? = nil
    /// 保存在页面目录的网页封面 URL；无封面时为 `nil`。
    var imageURL: URL? = nil
    /// 网站图标单独保存，避免被当作封面放大。
    var iconURL: URL? = nil

    /// 返回 URL 是否包含非空主机名且使用 HTTP 或 HTTPS 协议。
    static func accepts(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && !(url.host ?? "").isEmpty
    }
}

/// 聊天消息可以携带的页面级本地附件。
///
/// 附件枚举是消息层与具体媒体实现之间的值类型边界。音频、媒体组、文件与链接
/// 由各自的值模型描述，时间线渲染层按类型选择单元格。模型仅保存身份、元数据和
/// 本地 URL，不持有图像视图、资源选择器结果或播放器。
nonisolated enum IMessageChatAttachment: Equatable, Hashable, Sendable {
    /// 包含本地录音或文本合成语音的音频附件。
    case audio(IMessageChatAudioAttachment)

    /// 一次有序选择产生的图片和视频媒体组。
    case mediaGroup(IMessageChatMediaGroupAttachment)
    /// 可内联展示并通过系统文件选择器导出的本地文件。
    case file(IMessageChatFileAttachment)
    /// 保留原始 URL 与可选缓存元数据的网页链接。
    case link(IMessageChatLinkAttachment)

    /// 附件的稳定标识符。
    var id: UUID {
        switch self {
        case .audio(let attachment):
            attachment.id
        case .mediaGroup(let attachment):
            attachment.id
        case .file(let attachment): attachment.id
        case .link(let attachment): attachment.id
        }
    }

    /// 附件在页面生命周期内拥有的全部本地文件。
    ///
    /// 页面附件存储使用此集合统一清理资源。媒体组包含原件与缩略图，文件包含
    /// 原件与可选缩略图，链接仅包含已缓存的封面与站点图标，不包含远程网页 URL。
    var localFileURLs: [URL] {
        switch self {
        case .audio(let attachment):
            [attachment.fileURL]
        case .mediaGroup(let attachment):
            attachment.localFileURLs
        case .file(let file): [file.fileURL] + [file.thumbnailURL].compactMap { $0 }
        case .link(let link): [link.imageURL, link.iconURL].compactMap { $0 }
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

/// 聊天时间线保存的原始消息值，包含身份、载荷、时间和发送状态。
nonisolated struct IMessageChatMessage: Equatable, Hashable, Sendable {
    /// 消息在当前会话中的稳定整数标识符。
    let id: Int
    /// 当前消息的接收或发出方向，用于确定气泡外观与语义对齐。
    let direction: IMessageChatDirection
    /// 消息保存的文本或附件载荷，可在转写完成后更新。
    var content: IMessageChatMessageContent
    /// 消息进入会话时记录的日期，用于时间分组。
    let sentAt: Date
    /// 发出消息的发送状态；收到的消息通常为 `nil`。
    var deliveryState: IMessageChatDeliveryState?
}

/// 完成本地化解析、供时间线单元格直接渲染的消息值。
nonisolated struct IMessageChatMessagePresentation: Equatable, Sendable {
    /// 对应原始消息的稳定标识符。
    let id: Int
    /// 当前消息的接收或发出方向，用于确定气泡外观与语义对齐。
    let direction: IMessageChatDirection
    /// 已解析的正文文本或类型化附件内容。
    let content: IMessageChatMessagePresentationContent
    /// 可选的本地化送达或已读文字。
    let deliveryText: String?
    /// 发出消息的状态；初始化收到消息时强制为 `nil`。
    let deliveryState: IMessageChatDeliveryState?

    /// 创建文本消息的展示模型。
    ///
    /// - Parameters:
    ///   - id: 消息的稳定标识符。
    ///   - direction: 相对于当前用户的收发方向。
    ///   - text: 已完成本地化解析的正文。
    ///   - deliveryText: 可选的送达状态文字。
    ///   - deliveryState: 可选的发送状态；收到消息会忽略此值。
    init(
        id: Int,
        direction: IMessageChatDirection,
        text: String,
        deliveryText: String?,
        deliveryState: IMessageChatDeliveryState? = nil
    ) {
        self.id = id
        self.direction = direction
        content = .text(text)
        self.deliveryText = deliveryText
        self.deliveryState = direction == .outgoing ? deliveryState : nil
    }

    /// 创建附件消息的展示模型。
    ///
    /// - Parameters:
    ///   - id: 消息的稳定标识符。
    ///   - direction: 语义化的接收或发出方向。
    ///   - attachment: 已解析的本地附件。
    ///   - deliveryText: 本地化的送达状态；没有状态时为 `nil`。
    ///   - deliveryState: 发出消息的发送状态；收到消息会忽略此值。
    init(
        id: Int,
        direction: IMessageChatDirection,
        attachment: IMessageChatAttachment,
        deliveryText: String?,
        deliveryState: IMessageChatDeliveryState? = nil
    ) {
        self.id = id
        self.direction = direction
        content = .attachment(attachment)
        self.deliveryText = deliveryText
        self.deliveryState = direction == .outgoing ? deliveryState : nil
    }

    /// 解析后的文本；消息包含任意附件时为空字符串。
    var text: String {
        guard case .text(let text) = content else { return "" }
        return text
    }

    /// 音频附件；文本或其他类型附件返回 `nil`。
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
                direction: direction,
                deliveryState: deliveryState
            )
        case .attachment(let attachment):
            .attachment(
                value: attachment,
                deliveryText: deliveryText,
                direction: direction,
                deliveryState: deliveryState
            )
        }
    }
}

/// 消息 Cell 渲染的载荷。
nonisolated enum IMessageChatMessagePresentationContent: Equatable, Sendable {
    /// 已经解析完成、可直接显示的文本。
    case text(String)
    /// 由对应类型的消息单元格呈现的附件。
    case attachment(IMessageChatAttachment)
}

/// 消息 Cell 的稳定刷新身份。
///
/// 类型专属元数据由附件值本身提供；附件内容、发送状态或展示文字变化时，列表
/// 可据此重新配置已有单元格，无须手工拼接文件与尺寸等字符串。
nonisolated enum IMessageChatMessageRefreshIdentity:
    Equatable,
    Hashable,
    Sendable {
    /// 以正文、送达文字、收发方向和发送状态共同判断文本消息是否需要刷新。
    case text(
        value: String,
        deliveryText: String?,
        direction: IMessageChatDirection,
        deliveryState: IMessageChatDeliveryState? = nil
    )
    /// 以附件值、送达文字、收发方向和发送状态共同判断附件消息是否需要刷新。
    case attachment(
        value: IMessageChatAttachment,
        deliveryText: String?,
        direction: IMessageChatDirection,
        deliveryState: IMessageChatDeliveryState? = nil
    )
}

/// 时间线分隔项使用的来源消息身份与本地化时间文字。
nonisolated struct IMessageChatTimestampPresentation: Equatable, Sendable {
    /// 触发当前时间分隔项的消息标识符。
    let sourceMessageID: Int
    /// 已经按当前区域设置格式化的时间文字。
    let text: String
}

/// 区分时间分隔、消息和输入状态项的稳定时间线身份。
nonisolated enum IMessageChatTimelineItemID: Hashable, Sendable {
    /// 由来源消息身份确定的时间分隔项。
    case timestamp(sourceMessageID: Int)
    /// 由消息整数标识符确定的消息项。
    case message(Int)
    /// 当前会话唯一的对方输入状态项。
    case typing
}

/// 时间线单项可呈现的内容类型。
nonisolated enum IMessageChatTimelineContent: Equatable, Sendable {
    /// 显示本地化时间分隔信息。
    case timestamp(IMessageChatTimestampPresentation)
    /// 显示已经解析的文本或附件消息。
    case message(IMessageChatMessagePresentation)
    /// 显示对方输入状态，并携带辅助功能描述。
    case typing(accessibilityLabel: String)
}

/// 将稳定列表身份与展示内容组合的时间线项目。
nonisolated struct IMessageChatTimelineItem: Equatable, Sendable {
    /// 供列表差异更新使用的稳定项目身份。
    let id: IMessageChatTimelineItemID
    /// 由对应单元格显示的时间线内容。
    let content: IMessageChatTimelineContent
}

/// 提供基于已提交附件生成同类型模拟回复的值转换。
extension IMessageChatAttachment {
    /// 模拟回复使用独立消息/附件/媒体项目身份，共享页面已提交的只读资源。
    /// 已提交资源统一保留到页面退出，因此无须复制视频，也不会被 Composer 草稿清理。
    func simulatedReply() -> Self {
        switch self {
        case .audio(let audio):
            return .audio(.init(fileURL: audio.fileURL, duration: audio.duration,
                                waveform: audio.waveform, transcript: audio.transcript))
        case .mediaGroup(let group):
            return .mediaGroup(.init(items: group.items.map { item in
                .init(assetIdentifier: item.assetIdentifier, originalFileURL: item.originalFileURL,
                      thumbnailFileURL: item.thumbnailFileURL, pixelSize: item.pixelSize,
                      kind: item.kind, isAnimatedImage: item.isAnimatedImage)
            }))
        case .file(let file):
            return .file(.init(id: UUID(), fileURL: file.fileURL, displayName: file.displayName,
                               typeIdentifier: file.typeIdentifier, byteCount: file.byteCount,
                               thumbnailURL: file.thumbnailURL))
        case .link(var link):
            link.id = UUID()
            return .link(link)
        }
    }
}
