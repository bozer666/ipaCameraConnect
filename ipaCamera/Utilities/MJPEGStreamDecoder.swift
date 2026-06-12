import Foundation
import UIKit
import OSLog

/// MJPEG 流解码器
///
/// 将 HTTP multipart/x-mixed-replace 字节流解析为独立的 JPEG 帧。
/// 输出 AsyncStream<UIImage> 供 UI 层消费。
///
/// MJPEG 帧格式:
/// ```
/// --MJPEGBoundary\r\n
/// Content-Type: image/jpeg\r\n
/// Content-Length: <size>\r\n
/// \r\n
/// <JPEG binary data>
/// --MJPEGBoundary\r\n
/// ```
final class MJPEGStreamDecoder {
    // MARK: - 常量

    /// MJPEG 分隔标记
    private static let boundaryMarker = "--MJPEGBoundary".data(using: .utf8)!
    /// 帧结束标记（分隔标记 + CRLF）
    private static let boundaryEnd = "--MJPEGBoundary\r\n".data(using: .utf8)!
    /// Content-Length 头部前缀
    private static let contentLengthPrefix = "Content-Length: ".data(using: .utf8)!
    /// 空行（头部和体之间的分隔）
    private static let crlfCrlf = "\r\n\r\n".data(using: .utf8)!
    /// 单 CRLF
    private static let crlf = "\r\n".data(using: .utf8)!
    /// 扫描缓冲区大小
    private static let bufferSize = 1024 * 1024  // 1MB

    // MARK: - 属性

    private let logger: Logger
    private var isDecoding = false

    init() {
        self.logger = Logger(subsystem: "com.ipaCamera", category: "MJPEGDecoder")
    }

    // MARK: - 解码

    /// 解码 MJPEG 字节流为 UIImage 异步序列
    /// - Parameter bytes: HTTP 流字节序列
    /// - Returns: UIImage 异步流
    func decode(_ bytes: URLSession.AsyncBytes) -> AsyncStream<UIImage> {
        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self else { return }
                self.isDecoding = true
                await self.parseStream(bytes, continuation: continuation)
                self.isDecoding = false
            }
        }
    }

    /// 是否正在解码
    var isActive: Bool { isDecoding }

    // MARK: - 私有

    private func parseStream(_ bytes: URLSession.AsyncBytes, continuation: AsyncStream<UIImage>.Continuation) async {
        // 使用缓冲区来累积字节数据
        // 对于 MJPEG 流，我们需要在字节序列中查找 boundary 标记
        // 并从中提取 JPEG 数据

        var buffer = Data()
        buffer.reserveCapacity(Self.bufferSize)

        var frameStartIndex: Int? = nil
        var contentLength: Int? = nil
        var headerEndIndex: Int? = nil

        do {
            for try await byte in bytes {
                guard isDecoding else { break }

                buffer.append(byte)

                // 尝试解析帧
                if let parsed = tryParseFrame(buffer: &buffer) {
                    continuation.yield(parsed)
                }

                // 防止缓冲区无限增长
                if buffer.count > Self.bufferSize * 2 {
                    // 只保留最后 bufferSize 字节
                    buffer = buffer.suffix(Self.bufferSize)
                    logger.warning("⚠️ 缓冲区溢出，丢弃旧数据")
                }
            }
        } catch {
            if isDecoding {
                logger.warning("⚠️ 流读取错误: \(error.localizedDescription)")
            }
        }

        continuation.finish()
        logger.info("📡 流解码结束")
    }

    /// 尝试从缓冲区解析一帧 JPEG
    /// - Parameter buffer: 可变缓冲区
    /// - Returns: 解析出的 UIImage，如果数据不足返回 nil
    private func tryParseFrame(buffer: inout Data) -> UIImage? {
        // 查找 boundary 标记
        guard let boundaryRange = buffer.range(of: Self.boundaryEnd) else {
            return nil
        }

        let searchStart = boundaryRange.upperBound

        // 查找 Content-Length
        guard let clRange = buffer.range(of: Self.contentLengthPrefix, in: searchStart..<buffer.count) else {
            return nil
        }

        let valueStart = clRange.upperBound

        // 提取 Content-Length 值（直到 \r\n）
        guard let lineEnd = buffer.range(of: Self.crlf, in: valueStart..<buffer.count) else {
            return nil
        }

        let lengthStr = String(data: buffer[valueStart..<lineEnd.lowerBound], encoding: .utf8)
        guard let lengthStr = lengthStr, let length = Int(lengthStr.trimmingCharacters(in: .whitespaces)), length > 0 else {
            return nil
        }

        // 查找空行（头部结束）
        guard let headerEnd = buffer.range(of: Self.crlfCrlf, in: lineEnd.upperBound..<buffer.count) else {
            return nil
        }

        let dataStart = headerEnd.upperBound
        let frameEnd = dataStart + length

        // 检查是否有足够的 JPEG 数据
        guard frameEnd <= buffer.count else {
            return nil
        }

        // 提取 JPEG 数据
        let jpegData = buffer[dataStart..<frameEnd]

        // 移除已处理的数据（保留下一个 boundary 的部分数据）
        // 下一个帧从当前 boundary 结束开始
        // 查找下一个 boundary
        if let nextBoundary = buffer.range(of: Self.boundaryEnd, in: frameEnd..<buffer.count) {
            // 保留从下一个 boundary 开始的数据
            buffer = Data(buffer[nextBoundary.lowerBound...])
        } else {
            // 没找到下一个 boundary，只保留当前 JPEG 之后可能的新数据
            buffer = Data(buffer[frameEnd...])
        }

        // 解码 JPEG
        guard let image = UIImage(data: jpegData) else {
            logger.warning("⚠️ JPEG 解码失败")
            return nil
        }

        return image
    }
}
