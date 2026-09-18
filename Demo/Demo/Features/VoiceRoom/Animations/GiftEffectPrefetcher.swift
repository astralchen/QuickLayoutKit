import Foundation
import OSLog
import SVGAView
import VAPView

/// 为已入队礼物的远程特效预热播放器缓存。
///
/// 每次赠送独立登记资源需求，相同格式和 URL 的资源共享一次加载。资源去重
/// 不改变效果的播放次数或顺序。预下载独立于播放队列，不创建播放器或等待整组资源就绪。
@MainActor
final class GiftEffectPrefetcher {
    /// 预热单项效果资源的异步操作。
    ///
    /// 加载器应协作响应取消，并在其持有的底层工作退出及清理完成后返回。
    /// 测试可注入可控实现，避免依赖网络时序。原生效果无需加载。
    typealias Loader = @MainActor @Sendable (GiftEffect) async throws -> Void

    /// 格式参与身份比较，同地址的不同格式不能合并。
    private enum Resource: Hashable {
        case vap(URL)
        case svga(URL)

        init?(_ effect: GiftEffect) {
            switch effect {
            case .native: return nil
            case .vap(let url): self = .vap(url)
            case .svga(let url): self = .svga(url)
            }
        }

        var effect: GiftEffect {
            switch self {
            case .vap(let url): .vap(url)
            case .svga(let url): .svga(url)
            }
        }
    }

    /// 一次资源执行及仍需要该资源的赠送身份；终态条目保留到所有需求释放。
    private struct Entry {
        let resource: Resource
        var owners: Set<UUID>
    }

    private let queue: TaskQueue
    private let load: Loader
    private let logger = Logger(subsystem: "Demo.VoiceRoom", category: "GiftPrefetch")
    /// 请求和执行身份分离，取消后的同 URL 新请求不会被旧完成回调删除。
    private var requests: [UUID: Set<UUID>] = [:]
    private var entries: [UUID: Entry] = [:]
    private var entryByResource: [Resource: UUID] = [:]
    /// 仅保存资源执行句柄，等待顺序和槽位生命周期由通用队列负责。
    private var tasks: [UUID: Task<Void, Error>] = [:]

    /// 尚未释放的赠送需求数量，包括资源已加载完成或失败的需求。
    var requestCount: Int { requests.count }
    /// 已获得许可的加载数量，包括收到取消但尚未实际退出的任务。
    var runningCount: Int { queue.runningCount }

    /// 创建礼物特效预下载器。
    ///
    /// - Parameters:
    ///   - maxConcurrentLoads: 并发加载数量上限，必须大于零。默认值为 `2`。
    ///   - load: 资源加载操作。默认复用 VAP 和 SVGA 的加载及缓存能力。
    init(maxConcurrentLoads: Int = 2, load: @escaping Loader = GiftEffectPrefetcher.loadResource) {
        queue = TaskQueue(maxConcurrentTasks: maxConcurrentLoads)
        self.load = load
    }

    isolated deinit {
        queue.cancelAll()
    }

    /// 使用对应播放器的默认加载器预热单项效果。
    ///
    /// 底层下载是否响应取消由所引用的 SDK 版本决定；当前远程 VAP 版本的共享
    /// 下载可能继续完成。队列等待异步调用实际退出后才释放槽位，不以调用
    /// `Task.cancel()` 作为结束标志。
    ///
    /// - Parameter effect: 要预热的效果。原生效果直接返回。
    /// - Throws: 调用前已取消时抛出 `CancellationError`；加载期间传播 SDK 的取消或加载错误。
    static func loadResource(_ effect: GiftEffect) async throws {
        try Task.checkCancellation()
        switch effect {
        case .native: return
        case .vap(let url): _ = try await VAPView.prefetch(source: url.absoluteString)
        case .svga(let url): try await SVGAView.preload(remoteURL: url)
        }
        try Task.checkCancellation()
    }

    /// 为一次赠送登记资源需求，并按效果顺序提交新的加载任务。
    ///
    /// 成功或失败的资源条目均保留到全部需求释放，避免同一批有效需求循环重试。
    /// 此方法不等待预下载完成，调用方可以立即提交播放任务。
    ///
    /// - Parameter effects: 按播放顺序排列的效果配置；仅远程资源参与预下载。
    /// - Returns: 本次赠送的独立请求身份。即使没有远程资源，也应在赠送结束时释放。
    @discardableResult
    func register(effects: [GiftEffect]) -> UUID {
        let requestID = UUID()
        var executionIDs = Set<UUID>()
        for effect in effects {
            guard let resource = Resource(effect) else { continue }
            let executionID: UUID
            if let existingID = entryByResource[resource] {
                executionID = existingID
                entries[existingID]?.owners.insert(requestID)
            } else {
                executionID = UUID()
                entries[executionID] = Entry(resource: resource, owners: [requestID])
                entryByResource[resource] = executionID
                start(resource: resource, executionID: executionID)
            }
            executionIDs.insert(executionID)
        }
        requests[requestID] = executionIDs
        return requestID
    }

    /// 释放指定赠送的全部资源需求。
    ///
    /// 共享资源仅在最后一个需求离开时请求取消。重复释放不会产生副作用；
    /// 正在取消的加载在实际结束前继续占用队列槽位。
    ///
    /// - Parameter requestID: `register(effects:)` 返回的请求身份。
    func release(_ requestID: UUID) {
        guard let executionIDs = requests.removeValue(forKey: requestID) else { return }
        for executionID in executionIDs {
            guard var entry = entries[executionID] else { continue }
            entry.owners.remove(requestID)
            if entry.owners.isEmpty {
                entries[executionID] = nil
                if entryByResource[entry.resource] == executionID {
                    entryByResource[entry.resource] = nil
                }
                tasks[executionID]?.cancel()
            } else {
                entries[executionID] = entry
            }
        }
    }

    /// 清理当前全部赠送需求，并请求取消队列中的加载任务。
    ///
    /// 后续仍可登记新赠送。新任务需等待旧运行项实际退出后才能复用其槽位。
    func cancelAll() {
        // 先撤销资源归属，再触发取消，防止取消处理器重入时复用旧需求。
        requests.removeAll()
        entries.removeAll()
        entryByResource.removeAll()
        queue.cancelAll()
    }

    /// 在登记时同步提交，资源去重与错误诊断留在业务层。
    private func start(resource: Resource, executionID: UUID) {
        let effect = resource.effect
        let task = queue.addTask { [load, logger] in
            do {
                try await load(effect)
            } catch {
                if !Task.isCancelled, !(error is CancellationError) {
                    logger.error("礼物预下载失败，播放时按正常路径加载：\(error.localizedDescription, privacy: .public)")
                }
                throw error
            }
        }
        tasks[executionID] = task
        // 排队取消可能不进入操作闭包，统一观察原生句柄的终态。
        // 弱引用避免延长预下载器生命周期；独立执行身份防止旧完成回调清除新句柄。
        Task { [weak self] in
            _ = await task.result
            self?.tasks[executionID] = nil
        }
    }
}
