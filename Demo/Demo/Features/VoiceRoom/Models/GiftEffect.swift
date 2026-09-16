import Foundation
import OSLog

/// 礼物可组合的特效配置；原生样式和远程 URL 均为纯数据。
enum GiftEffect: Equatable, Sendable {
    /// 使用原生飞行、爆发或庆典动画，不加载远程素材。
    case native(GiftEffectStyle)
    /// 使用 VAP 透明视频播放器加载远程 MP4。
    case vap(URL)
    /// 使用 SVGA 播放器加载远程动画。
    case svga(URL)
}

/// 仓库示例清单的原始条目；显示文案另由礼物本地化键提供。
struct GiftEffectResourceEntry: Decodable, Equatable, Sendable {
    /// 上游清单中用于匹配演示素材的名称。
    let name: String
    /// 上游原始远程地址。
    let url: String

    /// 验证远程协议、主机和扩展名，不触发网络加载。
    func remoteURL(pathExtension: String) -> URL? {
        guard let value = URL(string: url),
              ["http", "https"].contains(value.scheme?.lowercased() ?? ""),
              let host = value.host, !host.isEmpty,
              value.pathExtension.lowercased() == pathExtension else { return nil }
        return value
    }
}

/// 从随 Demo 打包的 JSON 中读取远程素材地址，不持有动画文件。
enum GiftEffectResources {
    /// 只记录配置故障，避免无效素材进入可赠送目录。
    private static let logger = Logger(subsystem: "Demo.VoiceRoom", category: "GiftResources")

    /// 读取完整清单；显式传入 Bundle 可用于资源完整性验证。
    static func entries(named name: String, bundle: Bundle = .main) throws -> [GiftEffectResourceEntry] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([GiftEffectResourceEntry].self, from: Data(contentsOf: url))
    }

    /// 按配置顺序读取所有有效条目；同名重复项跳过，共用 URL 的不同礼物保留。
    /// 此处只读取本地 JSON，不加载任何远程动画素材。
    static func validEntries(named name: String, pathExtension: String) -> [GiftEffectResourceEntry] {
        do {
            var names = Set<String>()
            return try entries(named: name).filter { entry in
                guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      entry.remoteURL(pathExtension: pathExtension) != nil,
                      names.insert(entry.name).inserted else {
                    logger.error("礼物特效配置条目无效或重复：\(name, privacy: .public) / \(entry.name, privacy: .public)")
                    return false
                }
                return true
            }
        } catch {
            logger.error("无法读取礼物特效配置 \(name, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 按上游名称解析有效地址；配置错误时跳过礼物并记录诊断。
    static func remoteURL(list: String, name: String, pathExtension: String) -> URL? {
        do {
            guard let entry = try entries(named: list).first(where: { $0.name == name }),
                  let url = entry.remoteURL(pathExtension: pathExtension) else {
                logger.error("礼物特效配置条目无效：\(list, privacy: .public) / \(name, privacy: .public)")
                return nil
            }
            return url
        } catch {
            logger.error("无法读取礼物特效配置 \(list, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
