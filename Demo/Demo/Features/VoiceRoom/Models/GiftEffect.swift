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

    /// 校验并返回素材的远程 URL，不发起网络请求。
    ///
    /// - Parameter pathExtension: 期望的小写文件扩展名，不含句点。
    /// - Returns: 使用 HTTP 或 HTTPS、主机非空且扩展名匹配的 URL；校验失败时为 `nil`。
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

    /// 从指定资源包读取并解码完整素材清单。
    ///
    /// - Parameters:
    ///   - name: JSON 资源名称，不含扩展名。
    ///   - bundle: 查找清单的资源包；默认值为主资源包。
    /// - Returns: 保持 JSON 原始顺序的素材条目。
    /// - Throws: 资源缺失、文件读取或 JSON 解码错误。
    static func entries(named name: String, bundle: Bundle = .main) throws -> [GiftEffectResourceEntry] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([GiftEffectResourceEntry].self, from: Data(contentsOf: url))
    }

    /// 读取本地素材清单，并保留名称唯一且远程地址有效的条目。
    ///
    /// 同名条目只保留第一项有效记录；名称不同但 URL 相同的条目仍保留。此方法不下载动画素材。
    ///
    /// - Parameters:
    ///   - name: JSON 资源名称，不含扩展名。
    ///   - pathExtension: 期望的小写素材扩展名。
    /// - Returns: 按配置顺序排列的有效条目；读取失败时记录诊断并返回空数组。
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

    /// 按素材名称读取并校验对应的远程地址。
    ///
    /// - Parameters:
    ///   - list: JSON 清单名称，不含扩展名。
    ///   - name: 清单中匹配的原始素材名称。
    ///   - pathExtension: 期望的小写素材扩展名。
    /// - Returns: 首个匹配条目的有效地址；找不到、校验失败或清单读取失败时为 `nil`。
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
