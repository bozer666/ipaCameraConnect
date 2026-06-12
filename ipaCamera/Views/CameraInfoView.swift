import SwiftUI

/// 相机信息详情视图
///
/// 显示连接后的相机状态、属性和基本操作入口。
struct CameraInfoView: View {
    @EnvironmentObject private var cameraVM: CameraViewModel

    var body: some View {
        NavigationStack {
            List {
                // 连接状态横幅
                connectionStatusSection

                // 相机基本信息
                if case .connected(let info) = cameraVM.connectionState {
                    cameraInfoSection(info)

                    // 相机状态
                    if let status = cameraVM.cameraStatus {
                        statusSection(status)
                    }

                    // 快速操作
                    quickActionsSection
                }
            }
            .navigationTitle("相机已连接")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("断开", role: .destructive) {
                        cameraVM.disconnect()
                    }
                }
            }
            .onAppear {
                Task {
                    await cameraVM.loadCameraStatus()
                }
            }
        }
    }

    // MARK: - 连接状态横幅

    private var connectionStatusSection: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("相机已连接")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if case .connected(let info) = cameraVM.connectionState {
                    Text(info.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if cameraVM.isLoadingStatus {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 相机信息

    private func cameraInfoSection(_ info: CameraInfo) -> some View {
        Section("基本信息") {
            LabeledContent("型号") {
                Text(info.deviceName)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("制造商") {
                Text(info.manufacturer)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("序列号") {
                Text(info.serialNumber)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            LabeledContent("固件版本") {
                Text(info.firmwareVersion)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("API 版本") {
                Text(info.apiVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 相机状态

    private func statusSection(_ status: CameraStatus) -> some View {
        Section("相机状态") {
            // 电量
            HStack {
                Image(systemName: batteryIcon(level: status.batteryLevel))
                    .foregroundStyle(batteryColor(level: status.batteryLevel))
                Text("电量")
                Spacer()
                if let level = status.batteryLevel {
                    Text("\(level)%")
                        .foregroundStyle(.secondary)
                } else if let text = status.batteryStatus {
                    Text(text)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                }
            }

            // 剩余拍摄张数
            if let shots = status.remainingShots {
                LabeledContent("剩余拍摄") {
                    Text("\(shots) 张")
                        .foregroundStyle(.secondary)
                }
            }

            // 存储状态
            if let available = status.storageAvailable {
                LabeledContent("存储卡") {
                    HStack {
                        Image(systemName: available ? "sd.card" : "exclamationmark.triangle.fill")
                            .foregroundStyle(available ? .green : .orange)
                        Text(available ? "正常" : "不可用")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 快速操作

    private var quickActionsSection: some View {
        Section("功能入口") {
            NavigationLink {
                GalleryView()
            } label: {
                Label("照片浏览", systemImage: "photo.on.rectangle")
            }

            NavigationLink {
                RemoteShootView()
            } label: {
                Label("遥控拍摄", systemImage: "camera.viewfinder")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
        }
    }

    // MARK: - 辅助方法

    private func batteryIcon(level: Int?) -> String {
        guard let level = level else { return "battery.unknown" }
        switch level {
        case 75...100: return "battery.100"
        case 50..<75:  return "battery.75"
        case 25..<50:  return "battery.50"
        case 10..<25:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private func batteryColor(level: Int?) -> Color {
        guard let level = level else { return .gray }
        switch level {
        case 20...100: return .green
        case 10..<20:  return .orange
        default:       return .red
        }
    }
}

#Preview {
    CameraInfoView()
        .environmentObject(CameraViewModel())
}
