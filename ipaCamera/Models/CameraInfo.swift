import Foundation

/// 相机基本信息
struct CameraInfo: Codable, Identifiable {
    let id: String
    let deviceName: String
    let manufacturer: String
    let apiVersion: String
    let firmwareVersion: String
    let serialNumber: String
    let ipAddress: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "deviceName"
        case manufacturer = "manufacturer"
        case apiVersion = "apiVersion"
        case firmwareVersion = "firmwareVersion"
        case serialNumber = "serialNumber"
        case ipAddress
    }
}

/// 相机连接状态
enum CameraConnectionState: Equatable {
    /// 未连接
    case disconnected
    /// 正在连接 Wi-Fi
    case connecting
    /// 正在探测相机
    case probing
    /// 已连接
    case connected(CameraInfo)
    /// 连接失败
    case failed(String)
}

/// CCAPI 探测响应
struct CCAPIProbeResponse: Codable {
    let apiVersion: [Int]
    let deviceName: String
    let manufacturer: String
    let model: String?
    let serialNumber: String?
    let firmwareVersion: String?
}
