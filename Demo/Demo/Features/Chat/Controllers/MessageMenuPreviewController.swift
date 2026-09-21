import AppLocalization
import AVFoundation
import PDFKit
import QuickLayout
import QuickLayoutKit
import QuickLookThumbnailing
import UIKit
import WebKit

/// 菜单仅承载单项内容；不包含完整浏览器的分页、缩放手势或工具栏。
@MainActor
final class MessageMenuPreviewController: QuickLayoutHostingController, WKNavigationDelegate, WKUIDelegate {
    let target: MessageMenuTarget
    let attachment: Attachment
    let kind: MessageMenuPreviewKind
    let page = AttachmentPreviewPage(frame: .zero)
    let playback: AttachmentPreviewPlayer
    private(set) var webView: WKWebView?
    private(set) var isFinished = false
    private(set) var hasAppeared = false
    private(set) var didStartVideo = false
    var openContent: ((MessagePreviewPlayback?) -> Void)?
    private let imageLoader: MediaImageLoader
    private let playbackCoordinator: PlaybackCoordinator
    private let allowsAutoplay: () -> Bool
    private let isValid: () -> Bool
    private let webLoader: ((WKWebView, URL) -> Void)?
    private let maximumContentSize: CGSize
    private var videoSizeObservation: NSKeyValueObservation?
    private let placeholder = UIImageView()
    private let status = UILabel()
    private let loading = UIActivityIndicatorView(style: .medium)
    private var preparation: Task<Void, Never>?
    private var webTimeout: Task<Void, Never>?
    private var imageRequest: MediaImageLoader.Request?
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    private var observers: [NSObjectProtocol] = []
    private var autoplayAtOpening = false
    private var committed = false
    private var webHasFailed = false

    override var body: Layout {
        ZStack {
            page.resizable()
            placeholder.resizable()
            if let webView { webView.resizable() }
            status.resizable().padding(20)
            loading.resizable().frame(width: 32, height: 32)
        }
    }

    init(target: MessageMenuTarget, attachment: Attachment, kind: MessageMenuPreviewKind,
         imageLoader: MediaImageLoader, playbackCoordinator: PlaybackCoordinator,
         allowsAutoplay: @escaping () -> Bool, isValid: @escaping () -> Bool,
         webLoader: ((WKWebView, URL) -> Void)? = nil,
         maximumContentSize: CGSize = CGSize(width: 360, height: 440)) {
        self.target = target
        self.attachment = attachment
        self.kind = kind
        self.imageLoader = imageLoader
        self.playbackCoordinator = playbackCoordinator
        self.allowsAutoplay = allowsAutoplay
        self.isValid = isValid
        self.webLoader = webLoader
        self.maximumContentSize = maximumContentSize
        playback = AttachmentPreviewPlayer(coordinator: playbackCoordinator)
        super.init(nibName: nil, bundle: nil)
        let ratio: CGFloat = kind == .video ? 0.75 : 1.2
        preferredContentSize = CGSize(width: maximumContentSize.width,
                                      height: min(maximumContentSize.width * ratio, maximumContentSize.height))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 已知媒体元数据和异步加载出的文件尺寸共用同一个等比约束，迟到结果不得改变退出动画。
    func updateContentSize(_ size: CGSize) {
        guard !isFinished, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let scale = min(maximumContentSize.width / size.width, maximumContentSize.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        guard abs(fitted.width - preferredContentSize.width) > 0.5 || abs(fitted.height - preferredContentSize.height) > 0.5 else { return }
        preferredContentSize = fitted
    }

    override func viewDidLoad() {
        quickLayoutKeyboardSafeAreaBehavior = .disabled
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.clipsToBounds = true
        view.accessibilityIdentifier = "imessage.menu.preview"
        page.isMenuPreview = true
        page.isUserInteractionEnabled = false
        page.backgroundColor = .black
        page.photoGeometryDidChange = { [weak self] in
            guard let self, (kind == .image || kind == .livePhoto), page.hasOriginalImage,
                  isValid(), let size = page.imageView.image?.size else { return }
            updateContentSize(size)
        }
        page.pageDidChange = { [weak self] _, _ in
            guard let self, isValid(), let first = page.pdfView?.document?.page(at: 0) else { return }
            updateContentSize(first.bounds(for: .cropBox).applying(first.transform(for: .cropBox)).size)
        }
        placeholder.contentMode = .scaleAspectFit
        placeholder.accessibilityIdentifier = "imessage.menu.preview.thumbnail"
        placeholder.isHidden = true
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = .label
        status.numberOfLines = 0
        status.textAlignment = .center
        status.isHidden = true
        status.accessibilityIdentifier = "imessage.menu.preview.status"
        loading.hidesWhenStopped = true
        playback.didChange = { [weak self] in self?.startVideoIfReady() }
        playback.didFail = { [weak self] in self?.showFailure() }
        let stop: @MainActor @Sendable () -> Void = { [weak self] in self?.finish() }
        for name in [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification,
                     AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                if name == AVAudioSession.routeChangeNotification,
                   (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) != AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { return }
                MainActor.assumeIsolated { stop() }
            })
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppeared, !isFinished, isValid() else { return }
        hasAppeared = true
        autoplayAtOpening = allowsAutoplay()
        if case .link(let link) = attachment { loadWeb(link); return }
        loading.startAnimating()
        let attachment = attachment
        preparation = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) { AttachmentPreviewItem.prepare(attachment).first }
            let item = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
            guard !Task.isCancelled, let self, !isFinished, isValid() else { return }
            guard let item, item.kind != .unavailable else { showFailure(); return }
            loading.stopAnimating()
            if kind == .quickLook || item.kind == .quickLook { loadQuickLook(item); return }
            page.configure(item, imageLoader: imageLoader, isVisible: true, playbackCoordinator: playbackCoordinator)
            page.setOriginalActive(true)
            if kind == .livePhoto {
                page.autoplayLivePhotoOnce { [weak self] in self?.canAutoplay == true }
            } else if kind == .video {
                playback.prepare(url: item.url)
                let updateSize: @MainActor @Sendable (CGSize) -> Void = { [weak self] size in
                    guard let self, isValid() else { return }
                    updateContentSize(size)
                }
                videoSizeObservation = playback.player?.currentItem?.observe(\.presentationSize, options: [.initial, .new]) { item, _ in
                    let size = item.presentationSize
                    Task { @MainActor in updateSize(size) }
                }
                page.bind(player: playback.player)
                startVideoIfReady()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finish()
        webView?.removeFromSuperview()
        webView = nil
    }

    private var canAutoplay: Bool {
        hasAppeared && !isFinished && autoplayAtOpening && allowsAutoplay() && isValid()
            && UIApplication.shared.applicationState == .active
    }

    private func startVideoIfReady() {
        if kind == .video {
            let seconds = Int(max(0, playback.time))
            view.accessibilityValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        guard !didStartVideo, kind == .video, canAutoplay,
              playback.player?.currentItem?.status == .readyToPlay else { return }
        didStartVideo = true
        playback.toggle()
    }

    /// 先捕获状态再停止输出；提交闭包在系统菜单转场完成后调用，且只交付一次。
    func commitAction() -> (() -> Void)? {
        guard !committed, !isFinished, isValid() else { return nil }
        committed = true
        let snapshot: MessagePreviewPlayback? = (kind == .video || kind == .livePhoto)
            ? .init(time: playback.time, isPlaying: playback.isPlaying || playback.activationTask != nil,
                    playLivePhoto: kind == .livePhoto && canAutoplay) : nil
        let open = openContent
        let valid = isValid
        finish()
        return { guard valid() else { return }; open?(snapshot) }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        videoSizeObservation = nil
        preparation?.cancel(); preparation = nil
        webTimeout?.cancel(); webTimeout = nil
        if let thumbnailRequest { QLThumbnailGenerator.shared.cancel(thumbnailRequest) }
        thumbnailRequest = nil
        imageLoader.cancel(imageRequest); imageRequest = nil
        playback.stop()
        page.cancelLoadingPreservingDisplay()
        webView?.stopLoading()
        webView?.setAllMediaPlaybackSuspended(true)
        webView?.removeFromSuperview()
        webView = nil
        if isViewLoaded { setNeedsQuickLayout(); quickLayoutIfNeeded() }
        loading.stopAnimating()
    }

    private func showFailure() {
        guard !isFinished else { return }
        playback.stop()
        page.cancelLoadingPreservingDisplay()
        loading.stopAnimating()
        status.text = Localization.text(kind == .livePhoto ? "imessage.preview.live.unavailable" : "imessage.preview.unavailable")
        status.isHidden = false
        page.isHidden = true
    }

    private func loadQuickLook(_ item: AttachmentPreviewItem) {
        page.isHidden = true
        placeholder.isHidden = false
        loading.startAnimating()
        let size = preferredContentSize.width > 0 ? preferredContentSize : CGSize(width: 360, height: 400)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: size, scale: traitCollection.displayScale, representationTypes: .thumbnail)
        thumbnailRequest = request
        preparation = Task { [weak self] in
            do {
                let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled, let self, !isFinished, isValid() else { return }
                thumbnailRequest = nil
                loading.stopAnimating()
                placeholder.image = result.uiImage
                updateContentSize(result.uiImage.size)
            } catch {
                guard !Task.isCancelled, let self, !isFinished else { return }
                showFailure()
            }
        }
    }

    private func loadWeb(_ link: LinkAttachment) {
        page.isHidden = true
        status.text = [link.title, link.url.host].compactMap { $0 }.joined(separator: "\n")
        status.isHidden = false
        placeholder.isHidden = false
        if let url = link.imageURL {
            imageRequest = imageLoader.load(url: url, pixels: 800) { [weak self] image in
                guard let self, !isFinished else { return }; placeholder.image = image
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setAllMediaPlaybackSuspended(true)
        web.isUserInteractionEnabled = false
        web.isHidden = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.accessibilityIdentifier = "imessage.menu.preview.web"
        webView = web
        setNeedsQuickLayout()
        loading.startAnimating()
        webTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            self?.webFailed()
        }
        if let webLoader { webLoader(web, link.url) }
        else { web.load(URLRequest(url: link.url, timeoutInterval: 15)) }
    }

    private func webFailed() {
        guard !isFinished, !webHasFailed else { return }
        webHasFailed = true
        webTimeout?.cancel(); webTimeout = nil
        webView?.stopLoading()
        webView?.isHidden = true
        loading.stopAnimating()
        let domain: String = if case .link(let link) = attachment { link.url.host ?? link.url.absoluteString } else { "" }
        status.text = Localization.text("imessage.menu.webUnavailable") + "\n" + domain
        status.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isFinished, !webHasFailed, isValid() else { return }
        webTimeout?.cancel(); webTimeout = nil
        loading.stopAnimating()
        placeholder.isHidden = true
        status.isHidden = true
        webView.isHidden = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { webFailed() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { webFailed() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webFailed() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(!isFinished && MessageMenuPreviewPolicy.allowsWebNavigation(navigationAction.request.url) ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(!isFinished && navigationResponse.canShowMIMEType ? .allow : .cancel)
        if !isFinished && !navigationResponse.canShowMIMEType { webFailed() }
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) { completionHandler() }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) { completionHandler(false) }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) { completionHandler(nil) }

    isolated deinit {
        preparation?.cancel()
        webTimeout?.cancel()
        if let thumbnailRequest { QLThumbnailGenerator.shared.cancel(thumbnailRequest) }
        imageLoader.cancel(imageRequest)
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
