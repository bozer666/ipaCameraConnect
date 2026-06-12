import SwiftUI

/// 设置视图
///
/// 包含相机信息、缓存管理、关于和帮助。
struct SettingsView: View {
    @EnvironmentObject private var cameraVM: CameraViewModel
    @State private var diskCacheSize: String = "计算中..."
    @State private var showClearCacheAlert = false
    @State private var showDisconnectAlert = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            List {
                // 相机信息
                cameraInfoSection

                // 连接管理
                connectionSection

                // 缓存管理
                cacheSection

                // 关于
                aboutSection

                // 帮助
                helpSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("清空缓存", isPresented: $showClearCacheAlert) {
                Button("清空", role: .destructive) {
                    ImageCacheManager.shared.clearAll()
                    diskCacheSize = "0 MB"
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除所有已缓存的缩略图，下次浏览时需要重新下载。")
            }
            .alert("断开连接", isPresented: $showDisconnectAlert) {
                Button("断开", role: .destructive) {
                    cameraVM.disconnect()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("断开相机连接后将返回连接页面。")
            }
            .sheet(isPresented: $showHelp) {
                helpView
            }
            .task {
                await updateCacheSize()
            }
        }
    }

    // MARK: - 相机信息

    private var cameraInfoSection: some View {
        Section("相机信息") {
            if case .connected(let info) = cameraVM.connectionState {
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("固件版本") {
                    Text(info.firmwareVersion)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("IP 地址") {
                    Text(info.ipAddress)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("API 版本") {
                    Text(info.apiVersion)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "camera.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("未连接相机")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 连接管理

    private var connectionSection: some View {
        Section("连接") {
            if case .connected = cameraVM.connectionState {
                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("断开相机连接")
                    }
                }
            }

            Button {
                cameraVM.reconnect()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("重新探测相机")
                }
            }
        }
    }

    // MARK: - 缓存

    private var cacheSection: some View {
        Section("缓存管理") {
            HStack {
                Image(systemName: "photo.badge.arrow.down")
                    .foregroundStyle(.secondary)
                Text("缩略图缓存")
                Spacer()
                Text(diskCacheSize)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("清空缓存")
                }
            }
            .disabled(diskCacheSize == "0 MB" || diskCacheSize == "计算中...")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera Connect")
                        .font(.subheadline)
                    Text("版本 1.0.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("开发语言") {
                Text("Swift + SwiftUI")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            LabeledContent("通信协议") {
                Text("Canon CCAPI")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            LabeledContent("支持相机") {
                Text("佳能 EOS R7")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - 帮助

    private var helpSection: some View {
        Section {
            Button {
                showHelp = true
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.blue)
                    Text("使用帮助")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - 帮助视图

    private var helpView: some View {
        NavigationStack {
            List {
                Section("连接相机") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpStep("1", "在相机菜单中启用「Wi-Fi 遥控」功能")
                        helpStep("2", "在 iPhone 设置中连接到相机的 Wi-Fi 网络（通常以 Canon_ 开头）")
                        helpStep("3", "返回 App 等待自动连接，或点击「手动连接」输入 SSID")
                    }
                }

                Section("浏览照片") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpStep("1", "连接相机后，在首页点击「照片浏览」")
                        helpStep("2", "滑动浏览缩略图，点击查看大图")
                        helpStep("3", "点击「选择」进入多选模式，可批量下载或删除")
                    }
                }

                Section("遥控拍摄") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpStep("1", "在首页点击「遥控拍摄」")
                        helpStep("2", "点击「开启」启动实时取景")
                        helpStep("3", "点击参数栏调整光圈/快门/ISO")
                        helpStep("4", "半按快门对焦，全按拍摄")
                    }
                }

                Section("常见问题") {
                    VStack(alignment: .leading, spacing: 12) {
                        faqItem(
                            "无法连接相机？",
                            "确保相机 Wi-Fi 功能已开启，且手机已连接到相机的 Wi-Fi 网络。部分相机需要先在相机上选择「手机遥控」模式。"
                        )
                        faqItem(
                            "实时取景画面卡顿？",
                            "实时取景帧率受 Wi-Fi 信号质量影响，建议靠近相机使用。"
                        )
                        faqItem(
                            "下载的照片在哪里？",
                            "下载的照片保存在 iPhone 系统相册中。"
                        )
                    }
                }
            }
            .navigationTitle("使用帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { showHelp = false }
                }
            }
        }
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func faqItem(_ question: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 缓存大小

    private func updateCacheSize() async {
        let size = ImageCacheManager.shared.diskCacheSize
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        diskCacheSize = formatter.string(fromByteCount: Int64(size))
    }
}

#Preview {
    SettingsView()
        .environmentObject(CameraViewModel())
}
