import Foundation

/// 相机服务
///
/// 高级 API，封装相机连接、探测、属性读取等操作。
/// ViewModel 通过此服务与相机通信，不直接调用 CCAPIClient。
final class CameraService {
    private let client: CCAPIClient
    private let probe: CameraProbe

    // MARK: - 初始化

    init(client: CCAPIClient = CCAPIClient()) {
        self.client = client
        self.probe = CameraProbe(client: client)
    }

    // MARK: - 连接与探测

    /// 探测相机连接
    func probeCamera() async throws -> CameraInfo {
        try await probe.probeCamera()
    }

    /// 检查相机是否可达
    func checkReachable() async -> Bool {
        await probe.checkReachable()
    }

    // MARK: - 属性读取

    /// 获取所有可用属性列表
    func getAllProperties() async throws -> [String] {
        let data = try await client.get("properties")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = json["urls"] as? [String] else {
            throw CCAPIError.invalidResponse
        }
        // 从 URL 中提取属性名
        return urls.compactMap { urlString in
            urlString.split(separator: "/").last.map(String.init)
        }
    }

    /// 读取单个属性值
    func getProperty<T: Decodable>(_ name: String) async throws -> T {
        let data = try await client.get("properties/\(name)")
        // CCAPI 返回格式: { "value": ..., "available": [...] }
        let wrapper = try JSONDecoder().decode(PropertyWrapper<T>.self, from: data)
        return wrapper.value
    }

    /// 读取属性（包括可用值列表）
    func getPropertyDetail<T: Decodable>(_ name: String) async throws -> PropertyDetail<T> {
        let data = try await client.get("properties/\(name)")
        return try JSONDecoder().decode(PropertyDetail<T>.self, from: data)
    }

    /// 写入属性值
    func setProperty<T: Encodable>(_ name: String, value: T) async throws {
        let body = PropertyValue(value: value)
        _ = try await client.put("properties/\(name)", body: body)
    }

    // MARK: - 相机状态

    /// 获取相机基本信息（简版）
    func getCameraStatus() async throws -> CameraStatus {
        let data = try await client.get("device/status")
        return try JSONDecoder().decode(CameraStatus.self, from: data)
    }
}

// MARK: - 辅助类型

/// 属性值包装（CCAPI 格式）
struct PropertyValue<T: Encodable>: Encodable {
    let value: T
}

/// 属性详情（包含当前值和可用值）
struct PropertyDetail<T: Decodable>: Decodable {
    let value: T
    let available: [T]?
}

/// 相机状态
struct CameraStatus: Codable {
    let batteryLevel: Int?
    let batteryStatus: String?
    let storageAvailable: Bool?
    let remainingShots: Int?

    enum CodingKeys: String, CodingKey {
        case batteryLevel = "batterylevel"
        case batteryStatus = "batterystatus"
        case storageAvailable = "storageavailable"
        case remainingShots = "remainingshots"
    }
}
