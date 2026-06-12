import Foundation
import OSLog
import UIKit

/// 照片内容服务
///
/// 封装 CCAPI contents 相关接口：照片列表、缩略图、原图、详情
final class ContentService {
    private let client: CCAPIClient
    private let logger: Logger
    private let decoder: JSONDecoder

    /// 每页加载数量
    static let pageSize = 50

    init(client: CCAPIClient = CCAPIClient()) {
        self.client = client
        self.logger = Logger(subsystem: "com.ipaCamera", category: "ContentService")
        self.decoder = JSONDecoder()
    }

    // MARK: - 获取照片列表

    /// 获取照片 ID 列表（分页）
    /// - Parameters:
    ///   - offset: 偏移量
    ///   - limit: 数量限制
    /// - Returns: 内容 ID 列表
    func getContentIds(offset: Int = 0, limit: Int = Self.pageSize) async throws -> [String] {
        let path = "contents/sd?offset=\(offset)&limit=\(limit)&sortOrder=newest_first"
        let data = try await client.get(path)
        let response = try decoder.decode(ContentListResponse.self, from: data)
        logger.info("📋 获取照片列表: \(response.contentIds.count) 张 (offset=\(offset))")
        return response.contentIds
    }

    /// 获取照片列表（含完整元数据）
    /// - Parameters:
    ///   - offset: 偏移量
    ///   - limit: 数量限制
    /// - Returns: 分页照片列表
    func getContents(offset: Int = 0, limit: Int = Self.pageSize) async throws -> PaginatedContent {
        let ids = try await getContentIds(offset: offset, limit: limit)

        // 并发获取每张照片的详情
        let contents = try await withThrowingTaskGroup(of: PhotoContent?.self) { group in
            for id in ids {
                group.addTask {
                    try? await self.getContentDetail(id: id)
                }
            }

            var results: [PhotoContent] = []
            for try await content in group {
                if let content = content {
                    results.append(content)
                }
            }
            // 按原始顺序排序
            return ids.compactMap { id in
                results.first { $0.id == id || $0.id.hasSuffix(id) }
            }
        }

        let hasMore = contents.count >= limit
        return PaginatedContent(contents: contents, hasMore: hasMore, totalCount: nil)
    }

    // MARK: - 照片详情

    /// 获取单张照片详情
    /// - Parameter id: 内容 ID
    /// - Returns: 照片元数据
    func getContentDetail(id: String) async throws -> PhotoContent {
        let path = "contents/sd/\(id)"
        let data = try await client.get(path)
        var content = try decoder.decode(PhotoContent.self, from: data)
        // 确保 id 正确
        if !content.id.contains(id) {
            content = PhotoContent(
                id: id,
                name: content.name,
                size: content.size,
                date: content.date,
                width: content.width,
                height: content.height,
                isRaw: content.isRaw,
                directory: content.directory
            )
        }
        return content
    }

    // MARK: - 缩略图

    /// 获取缩略图
    /// - Parameter id: 内容 ID
    /// - Returns: UIImage
    func getThumbnail(id: String) async throws -> UIImage {
        let path = "contents/sd/\(id)/image?size=small"
        let data = try await client.getData(path)
        guard let image = UIImage(data: data) else {
            throw CCAPIError.invalidResponse
        }
        return image
    }

    // MARK: - 原图

    /// 获取原图数据
    /// - Parameter id: 内容 ID
    /// - Returns: 图片原始 Data
    func getOriginalImageData(id: String) async throws -> Data {
        let path = "contents/sd/\(id)/image"
        logger.info("📥 下载原图: \(id)")
        return try await client.getData(path)
    }

    /// 获取原图 UIImage
    /// - Parameter id: 内容 ID
    /// - Returns: UIImage
    func getOriginalImage(id: String) async throws -> UIImage {
        let data = try await getOriginalImageData(id: id)
        guard let image = UIImage(data: data) else {
            throw CCAPIError.invalidResponse
        }
        return image
    }

    // MARK: - 删除

    /// 删除照片
    /// - Parameter id: 内容 ID
    func deleteContent(id: String) async throws {
        let path = "contents/sd/\(id)"
        logger.info("🗑️ 删除: \(id)")
        _ = try await client.delete(path)
    }
}
