import Foundation

/// CCAPI 通信错误
enum CCAPIError: LocalizedError {
    /// 相机未连接
    case cameraNotConnected
    /// 请求超时
    case timeout
    /// 相机无响应
    case connectionFailed
    /// 未找到相机 (CCAPI 端点不可达)
    case cameraNotFound
    /// HTTP 响应无效
    case invalidResponse
    /// HTTP 错误状态码
    case httpError(Int, String?)
    /// 数据解析失败
    case decodingFailed(Error)
    /// 实时取流断开
    case liveViewStreamDisconnected
    /// Wi-Fi 未连接
    case wifiNotConnected
    /// 未知错误
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .cameraNotConnected:
            return "相机未连接"
        case .timeout:
            return "请求超时，请检查相机连接"
        case .connectionFailed:
            return "无法连接到相机"
        case .cameraNotFound:
            return "未找到相机，请确认相机 Wi-Fi 已开启"
        case .invalidResponse:
            return "相机响应异常"
        case .httpError(let code, let message):
            if let msg = message {
                return "相机错误 (\(code)): \(msg)"
            }
            return "相机错误 (HTTP \(code))"
        case .decodingFailed(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .liveViewStreamDisconnected:
            return "实时取景已断开"
        case .wifiNotConnected:
            return "请先连接到相机 Wi-Fi"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}
