import Foundation
import UIKit
import OSLog

/// 下载状态
enum DownloadState: Equatable {
    case idle
    case downloading
    case completed
    case failed(String)
}

/// 图库视图模型
///
/// 管理照片列表的加载、缓存、多选和操作状态。
@MainActor
final class GalleryViewModel: ObservableObject {
    // MARK: - Published 属性

    /// 照片列表
    @Published private(set) var contents: [PhotoContent] = []
    /// 是否正在加载
    @Published var isLoading = false
    /// 是否正在加载更多
    @Published var isLoadingMore = false
    /// 错误信息
    @Published var errorMessage: String?
    /// 是否显示错误
    @Published var showError = false
    /// 是否还有更多内容
    @Published private(set) var hasMore = true
    /// 选中的照片 ID 集合
    @Published var selectedIds: Set<String> = []
    /// 是否处于编辑/选择模式
    @Published var isSelecting = false
    /// 缩略图缓存（[contentId: UIImage]）
    @Published private(set) var thumbnails: [String: UIImage] = [:]
    /// 加载中的缩略图
    private var loadingThumbnails: Set<String> = []
    /// 下载状态 [contentId: DownloadState]
    @Published private(set) var downloadStates: [String: DownloadState] = [:]
    /// 总下载进度 (0.0 ~ 1.0)
    @Published private(set) var downloadProgress: Double = 0
    /// 是否正在批量下载
    @Published var isDownloading = false
    /// 是否显示删除确认
    @Published var showDeleteConfirmation = false
    /// 下载结果提示
    @Published var downloadResultMessage: String?
    @Published var showDownloadResult = false

    // MARK: - 服务

    private let contentService: ContentService
    private let cacheManager: ImageCacheManager
    private let photoLibrarySaver: PhotoLibrarySaver
    private let logger: Logger
    private var currentOffset = 0
    private var loadTask: Task<Void, Never>?

    // MARK: - 初始化

    init(contentService: ContentService = ContentService()) {
        self.contentService = contentService
        self.cacheManager = .shared
        self.photoLibrarySaver = .shared
        self.logger = Logger(subsystem: "com.ipaCamera", category: "GalleryViewModel")
    }

    // MARK: - 加载

    /// 加载第一页
    func loadFirstPage() async {
        loadTask?.cancel()
        loadTask = Task {
            guard !Task.isCancelled else { return }

            isLoading = true
            errorMessage = nil
            currentOffset = 0

            do {
                let result = try await contentService.getContents(offset: 0, limit: ContentService.pageSize)
                guard !Task.isCancelled else { return }

                contents = result.contents
                hasMore = result.hasMore
                currentOffset = contents.count
                selectedIds.removeAll()
                isSelecting = false
                logger.info("📸 加载首页: \(contents.count) 张")
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                showError = true
                logger.warning("⚠️ 加载失败: \(error.localizedDescription)")
            }

            isLoading = false
        }
    }

    /// 加载更多
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        loadTask?.cancel()
        loadTask = Task {
            guard !Task.isCancelled else { return }

            isLoadingMore = true

            do {
                let result = try await contentService.getContents(
                    offset: currentOffset,
                    limit: ContentService.pageSize
                )
                guard !Task.isCancelled else { return }

                contents += result.contents
                hasMore = result.hasMore
                currentOffset = contents.count
                logger.info("📸 加载更多: +\(result.contents.count) 张 (共\(contents.count))")
            } catch {
                guard !Task.isCancelled else { return }
                // 加载更多失败不阻止用户操作
                logger.warning("⚠️ 加载更多失败: \(error.localizedDescription)")
            }

            isLoadingMore = false
        }
    }

    /// 刷新
    func refresh() async {
        await loadFirstPage()
    }

    // MARK: - 缩略图

    /// 加载缩略图（带缓存）
    /// - Parameter contentId: 照片 ID
    func loadThumbnail(for contentId: String) async {
        // 已有缓存
        if thumbnails[contentId] != nil { return }
        // 正在加载
        guard !loadingThumbnails.contains(contentId) else { return }

        // 检查磁盘缓存
        let cacheKey = ImageCacheManager.thumbnailKey(for: contentId)
        if let cachedImage = cacheManager.getImage(forKey: cacheKey) {
            thumbnails[contentId] = cachedImage
            return
        }

        loadingThumbnails.insert(contentId)

        do {
            let image = try await contentService.getThumbnail(id: contentId)
            guard !Task.isCancelled else { return }

            // 保存到缓存
            cacheManager.setImage(image, forKey: cacheKey, toDisk: true)
            thumbnails[contentId] = image
        } catch {
            logger.warning("⚠️ 缩略图加载失败: \(contentId)")
        }

        loadingThumbnails.remove(contentId)
    }

    // MARK: - 选择模式

    /// 切换选择模式
    func toggleSelectMode() {
        isSelecting.toggle()
        if !isSelecting {
            selectedIds.removeAll()
        }
    }

    /// 切换选中状态
    func toggleSelection(for contentId: String) {
        if selectedIds.contains(contentId) {
            selectedIds.remove(contentId)
        } else {
            selectedIds.insert(contentId)
        }
    }

    /// 选择所有
    func selectAll() {
        selectedIds = Set(contents.map { $0.id })
    }

    /// 取消全选
    func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - 操作

    /// 下载单张照片到系统相册
    /// - Parameter contentId: 照片 ID
    func downloadToLibrary(for contentId: String) async {
        downloadStates[contentId] = .downloading

        do {
            let data = try await contentService.getOriginalImageData(id: contentId)
            let success = await photoLibrarySaver.saveImageData(data, filename: contentId)
            downloadStates[contentId] = success ? .completed : .failed("保存失败")

            if !success {
                logger.warning("⚠️ 照片保存失败: \(contentId)")
            }
        } catch {
            downloadStates[contentId] = .failed(error.localizedDescription)
            logger.warning("⚠️ 照片下载失败: \(contentId) - \(error.localizedDescription)")
        }
    }

    /// 批量下载选中照片到系统相册
    func downloadSelected() async {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }

        isDownloading = true
        downloadProgress = 0

        var successCount = 0
        var failureCount = 0

        for (index, id) in ids.enumerated() {
            downloadStates[id] = .downloading

            do {
                let data = try await contentService.getOriginalImageData(id: id)
                let success = await photoLibrarySaver.saveImageData(data, filename: id)
                if success {
                    downloadStates[id] = .completed
                    successCount += 1
                } else {
                    downloadStates[id] = .failed("保存失败")
                    failureCount += 1
                }
            } catch {
                downloadStates[id] = .failed(error.localizedDescription)
                failureCount += 1
            }

            downloadProgress = Double(index + 1) / Double(ids.count)
        }

        isDownloading = false
        selectedIds.removeAll()
        isSelecting = false

        downloadResultMessage = "下载完成: \(successCount) 张成功, \(failureCount) 张失败"
        showDownloadResult = true
        logger.info("📥 批量下载: \(successCount) 成功, \(failureCount) 失败")
    }

    /// 请求删除选中照片（弹出确认）
    func requestDeleteSelected() {
        guard !selectedIds.isEmpty else { return }
        showDeleteConfirmation = true
    }

    /// 确认删除选中照片
    /// - Returns: 是否成功
    func confirmDeleteSelected() async -> Bool {
        showDeleteConfirmation = false
        return await deleteSelected()
    }

    /// 删除选中的照片
    /// - Returns: 是否成功
    func deleteSelected() async -> Bool {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return false }

        var successCount = 0
        for id in ids {
            do {
                try await contentService.deleteContent(id: id)
                // 清除缓存
                let cacheKey = ImageCacheManager.thumbnailKey(for: id)
                cacheManager.removeImage(forKey: cacheKey)
                thumbnails.removeValue(forKey: id)
                downloadStates.removeValue(forKey: id)
                successCount += 1
            } catch {
                logger.warning("⚠️ 删除失败: \(id) - \(error.localizedDescription)")
            }
        }

        // 从列表移除
        contents.removeAll { selectedIds.contains($0.id) }
        selectedIds.removeAll()
        isSelecting = false

        logger.info("🗑️ 删除完成: \(successCount)/\(ids.count)")
        return successCount > 0
    }
}
