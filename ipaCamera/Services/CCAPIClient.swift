import Foundation
import OSLog

/// CCAPI 底层 HTTP 通信客户端
///
/// 封装佳能 CCAPI (Canon Camera Control API) 的 REST 请求。
/// 相机 Wi-Fi 连接模式下，CCAPI 监听在 http://192.168.1.1/ccapi/ver100/
///
/// 特性：
/// - 统一的 HTTP 方法封装 (GET/POST/PUT/DELETE)
/// - 自动重试（可配置次数和重试条件）
/// - 请求/响应日志
/// - 图片流和 MJPEG 流支持
final class CCAPIClient {
    // MARK: - 常量

    /// 相机 IP 地址（佳能相机 Wi-Fi 直连默认 IP）
    static let cameraIP = "192.168.1.1"
    /// CCAPI 基础路径
    static let basePath = "/ccapi"
    /// API 版本路径
    static let apiVersion = "/ver100"
    /// 请求超时时间
    static let requestTimeout: TimeInterval = 5.0
    /// 图片下载超时时间
    static let imageDownloadTimeout: TimeInterval = 30.0
    /// 最大重试次数
    static let maxRetryCount = 2
    /// 重试延迟（秒）
    static let retryDelay: TimeInterval = 1.0

    /// 可重试的错误类型
    private static let retryableErrors: [CCAPIError] = [
        .timeout,
        .connectionFailed,
    ]

    // MARK: - 属性

    /// 完整的基础 URL
    var baseURL: URL {
        URL(string: "http://\(Self.cameraIP):80\(Self.basePath)\(Self.apiVersion)")!
    }

    /// 探测 URL（无版本号）
    var probeURL: URL {
        URL(string: "http://\(Self.cameraIP):80\(Self.basePath)")!
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger

    // MARK: - 初始化

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.requestTimeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.logger = Logger(subsystem: "com.ipaCamera", category: "CCAPIClient")
    }

    // MARK: - 探测

    /// 探测相机是否可达
    /// - Returns: 探测响应（API 版本、设备名等）
    func probe() async throws -> CCAPIProbeResponse {
        logger.info("🔍 探测相机: \(self.probeURL)")
        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0

        let data = try await performRequestWithRetry(request)
        let response = try decoder.decode(CCAPIProbeResponse.self, from: data)
        logger.info("✅ 探测成功: \(response.deviceName) (API v\(response.apiVersion))")
        return response
    }

    // MARK: - HTTP 方法

    /// GET 请求
    /// - Parameter path: API 路径（相对于 baseURL）
    /// - Returns: JSON Data
    func get(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequestWithRetry(request)
    }

    /// POST 请求
    /// - Parameters:
    ///   - path: API 路径
    ///   - body: JSON 可编码的请求体
    /// - Returns: JSON Data
    func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await performRequestWithRetry(request)
    }

    /// POST 请求（无请求体）
    /// - Parameter path: API 路径
    /// - Returns: JSON Data
    func post(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequestWithRetry(request)
    }

    /// PUT 请求
    /// - Parameters:
    ///   - path: API 路径
    ///   - body: JSON 可编码的请求体
    /// - Returns: JSON Data
    func put<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await performRequestWithRetry(request)
    }

    /// DELETE 请求
    /// - Parameter path: API 路径
    /// - Returns: JSON Data
    func delete(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequestWithRetry(request)
    }

    // MARK: - 原始数据请求（用于图片/流媒体）

    /// GET 原始字节数据（用于图片下载等）
    /// - Parameter path: API 路径
    /// - Returns: 原始 Data
    func getData(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        logger.info("📥 下载数据: \(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.imageDownloadTimeout
        return try await performRequestWithRetry(request)
    }

    // MARK: - HTTP 流（用于 MJPEG 实时取景）

    /// 创建 HTTP 字节流
    /// - Parameter path: API 路径
    /// - Returns: URLSession.AsyncBytes
    func getStream(_ path: String) async throws -> URLSession.AsyncBytes {
        let url = baseURL.appendingPathComponent(path)
        logger.info("📡 开启流: \(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = .infinity  // 流连接不超时
        let (bytes, response) = try await session.bytes(for: request)
        try validateResponse(response)
        logger.info("📡 流已建立")
        return bytes
    }

    // MARK: - 私有方法

    /// 执行 HTTP 请求（带重试）
    private func performRequestWithRetry(_ request: URLRequest, retryCount: Int = 0) async throws -> Data {
        logRequest(request)

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            logResponse(response, data: data)
            return data
        } catch let error as CCAPIError {
            // 判断是否可重试
            if retryCount < Self.maxRetryCount && shouldRetry(error) {
                logger.warning("⏳ 重试 #\(retryCount + 1)  (原因: \(error.localizedDescription))")
                try await Task.sleep(nanoseconds: UInt64(Self.retryDelay * 1_000_000_000))
                return try await performRequestWithRetry(request, retryCount: retryCount + 1)
            }
            throw error
        } catch {
            // 将 URLError 转为 CCAPIError
            let ccapiError = mapURLError(error)
            if retryCount < Self.maxRetryCount && shouldRetry(ccapiError) {
                logger.warning("⏳ 重试 #\(retryCount + 1)  (原因: \(error.localizedDescription))")
                try await Task.sleep(nanoseconds: UInt64(Self.retryDelay * 1_000_000_000))
                return try await performRequestWithRetry(request, retryCount: retryCount + 1)
            }
            throw ccapiError
        }
    }

    /// 判断错误是否可重试
    private func shouldRetry(_ error: CCAPIError) -> Bool {
        switch error {
        case .timeout, .connectionFailed, .cameraNotConnected:
            return true
        case .httpError(let code, _):
            // 5xx 服务端错误可重试
            return code >= 500
        default:
            return false
        }
    }

    /// 将 URLError 映射为 CCAPIError
    private func mapURLError(_ error: Error) -> CCAPIError {
        if let ccapiError = error as? CCAPIError {
            return ccapiError
        }
        guard let urlError = error as? URLError else {
            return .unknown(error)
        }
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionFailed
        case .cannotFindHost, .dnsLookupFailed:
            return .cameraNotFound
        default:
            return .connectionFailed
        }
    }

    /// 验证 HTTP 响应
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CCAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 404:
            throw CCAPIError.cameraNotFound
        default:
            throw CCAPIError.httpError(httpResponse.statusCode, nil)
        }
    }

    // MARK: - 日志

    private func logRequest(_ request: URLRequest) {
        guard let url = request.url else { return }
        let method = request.httpMethod ?? "UNKNOWN"
        let bodySize = request.httpBody?.count ?? 0
        logger.debug("➡️ \(method) \(url.lastPathComponent) (\(bodySize)B)")
    }

    private func logResponse(_ response: URLResponse, data: Data) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        let statusEmoji: String
        switch httpResponse.statusCode {
        case 200...299: statusEmoji = "✅"
        case 300...399: statusEmoji = "↪️"
        case 400...499: statusEmoji = "⚠️"
        default:        statusEmoji = "❌"
        }
        logger.debug("\(statusEmoji) \(httpResponse.statusCode) (\(data.count)B)")
    }
}
