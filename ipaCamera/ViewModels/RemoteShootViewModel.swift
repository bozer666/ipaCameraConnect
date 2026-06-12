import Foundation
import UIKit
import OSLog

/// 遥控拍摄视图模型（完整版）
///
/// 管理实时取景 + 完整参数控制 + 拍摄模式。
@MainActor
final class RemoteShootViewModel: ObservableObject {
    // MARK: - Published — 实时取景

    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var liveViewState: LiveViewService.LiveViewState = .idle
    @Published var isTogglingLiveView = false

    var isLiveViewEnabled: Bool {
        if case .running = liveViewState { return true }
        return false
    }

    // MARK: - Published — 参数控制

    @Published var shootingParams = ShootingParams()
    @Published var cameraProperties: [CameraProperty] = []
    @Published var isLoadingParams = false
    /// 当前正在编辑的参数名
    @Published var editingParameter: String?
    /// 当前编辑参数的可用值列表
    @Published var editingAvailableValues: [String] = []
    /// 是否显示参数选择器
    @Published var showParameterPicker = false

    // MARK: - Published — 通用

    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - 服务

    private let liveViewService: LiveViewService
    private let shootingService: ShootingService
    private let logger: Logger
    private var frameTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var paramLoadTask: Task<Void, Never>?

    // MARK: - 初始化

    init(
        liveViewService: LiveViewService = LiveViewService(),
        shootingService: ShootingService = ShootingService()
    ) {
        self.liveViewService = liveViewService
        self.shootingService = shootingService
        self.logger = Logger(subsystem: "com.ipaCamera", category: "RemoteShootVM")
        observeState()
        observeFrames()
    }

    // MARK: - 实时取景

    func toggleLiveView() async {
        isTogglingLiveView = true
        if isLiveViewEnabled {
            await stopLiveView()
        } else {
            await startLiveView()
        }
        isTogglingLiveView = false
    }

    func startLiveView() async {
        do {
            try await liveViewService.start()
            logger.info("📡 实时取景已开启")
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    func stopLiveView() async {
        await liveViewService.stop()
        currentFrame = nil
        logger.info("📡 实时取景已关闭")
    }

    // MARK: - 参数管理

    /// 加载所有相机参数
    func loadParameters() async {
        isLoadingParams = true
        paramLoadTask?.cancel()

        paramLoadTask = Task {
            do {
                let props = try await shootingService.readAllParameters()
                guard !Task.isCancelled else { return }

                cameraProperties = props
                updateShootingParams(from: props)
                logger.info("⚙️ 已加载 \(props.count) 个参数")
            } catch {
                guard !Task.isCancelled else { return }
                logger.warning("⚠️ 加载参数失败: \(error.localizedDescription)")
            }
            isLoadingParams = false
        }
    }

    /// 打开参数选择器
    func selectParameter(_ name: String) {
        editingParameter = name
        if let prop = cameraProperties.first(where: { $0.name == name }) {
            editingAvailableValues = prop.availableValues.map { $0.stringValue }
        } else {
            editingAvailableValues = []
        }
        showParameterPicker = true
    }

    /// 设置参数值
    func setParameterValue(_ name: String, value: String) async {
        do {
            try await shootingService.writeParameter(name, value: value)
            // 更新本地缓存
            if let index = cameraProperties.firstIndex(where: { $0.name == name }) {
                let prop = cameraProperties[index]
                cameraProperties[index] = CameraProperty(
                    id: prop.id,
                    name: prop.name,
                    displayName: prop.displayName,
                    currentValue: .string(value),
                    availableValues: prop.availableValues
                )
            }
            updateShootingParams(from: cameraProperties)
            logger.info("✅ 参数已设置: \(name) = \(value)")
        } catch {
            showErrorMessage("设置 \(name) 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 快门控制

    func takePhoto() async {
        do {
            try await shootingService.pressShutter()
            logger.info("📸 拍照完成")
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    func focus() async {
        do {
            try await shootingService.pressShutterHalf()
        } catch {
            logger.warning("⚠️ 对焦失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 辅组

    func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    func cleanup() {
        frameTask?.cancel()
        stateTask?.cancel()
        paramLoadTask?.cancel()
        Task { await liveViewService.stop() }
    }

    // MARK: - 私有

    private func observeState() {
        stateTask = Task { [weak self] in
            guard let self = self else { return }
            for await state in self.liveViewService.stateStream {
                await MainActor.run {
                    self.liveViewState = state
                }
            }
        }
    }

    private func observeFrames() {
        frameTask = Task { [weak self] in
            guard let self = self else { return }
            for await frame in self.liveViewService.frameStream {
                await MainActor.run {
                    self.currentFrame = frame
                }
            }
        }
    }

    private func updateShootingParams(from props: [CameraProperty]) {
        var params = ShootingParams()
        for prop in props {
            let value = prop.currentValue.stringValue
            switch prop.name {
            case CCAPIPropertyName.shootingMode: params.shootingMode = value
            case CCAPIPropertyName.aperture: params.aperture = value
            case CCAPIPropertyName.shutterSpeed: params.shutterSpeed = value
            case CCAPIPropertyName.iso: params.iso = value
            case CCAPIPropertyName.exposureCompensation: params.exposureCompensation = value
            case CCAPIPropertyName.whiteBalance: params.whiteBalance = value
            case CCAPIPropertyName.focusMode: params.focusMode = value
            default: break
            }
        }
        shootingParams = params
    }
}
