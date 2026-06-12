import Foundation
import UIKit
import Photos
import OSLog

/// 照片保存到系统相册的服务
///
/// 封装 PHPhotoLibrary 写入操作，处理授权请求和错误恢复。
final class PhotoLibrarySaver {
    static let shared = PhotoLibrarySaver()

    private let logger = Logger(subsystem: "com.ipaCamera", category: "PhotoLibrarySaver")

    private init() {}

    // MARK: - 授权

    /// 检查相册写入权限
    /// - Returns: 当前授权状态
    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    /// 请求相册写入权限
    /// - Returns: 授权结果
    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    /// 检查并请求权限
    /// - Returns: 是否已授权
    func ensureAuthorized() async -> Bool {
        let status = authorizationStatus
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await requestAuthorization() == .authorized
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 保存

    /// 保存单张图片到系统相册
    /// - Parameters:
    ///   - image: UIImage
    ///   - filename: 文件名（用于创建相册时的标识）
    /// - Returns: 是否成功
    func saveImage(_ image: UIImage, filename: String? = nil) async -> Bool {
        guard await ensureAuthorized() else {
            logger.warning("⚠️ 无相册写入权限")
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            logger.info("✅ 图片已保存到相册")
            return true
        } catch {
            logger.error("❌ 保存失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 保存图片数据到系统相册
    /// - Parameters:
    ///   - data: 图片原始数据（JPEG/HEIF）
    ///   - filename: 文件名
    /// - Returns: 是否成功
    func saveImageData(_ data: Data, filename: String? = nil) async -> Bool {
        guard await ensureAuthorized() else {
            logger.warning("⚠️ 无相册写入权限")
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            logger.info("✅ 图片数据已保存到相册")
            return true
        } catch {
            logger.error("❌ 保存失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 批量保存

    /// 批量保存图片到相册
    /// - Parameter images: [UIImage] 列表
    /// - Returns: (成功数, 失败数)
    func saveImages(_ images: [(image: UIImage, filename: String?)]) async -> (success: Int, failure: Int) {
        guard await ensureAuthorized() else {
            logger.warning("⚠️ 无相册写入权限")
            return (0, images.count)
        }

        var success = 0
        var failure = 0

        for item in images {
            let ok = await saveImage(item.image, filename: item.filename)
            if ok { success += 1 } else { failure += 1 }
        }

        logger.info("📸 批量保存完成: \(success) 成功, \(failure) 失败")
        return (success, failure)
    }

    /// 批量保存图片数据到相册
    /// - Parameter items: [(data: Data, filename: String?)] 列表
    /// - Returns: (成功数, 失败数)
    func saveImageDatas(_ items: [(data: Data, filename: String?)]) async -> (success: Int, failure: Int) {
        guard await ensureAuthorized() else {
            logger.warning("⚠️ 无相册写入权限")
            return (0, items.count)
        }

        var success = 0
        var failure = 0

        for item in items {
            let ok = await saveImageData(item.data, filename: item.filename)
            if ok { success += 1 } else { failure += 1 }
        }

        logger.info("📸 批量保存完成: \(success) 成功, \(failure) 失败")
        return (success, failure)
    }
}
