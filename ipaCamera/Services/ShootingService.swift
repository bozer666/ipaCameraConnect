import Foundation
import OSLog

/// 拍摄控制服务
///
/// 封装佳能 CCAPI 的拍摄控制和参数读写接口。
/// 支持：快门控制、参数读写（光圈/快门/ISO/曝光补偿等）、拍摄模式设置。
final class ShootingService {
    private let client: CCAPIClient
    private let logger: Logger

    /// 快门请求体
    private struct ShutterButtonRequest: Encodable {
        let af: Bool?
        let shutterbutton: Int?

        /// 半按（对焦）
        static func halfPress() -> ShutterButtonRequest {
            ShutterButtonRequest(af: true, shutterbutton: nil)
        }

        /// 全按（拍照）
        static func fullPress() -> ShutterButtonRequest {
            ShutterButtonRequest(af: nil, shutterbutton: 1)
        }

        /// 释放
        static func release() -> ShutterButtonRequest {
            ShutterButtonRequest(af: nil, shutterbutton: 0)
        }
    }

    // MARK: - 初始化

    init(client: CCAPIClient = CCAPIClient()) {
        self.client = client
        self.logger = Logger(subsystem: "com.ipaCamera", category: "ShootingService")
    }

    // MARK: - 快门控制

    /// 全按快门（拍照）
    func pressShutter() async throws {
        logger.info("📸 按下快门")
        _ = try await client.post("shooting/control/shutterbutton", body: ShutterButtonRequest.fullPress())
        // 短暂延迟后释放快门
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2秒
        _ = try await client.post("shooting/control/shutterbutton", body: ShutterButtonRequest.release())
        logger.info("✅ 快门释放完成")
    }

    /// 半按快门（对焦）
    func pressShutterHalf() async throws {
        logger.info("🔍 半按快门（对焦）")
        _ = try await client.post("shooting/control/shutterbutton", body: ShutterButtonRequest.halfPress())
    }

    /// 释放快门
    func releaseShutter() async throws {
        logger.info("🔓 释放快门")
        _ = try await client.post("shooting/control/shutterbutton", body: ShutterButtonRequest.release())
    }

    // MARK: - 参数读写

    /// 读取拍摄参数的当前值和可选值列表
    /// - Parameter name: CCAPI 属性名（如 "aperture", "iso"）
    /// - Returns: (当前值, 可选值列表)
    func readParameter(_ name: String) async throws -> (String, [String]) {
        let path = "properties/\(name)"
        let data = try await client.get(path)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CCAPIError.invalidResponse
        }

        let currentValue: String
        if let strValue = json["value"] as? String {
            currentValue = strValue
        } else if let intValue = json["value"] as? Int {
            currentValue = "\(intValue)"
        } else if let numValue = json["value"] as? NSNumber {
            currentValue = numValue.stringValue
        } else {
            currentValue = "--"
        }

        let availableValues: [String]
        if let available = json["available"] as? [String] {
            availableValues = available
        } else if let available = json["available"] as? [Int] {
            availableValues = available.map { "\($0)" }
        } else if let available = json["available"] as? [Any] {
            availableValues = available.compactMap { value in
                (value as? String) ?? (value as? Int).map { "\($0)" }
            }
        } else {
            availableValues = []
        }

        return (currentValue, availableValues)
    }

    /// 写入拍摄参数
    /// - Parameters:
    ///   - name: CCAPI 属性名
    ///   - value: 要设置的值
    func writeParameter(_ name: String, value: String) async throws {
        let path = "properties/\(name)"
        logger.info("⚙️ 设置 \(name) = \(value)")
        // CCAPI 的 PUT 接收 {"value": <value>} 格式
        let body = ["value": value]
        _ = try await client.put(path, body: body)
    }

    /// 读取所有支持的参数
    /// - Returns: CameraProperty 列表
    func readAllParameters() async throws -> [CameraProperty] {
        let supportedParams = [
            CCAPIPropertyName.shootingMode,
            CCAPIPropertyName.aperture,
            CCAPIPropertyName.shutterSpeed,
            CCAPIPropertyName.iso,
            CCAPIPropertyName.exposureCompensation,
            CCAPIPropertyName.whiteBalance,
            CCAPIPropertyName.focusMode,
        ]

        var properties: [CameraProperty] = []
        for name in supportedParams {
            do {
                let (value, available) = try await readParameter(name)
                let prop = CameraProperty(
                    id: name,
                    name: name,
                    displayName: CCAPIPropertyName.displayName(for: name),
                    currentValue: .string(value),
                    availableValues: available.map { .string($0) }
                )
                properties.append(prop)
            } catch {
                logger.warning("⚠️ 读取参数 \(name) 失败: \(error.localizedDescription)")
            }
        }
        return properties
    }

    // MARK: - 拍摄模式

    /// 设置连拍模式
    func setContinuousShooting(_ mode: ContinuousShootingMode) async throws {
        let path = "properties/continuousshooting"
        _ = try await client.put(path, body: mode.rawValue)
    }

    /// 设置自拍定时
    func setSelfTimer(_ mode: SelfTimerMode) async throws {
        let path = "properties/selftimer"
        _ = try await client.put(path, body: mode.rawValue)
    }
}

// MARK: - 模式枚举

enum ContinuousShootingMode: String, Encodable {
    case off = "0"          // 单张
    case low = "1"          // 低速连拍
    case high = "2"         // 高速连拍
}

enum SelfTimerMode: String, Encodable {
    case off = "0"          // 关闭
    case twoSeconds = "2"   // 2秒
    case tenSeconds = "10"  // 10秒
}
