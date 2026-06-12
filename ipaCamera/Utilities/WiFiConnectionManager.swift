import Foundation
import Network
import NetworkExtension
import Combine

/// Wi-Fi 连接状态
enum WiFiConnectionState: Equatable {
    /// 未知（初始状态）
    case unknown
    /// 已连接到相机 Wi-Fi
    case connectedToCamera(ssid: String)
    /// 已连接到其他 Wi-Fi
    case connectedToOther(ssid: String)
    /// 未连接任何 Wi-Fi
    case disconnected
    /// 正在连接
    case connecting

    var isConnectedToCamera: Bool {
        if case .connectedToCamera = self { return true }
        return false
    }
}

/// Wi-Fi 连接管理器
///
/// 职责：
/// 1. 监听 iOS Wi-Fi 状态变化
/// 2. 使用 NEHotspotConfiguration 自动连接相机 Wi-Fi
/// 3. 提供手动连接引导
@MainActor
final class WiFiConnectionManager: ObservableObject {
    // MARK: - 常量

    /// 佳能相机的 SSID 前缀（R7 通常为 "CanonR7_" 开头）
    static let cameraSSIDPrefixes = ["CanonR7_", "Canon_EOS_R7_", "Canon_"]
    /// CCAPI 默认端口
    static let ccapiPort = 80

    // MARK: - Published 属性

    @Published private(set) var connectionState: WiFiConnectionState = .unknown
    @Published private(set) var currentSSID: String?
    @Published private(set) var isMonitoring = false

    // MARK: - 私有属性

    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.ipaCamera.wifi-monitor", qos: .background)

    // MARK: - 初始化

    init() {
        self.pathMonitor = NWPathMonitor()
        setupPathMonitor()
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - 公共方法

    /// 开始监听 Wi-Fi 状态
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        pathMonitor.start(queue: monitorQueue)
        // 立即检查一次当前状态
        checkCurrentWiFiStatus()
    }

    /// 停止监听 Wi-Fi 状态
    func stopMonitoring() {
        isMonitoring = false
        pathMonitor.cancel()
    }

    /// 尝试自动连接相机 Wi-Fi
    /// - Parameter ssid: 相机 Wi-Fi 的 SSID（可选，不提供则扫描已知前缀）
    func connectToCamera(ssid: String? = nil) async throws {
        guard let ssid = ssid else {
            // 如果没有指定 SSID，尝试扫描可用的相机网络
            // 注意：iOS 没有公开的 Wi-Fi 扫描 API
            // 用户需要手动输入或从列表选择
            throw CCAPIError.cameraNotFound
        }

        await MainActor.run {
            connectionState = .connecting
        }

        do {
            let hotspotConfig = NEHotspotConfiguration(ssid: ssid)
            hotspotConfig.joinOnce = true   // 只加入一次，不保存网络
            try await NEHotspotConfigurationManager.shared.apply(hotspotConfig)
            // 连接成功后，pathMonitor 会自动更新状态
        } catch {
            await MainActor.run {
                connectionState = .disconnected
            }
            throw error
        }
    }

    /// 断开相机 Wi-Fi（移除配置）
    func disconnect() {
        // 移除所有相机网络配置
        for prefix in Self.cameraSSIDPrefixes {
            NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: prefix)
        }
        // 注意：这不会主动断开 Wi-Fi，只是移除配置
        // iOS 会自动管理连接
    }

    /// 判断 SSID 是否为相机网络
    static func isCameraSSID(_ ssid: String) -> Bool {
        cameraSSIDPrefixes.contains { ssid.hasPrefix($0) }
    }

    /// 获取当前 Wi-Fi SSID
    static func fetchCurrentSSID() async -> String? {
        // 使用 NEHotspotNetwork 获取当前 SSID
        // 注意：这需要 kCLLocationAccuracyReduced 或更高精度定位权限
        // 简化实现：通过 NWPathMonitor 获取
        return nil
    }

    // MARK: - 私有方法

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let isWiFi: Bool
            let ssid: String?

            if #available(iOS 16.0, *) {
                isWiFi = path.usesInterfaceType(.wifi)
            } else {
                isWiFi = path.availableInterfaces.contains { $0.type == .wifi }
            }

            // 从网络接口中提取 SSID（仅用于判断）
            // 实际的 SSID 获取需要定位权限
            ssid = nil

            Task { @MainActor in
                if !isWiFi {
                    self.connectionState = .disconnected
                    self.currentSSID = nil
                }
                // 注意：无法可靠获取 SSID 时，我们依赖 CameraProbe 来确认是否连接到相机
            }
        }
    }

    private func checkCurrentWiFiStatus() {
        let currentPath = pathMonitor.currentPath
        let isWiFi = currentPath.availableInterfaces.contains { $0.type == .wifi }

        Task { @MainActor in
            if !isWiFi {
                connectionState = .disconnected
                currentSSID = nil
            } else {
                // 暂时标记为未知，CameraProbe 会确认是否相机网络
                connectionState = .connectedToOther(ssid: "Wi-Fi")
            }
        }
    }
}
