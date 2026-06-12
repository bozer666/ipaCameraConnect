import Foundation
import UIKit
import OSLog

/// 实时取景服务
///
/// 管理佳能 CCAPI 实时取景 (Live View) 的生命周期：
/// 1. 开始实时取景 → POST /liveview/start → GET /liveview/liveimage → MJPEG 解码
/// 2. 停止实时取景 → POST /liveview/stop
/// 3. 自动重连（断流后自动恢复）
/// 4. 帧回调发布
final class LiveViewService {
    // MARK: - 常量

    /// 最大重连次数
    private static let maxReconnectAttempts = 3
    /// 重连间隔（秒）
    private static let reconnectDelay: TimeInterval = 1.0

    // MARK: - 枚举

    /// 实时取景状态
    enum LiveViewState: Equatable {
        /// 未启动
        case idle
        /// 正在启动
        case starting
        /// 运行中
        case running
        /// 正在停止
        case stopping
        /// 出现错误
        case failed(String)
    }

    // MARK: - 属性

    private let client: CCAPIClient
    private let decoder: MJPEGStreamDecoder
    private let logger: Logger

    private var streamTask: Task<Void, Never>?
    private var reconnectCount = 0
    private var stateContinuation: AsyncStream<LiveViewState>.Continuation?
    private var frameContinuation: AsyncStream<UIImage>.Continuation?

    /// 状态流
    private(set) lazy var stateStream: AsyncStream<LiveViewState> = {
        AsyncStream { continuation in
            self.stateContinuation = continuation
            continuation.yield(.idle)
        }
    }()

    /// 帧流
    private(set) lazy var frameStream: AsyncStream<UIImage> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

    /// 当前状态
    private(set) var currentState: LiveViewState = .idle {
        didSet {
            stateContinuation?.yield(currentState)
        }
    }

    // MARK: - 初始化

    init(client: CCAPIClient = CCAPIClient()) {
        self.client = client
        self.decoder = MJPEGStreamDecoder()
        self.logger = Logger(subsystem: "com.ipaCamera", category: "LiveViewService")
    }

    // MARK: - 公共方法

    /// 开始实时取景
    func start() async throws {
        guard currentState == .idle || currentState == .failed("") else {
            logger.warning("⚠️ 实时取景已在运行中")
            return
        }

        currentState = .starting
        reconnectCount = 0

        do {
            // 1. 发送开始命令
            logger.info("📡 开始实时取景")
            _ = try await client.post("device/liveview/start")

            // 2. 获取 MJPEG 流
            let bytes = try await client.getStream("device/liveview/liveimage")

            currentState = .running

            // 3. 开始解码
            streamTask = Task { [weak self] in
                guard let self = self else { return }

                let frameStream = self.decoder.decode(bytes)
                for await frame in frameStream {
                    guard !Task.isCancelled else { break }
                    self.frameContinuation?.yield(frame)
                }

                // 流结束（非主动停止）
                if !Task.isCancelled && self.currentState == .running {
                    self.logger.warning("⚠️ 实时取景流断开")
                    await self.handleStreamDisconnect()
                }
            }

        } catch {
            currentState = .failed(error.localizedDescription)
            logger.error("❌ 启动实时取景失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 停止实时取景
    func stop() async {
        guard currentState == .running || currentState == .starting else { return }

        currentState = .stopping
        logger.info("📡 停止实时取景")

        // 取消解码任务
        streamTask?.cancel()
        streamTask = nil

        // 发送停止命令
        do {
            _ = try await client.post("device/liveview/stop")
            logger.info("✅ 实时取景已停止")
        } catch {
            logger.warning("⚠️ 停止实时取景命令失败: \(error.localizedDescription)")
        }

        currentState = .idle
    }

    /// 是否正在运行
    var isRunning: Bool {
        if case .running = currentState { return true }
        return false
    }

    // MARK: - 私有方法

    /// 处理流断开（自动重连）
    private func handleStreamDisconnect() async {
        guard reconnectCount < Self.maxReconnectAttempts else {
            logger.error("❌ 重连次数耗尽，停止自动重连")
            await MainActor.run {
                currentState = .failed("实时取景连接断开，自动重连失败")
            }
            return
        }

        reconnectCount += 1
        logger.info("🔄 自动重连 #\(self.reconnectCount)")

        // 等待后重试
        try? await Task.sleep(nanoseconds: UInt64(Self.reconnectDelay * 1_000_000_000))

        guard !Task.isCancelled else { return }

        do {
            try await start()
        } catch {
            logger.warning("⚠️ 重连失败: \(error.localizedDescription)")
            await handleStreamDisconnect()
        }
    }
}
