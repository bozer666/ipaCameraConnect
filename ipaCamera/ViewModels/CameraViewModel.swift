import Foundation
import Network
import Combine
import OSLog

/// 相机连接视图模型
///
/// 管理 Wi-Fi 连接 → 相机探测 → 连接状态的全流程。
/// 作为全局单例在 App 中共享。
@MainActor
final class CameraViewModel: ObservableObject {
    // MARK: - Published 属性

    /// 连接状态
    @Published private(set) var connectionState: CameraConnectionState = .disconnected
    /// Wi-Fi 状态
    @Published private(set) var wifiState: WiFiConnectionState = .unknown
    /// 错误信息（用于 Alert 显示）
    @Published var errorMessage: String?
    /// 是否正在加载
    @Published var isLoading = false
    /// 是否显示错误 Alert
    @Published var showError = false
    /// 相机实时状态
    @Published private(set) var cameraStatus: CameraStatus?
    /// 是否正在加载状态
    @Published var isLoadingStatus = false

    // MARK: - 服务

    let wifiManager: WiFiConnectionManager
    private let cameraService: CameraService
    private var probeTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.ipaCamera", category: "CameraViewModel")

    // MARK: - 初始化

    init(
        wifiManager: WiFiConnectionManager = WiFiConnectionManager(),
        cameraService: CameraService = CameraService()
    ) {
        self.wifiManager = wifiManager
        self.cameraService = cameraService
        setupBindings()
    }

    // MARK: - 公共方法

    /// 开始监听 Wi-Fi 并自动探测相机
    func start() {
        wifiManager.startMonitoring()
        // 启动后立即尝试探测（可能已连接相机 Wi-Fi）
        attemptAutoConnect()
    }

    /// 尝试自动连接并探测相机
    func attemptAutoConnect() {
        probeTask?.cancel()
        probeTask = Task {
            // 等待短暂时间让 Wi-Fi 状态稳定
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1秒

            guard !Task.isCancelled else { return }

            await MainActor.run {
                connectionState = .probing
                isLoading = true
            }

            do {
                let cameraInfo = try await cameraService.probeCamera()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    connectionState = .connected(cameraInfo)
                    isLoading = false
                    errorMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    connectionState = .disconnected
                    isLoading = false
                    // 探测失败不报错，等待用户手动操作
                }
            }
        }
    }

    /// 手动连接到相机 Wi-Fi
    /// - Parameter ssid: 相机 Wi-Fi SSID
    func connectToCamera(ssid: String) async {
        guard case .disconnected = connectionState else { return }

        await MainActor.run {
            connectionState = .connecting
            isLoading = true
            errorMessage = nil
        }

        do {
            try await wifiManager.connectToCamera(ssid: ssid)
            // 连接 Wi-Fi 后等待相机就绪
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 等待2秒
            // 探测相机
            let cameraInfo = try await cameraService.probeCamera()
            await MainActor.run {
                connectionState = .connected(cameraInfo)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                connectionState = .disconnected
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// 断开连接
    func disconnect() {
        probeTask?.cancel()
        probeTask = nil
        wifiManager.disconnect()
        connectionState = .disconnected
        isLoading = false
    }

    /// 重新连接
    func reconnect() {
        disconnect()
        attemptAutoConnect()
    }

    /// 加载相机实时状态（电量、存储等）
    func loadCameraStatus() async {
        guard case .connected = connectionState else { return }
        isLoadingStatus = true
        do {
            let status = try await cameraService.getCameraStatus()
            cameraStatus = status
        } catch {
            // 状态加载失败不阻塞用户操作，静默处理
            logger.warning("加载相机状态失败: \(error.localizedDescription)")
        }
        isLoadingStatus = false
    }

    // MARK: - 私有方法

    private func setupBindings() {
        // 监听 Wi-Fi 状态变化，自动触发相机探测
        Task {
            for await state in wifiManager.$connectionState.values {
                wifiState = state
                if state.isConnectedToCamera {
                    attemptAutoConnect()
                }
            }
        }
    }
}
