import SwiftUI

/// Wi-Fi 连接引导视图
///
/// 显示连接状态和操作引导，支持自动探测和手动连接两种模式。
struct ConnectView: View {
    @EnvironmentObject private var cameraVM: CameraViewModel
    @State private var showManualConnect = false
    @State private var manualSSID = ""

    let errorMessage: String?

    init(errorMessage: String? = nil) {
        self.errorMessage = errorMessage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 图标
                Image(systemName: "camera.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .repeating, value: isConnecting)

                // 标题
                Text("Camera Connect")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // 状态信息
                statusSection

                // 错误信息
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // 操作按钮
                actionButtons

                // 连接提示
                connectionGuide
                    .padding(.bottom, 32)
            }
            .padding()
            .navigationTitle("连接相机")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showManualConnect) {
                manualConnectSheet
            }
        }
    }

    // MARK: - 状态指示

    private var isConnecting: Bool {
        if case .connecting = cameraVM.connectionState { return true }
        if case .probing = cameraVM.connectionState { return true }
        return false
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Wi-Fi 状态
            HStack {
                Image(systemName: wifiIcon)
                    .foregroundStyle(wifiIconColor)
                Text(wifiStatusText)
                    .font(.subheadline)
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.3))
            )

            // 相机状态
            if isConnecting {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.blue)
                    Text("正在探测相机...")
                        .font(.subheadline)
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.3))
                )
            }
        }
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if isConnecting {
                Button("取消", role: .cancel) {
                    cameraVM.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                Button("自动连接") {
                    cameraVM.attemptAutoConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("手动连接") {
                    showManualConnect = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - 连接引导

    private var connectionGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("连接步骤：")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                Text("1.").font(.caption).foregroundStyle(.secondary)
                Text("打开相机，在相机菜单中启用「Wi-Fi 遥控」功能").font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("2.").font(.caption).foregroundStyle(.secondary)
                Text("在 iOS 设置中连接到相机的 Wi-Fi 网络").font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text("3.").font(.caption).foregroundStyle(.secondary)
                Text("返回 App，点击「自动连接」").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.2))
        )
    }

    // MARK: - 手动连接弹窗

    private var manualConnectSheet: some View {
        NavigationStack {
            Form {
                Section("相机 Wi-Fi") {
                    TextField("Wi-Fi 名称 (SSID)", text: $manualSSID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button("连接") {
                        showManualConnect = false
                        Task {
                            await cameraVM.connectToCamera(ssid: manualSSID)
                        }
                    }
                    .disabled(manualSSID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("手动连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showManualConnect = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 辅助计算属性

    private var wifiIcon: String {
        switch cameraVM.wifiState {
        case .connectedToCamera:
            return "wifi"
        case .connectedToOther:
            return "wifi.slash"
        case .disconnected, .unknown:
            return "wifi.slash"
        case .connecting:
            return "wifi"
        }
    }

    private var wifiIconColor: Color {
        switch cameraVM.wifiState {
        case .connectedToCamera:
            return .green
        case .connectedToOther:
            return .orange
        case .disconnected, .unknown:
            return .gray
        case .connecting:
            return .blue
        }
    }

    private var wifiStatusText: String {
        switch cameraVM.wifiState {
        case .unknown:
            return "Wi-Fi 状态检测中..."
        case .connectedToCamera(let ssid):
            return "已连接相机: \(ssid)"
        case .connectedToOther(let ssid):
            return "已连接 \(ssid)（非相机网络）"
        case .disconnected:
            return "未连接 Wi-Fi"
        case .connecting:
            return "正在连接..."
        }
    }
}

#Preview {
    ConnectView()
        .environmentObject(CameraViewModel())
}
