import ImageIO
import UIKit

/// 缩略图专用的有界后台解码器；相同 URL 和像素尺寸共享在途请求。
@MainActor
final class AttachmentThumbnailLoader {
    /// 一个消费者的可取消请求，不影响其他消费者。
    struct Request {
        /// 合并加载使用的键。
        let key: String
        /// 消费者身份。
        let id: UUID
    }
    /// 一次后台加载及其仍然有效的消费者。
    private struct Pending {
        /// 在途请求代次，防止同键旧任务回写新任务。
        let generation: UUID
        /// 可取消的后台操作。
        let operation: BlockOperation
        /// 主线程回写闭包。
        var consumers: [UUID: (UIImage?) -> Void]
    }
    /// 解码图片按实际像素成本保留，供来回浏览复用。
    private let cache = NSCache<NSString, UIImage>()
    /// 后台最多两个任务，避免快速滚动同时解码大量文件。
    private let queue = OperationQueue()
    /// 尚未完成的请求，始终由主线程访问。
    private var pending: [String: Pending] = [:]
    /// 当前请求数量，供生命周期及规模验证。
    var pendingCount: Int { pending.count }

    /// 配置固定并发和内存预算。
    init() {
        cache.totalCostLimit = 16 * 1024 * 1024
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        queue.name = "AttachmentThumbnailLoader"
    }
    /// 可见 Cell 请求图片；命中缓存时立即回写，不创建后台任务。
    func load(url: URL, pixels: Int, completion: @escaping (UIImage?) -> Void) -> Request? {
        let key = "\(pixels):\(url.absoluteString)"
        if let image = cache.object(forKey: key as NSString) { completion(image); return nil }
        let request = Request(key: key, id: UUID())
        if pending[key] != nil {
            pending[key]?.consumers[request.id] = completion
            return request
        }
        let generation = UUID()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let image = Self.decode(url: url, pixels: pixels)
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                self?.finish(key: key, generation: generation, image: image)
            }
        }
        pending[key] = Pending(generation: generation, operation: operation, consumers: [request.id: completion])
        queue.addOperation(operation)
        return request
    }
    /// 删除一个消费者；无人等待时取消并移除后台任务。
    func cancel(_ request: Request?) {
        guard let request, var entry = pending[request.key] else { return }
        entry.consumers[request.id] = nil
        if entry.consumers.isEmpty {
            entry.operation.cancel()
            pending[request.key] = nil
        } else { pending[request.key] = entry }
    }
    /// 沉浸隐藏和退出时停止所有尚未完成的图片读取。
    func cancelAll() {
        queue.cancelAllOperations()
        pending.removeAll()
    }
    /// 只有当前代次能够缓存和通知消费者。
    private func finish(key: String, generation: UUID, image: CGImage?) {
        guard let entry = pending[key], entry.generation == generation else { return }
        pending[key] = nil
        let result = image.map { UIImage(cgImage: $0) }
        if let image, let result { cache.setObject(result, forKey: key as NSString, cost: image.bytesPerRow * image.height) }
        for completion in entry.consumers.values { completion(result) }
    }
    /// 后台按短边满足方形 aspect-fill，应用 EXIF 方向并立即解码。
    nonisolated static func decode(url: URL, pixels: Int) -> CGImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
            let short = min(width.doubleValue, height.doubleValue)
            let long = max(width.doubleValue, height.doubleValue)
            guard short > 0 else { return nil }
            // 极端全景图不分配无界中间图；正常缩略图按短边完整满足显示需求。
            let maximum = min(4096, max(1, ceil(Double(pixels) * long / short)))
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum
            ] as CFDictionary)
        }
    }
    /// 析构不保留无消费者的解码工作。
    isolated deinit { queue.cancelAllOperations() }
}
