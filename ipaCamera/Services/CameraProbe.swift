import Foundation

/// 相机探测服务
///
/// 负责在 Wi-Fi 连接后探测相机 CCAPI 端点，
/// 获取相机基本信息和 API 版本。
struct CameraProbe {
    private let client: CCAPIClient

    init(client: CCAPIClient = CCAPIClient()) {
        self.client = client
    }

    /// 探测相机连接
    /// - Returns: 相机信息
    func probeCamera() async throws -> CameraInfo {
        let response = try await client.probe()

        let apiVersionStr = response.apiVersion.map(String.init).joined(separator: ".")

        return CameraInfo(
            id: response.serialNumber ?? UUID().uuidString,
            deviceName: response.deviceName,
            manufacturer: response.manufacturer,
            apiVersion: apiVersionStr,
            firmwareVersion: response.firmwareVersion ?? "未知",
            serialNumber: response.serialNumber ?? "未知",
            ipAddress: CCAPIClient.cameraIP
        )
    }

    /// 快速检查相机是否可达（不解析完整信息）
    /// - Returns: 是否可达
    func checkReachable() async -> Bool {
        do {
            _ = try await client.probe()
            return true
        } catch {
            return false
        }
    }
}
