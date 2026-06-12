import Foundation
import UIKit
import OSLog

/// 图片缓存管理器
///
/// 两级缓存策略：
/// - 内存缓存: NSCache，快速访问，App 退出后自动释放
/// - 磁盘缓存: 沙盒 Caches 目录，App 重启后仍可访问
///
/// 缓存键格式: `thumbnail_{contentId}` / `original_{contentId}`
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache: NSCache<NSString, UIImage>
    private let diskCacheURL: URL
    private let fileManager: FileManager
    private let logger: Logger
    private let decoder: JSONDecoder

    private init() {
        self.memoryCache = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 200       // 最多缓存 200 张图片
            cache.totalCostLimit = 50 * 1024 * 1024  // 最多 50MB 内存
            return cache
        }()

        self.fileManager = FileManager.default
        self.logger = Logger(subsystem: "com.ipaCamera", category: "ImageCache")

        // 磁盘缓存目录: Caches/ImageCache/
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheURL = cachesDir.appendingPathComponent("ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        self.decoder = JSONDecoder()

        logger.info("📁 缓存目录: \(self.diskCacheURL.path)")
    }

    // MARK: - 公共方法

    /// 获取缓存图片
    /// - Parameter key: 缓存键
    /// - Returns: 缓存的图片（如果存在）
    func getImage(forKey key: String) -> UIImage? {
        // 1. 检查内存缓存
        if let image = memoryCache.object(forKey: key as NSString) {
            logger.debug("✅ 内存缓存命中: \(key)")
            return image
        }

        // 2. 检查磁盘缓存
        let diskURL = diskURL(forKey: key)
        if fileManager.fileExists(atPath: diskURL.path) {
            do {
                let data = try Data(contentsOf: diskURL)
                if let image = UIImage(data: data) {
                    // 回填内存缓存
                    memoryCache.setObject(image, forKey: key as NSString)
                    logger.debug("✅ 磁盘缓存命中: \(key)")
                    return image
                }
            } catch {
                logger.warning("⚠️ 磁盘缓存读取失败: \(error.localizedDescription)")
            }
        }

        logger.debug("❌ 缓存未命中: \(key)")
        return nil
    }

    /// 保存图片到缓存
    /// - Parameters:
    ///   - image: 图片
    ///   - key: 缓存键
    ///   - toDisk: 是否持久化到磁盘（缩略图持久化，原始大图仅内存缓存）
    func setImage(_ image: UIImage, forKey key: String, toDisk: Bool = true) {
        // 内存缓存
        let cost = Int(image.size.width * image.size.height * 4)  // 近似内存占用
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        // 磁盘缓存（异步写入）
        if toDisk {
            let diskURL = self.diskURL(forKey: key)
            Task.detached(priority: .background) {
                guard let data = image.jpegData(compressionQuality: 0.8) else { return }
                try? data.write(to: diskURL)
            }
        }
    }

    /// 移除单张缓存
    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let diskURL = self.diskURL(forKey: key)
        try? fileManager.removeItem(at: diskURL)
    }

    /// 清空所有缓存
    func clearAll() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        logger.info("🧹 缓存已清空")
    }

    /// 获取磁盘缓存大小（字节）
    var diskCacheSize: UInt64 {
        guard let files = fileManager.enumerator(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let file as URL in files {
            guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
                  let size = attributes.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    // MARK: - 私有方法

    /// 生成磁盘缓存文件 URL
    private func diskURL(forKey key: String) -> URL {
        // 使用 MD5 或 base64 编码作为文件名
        let filename = key.data(using: .utf8).map { data in
            data.base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
        } ?? key
        return diskCacheURL.appendingPathComponent(filename + ".jpg")
    }
}

// MARK: - 缓存键生成

extension ImageCacheManager {
    /// 缩略图缓存键
    static func thumbnailKey(for contentId: String) -> String {
        "thumbnail_\(contentId)"
    }

    /// 原图缓存键
    static func originalKey(for contentId: String) -> String {
        "original_\(contentId)"
    }
}
