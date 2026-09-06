import UIKit
import UniformTypeIdentifiers

/// 仅属于一次用户粘贴的提供器描述，不进入消息值模型或持久化存储。
@available(iOS 26.0, *)
enum IMessageChatPasteSource {
    case provider(NSItemProvider, typeIdentifier: String)
    case fileURL(URL)
    case link(URL)
    case text(String)

    static func webURL(in text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace),
              let url = URL(string: value), IMessageChatLinkAttachment.accepts(url) else { return nil }
        return url
    }

    static func fileType(in provider: NSItemProvider) -> String? {
        let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        // 视频提供器有时同时提供封面；只选择一次真实媒体表示。
        for family in [UTType.movie, .audio] {
            if let type = types.first(where: { $0.conforms(to: family) }) { return type.identifier }
        }
        let namedType = provider.suggestedName.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }
        // PDF 等文件可能同时提供图片预览；明确的原始文档优先于其缩略图。
        if let document = types.first(where: { type in
            guard type.conforms(to: .data), type != .data, !type.conforms(to: .url), !type.conforms(to: .image),
                  type != .html, type != .rtf, type != .rtfd else { return false }
            // NSString 的文本表示不能被当成文件；有文件名的 txt 和 JSON 文件可以。
            if type.conforms(to: .text) {
                return type == .json || type == .xml || namedType?.conforms(to: type) == true
            }
            return true
        }) { return document.identifier }
        if let image = types.first(where: { $0.conforms(to: .image) }) { return image.identifier }
        if provider.canLoadObject(ofClass: UIImage.self) { return UTType.image.identifier }
        return types.contains(.data) && provider.suggestedName?.isEmpty == false ? UTType.data.identifier : nil
    }
}

/// 令 UIKit 先按剪贴板顺序组合结果，再在目标选区一次性插入有序内容；不等待文件导入。
@available(iOS 26.0, *)
final class IMessageChatPasteCoordinator: NSObject, UITextPasteDelegate {
    private static let generationKey = NSAttributedString.Key("imessage.paste.generation")
    private struct SelectionSnapshot {
        let selection: NSRange
        let text: String
    }
    private final class Token: NSTextAttachment {
        let source: IMessageChatPasteSource
        let generation: Int
        let snapshot: SelectionSnapshot?
        init(_ source: IMessageChatPasteSource, generation: Int, snapshot: SelectionSnapshot?) {
            self.source = source
            self.generation = generation
            self.snapshot = snapshot
            super.init(data: nil, ofType: nil)
        }
        required init?(coder: NSCoder) { return nil }
    }

    private weak var textView: IMessageChatTextView?
    private var generation = 0
    private var selectionSnapshot: SelectionSnapshot?
    private var pendingItems: [UUID: any UITextPasteItem] = [:]
    private var pendingLoads: [UUID: Progress] = [:]
    var insertAttachments: (([IMessageChatPasteSource]) -> Void)?
    var textDidChange: (() -> Void)?

    init(textView: IMessageChatTextView) {
        self.textView = textView
        super.init()
        textView.pasteDelegate = self
        textView.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.item.identifier])
        // 智能插入会在自定义附件周围注入空格，甚至让纯附件粘贴替换正文选区。
        textView.smartInsertDeleteType = .no
        textView.willPaste = { [weak self, weak textView] in
            guard let textView else { return }
            self?.selectionSnapshot = SelectionSnapshot(selection: textView.selectedRange, text: textView.textStorage.string)
        }
    }

    func invalidate() {
        generation += 1
        selectionSnapshot = nil
        let items = Array(pendingItems.values)
        pendingItems.removeAll()
        for progress in pendingLoads.values { progress.cancel() }
        pendingLoads.removeAll()
        for item in items { item.setNoResult() }
    }

    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                          transform item: any UITextPasteItem) {
        guard textView?.isInputSuspended == false else { item.setNoResult(); return }
        let provider = item.itemProvider
        let current = generation
        let snapshot = selectionSnapshot
        if let type = IMessageChatPasteSource.fileType(in: provider) {
            item.setResult(attachment: Token(.provider(provider, typeIdentifier: type), generation: current, snapshot: snapshot))
            return
        }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier
            : provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier
            : UTType.plainText.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { item.setNoResult(); return }
        let id = UUID()
        pendingItems[id] = item
        if type != UTType.fileURL.identifier, provider.canLoadObject(ofClass: NSString.self) {
            pendingLoads[id] = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                let text = value as? String
                Task { @MainActor [weak self] in
                    self?.finishText(id: id, generation: current, string: text, isFileURL: false, snapshot: snapshot)
                }
            }
            return
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, _ in
            // 将跨回调的数据转换为值；不把系统提供器的临时 URL 作为文件所有权。
            // 跨进程剪贴板也可能将请求的纯文本物化为临时文件；该 URL 不是正文。
            let representationURL = value as? URL
            let materializedText = type != UTType.fileURL.identifier && representationURL?.isFileURL == true
            let data = (value as? Data) ?? (materializedText ? representationURL.flatMap { try? Data(contentsOf: $0) } : nil)
            let string = (value as? String) ?? data.flatMap { String(data: $0, encoding: .utf8) }
                ?? (materializedText ? nil : representationURL?.absoluteString)
            Task { @MainActor [weak self] in
                self?.finishText(id: id, generation: current, string: string, isFileURL: type == UTType.fileURL.identifier, snapshot: snapshot)
            }
        }
    }

    private func finishText(id: UUID, generation current: Int, string: String?, isFileURL: Bool, snapshot: SelectionSnapshot?) {
        pendingLoads[id] = nil
        guard let item = pendingItems.removeValue(forKey: id) else { return }
        guard generation == current, textView?.isInputSuspended == false else { item.setNoResult(); return }
        if isFileURL, let string, let url = URL(string: string), url.isFileURL {
            item.setResult(attachment: Token(.fileURL(url), generation: current, snapshot: snapshot))
        } else if let string, let url = IMessageChatPasteSource.webURL(in: string) {
            item.setResult(attachment: Token(.link(url), generation: current, snapshot: snapshot))
        } else if let string {
            item.setResult(attributedString: NSAttributedString(string: string, attributes: [Self.generationKey: current]))
        } else { item.setNoResult() }
    }

    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                          combineItemAttributedStrings itemStrings: [NSAttributedString],
                                          for textRange: UITextRange) -> NSAttributedString {
        // UIKit 默认拼接可能在附件边界加入智能空格；这些空格不能变成用户正文。
        let result = NSMutableAttributedString(string: "")
        for string in itemStrings { result.append(string) }
        var hasAttachments = false
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if value is Token { hasAttachments = true }
        }
        if hasAttachments {
            let current = generation
            // 让 UIKit 先结束空的原生粘贴事务，再提交附件批次。否则其收尾步骤会
            // 在已插入附件的编辑器中追加智能空格、按旧位置折叠选区。
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == current, let textView, !textView.isInputSuspended else { return }
                _ = self.textPasteConfigurationSupporting(textView, performPasteOf: result, to: textRange)
            }
            return NSAttributedString(string: "")
        }
        return result
    }

    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
                                          performPasteOf attributedString: NSAttributedString,
                                          to textRange: UITextRange) -> UITextRange {
        guard let textView, !textView.isInputSuspended else { return textRange }
        guard attributedString.length > 0 else {
            return textView.textRange(from: textRange.start, to: textRange.start) ?? textRange
        }
        var targetSelection = NSRange(
            location: textView.offset(from: textView.beginningOfDocument, to: textRange.start),
            length: textView.offset(from: textRange.start, to: textRange.end)
        )
        var expired = false
        attributedString.enumerateAttribute(Self.generationKey, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
            if let value = value as? Int, value != generation { expired = true }
        }
        guard !expired else { return textRange }
        var sources: [IMessageChatPasteSource] = []
        var hasAttachments = false
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length)) { attrs, range, _ in
            if let token = attrs[.attachment] as? Token {
                guard token.generation == generation else { expired = true; return }
                hasAttachments = true
                sources.append(token.source)
                if let snapshot = token.snapshot, snapshot.text == textView.textStorage.string {
                    targetSelection = snapshot.selection
                }
            } else if attrs[.attachment] == nil {
                sources.append(.text((attributedString.string as NSString).substring(with: range)))
            }
        }
        guard !expired, targetSelection.location >= 0, NSMaxRange(targetSelection) <= textView.textStorage.length else { return textRange }
        if hasAttachments {
            textView.selectedRange = targetSelection
            insertAttachments?(sources)
        } else {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: targetSelection.location),
                  let end = textView.position(from: start, offset: targetSelection.length),
                  let replacementRange = textView.textRange(from: start, to: end) else { return textRange }
            textView.replace(replacementRange, withText: attributedString.string)
            textDidChange?()
        }
        return textView.selectedTextRange ?? textRange
    }
}
