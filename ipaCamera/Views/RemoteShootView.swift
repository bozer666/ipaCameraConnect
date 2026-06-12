import SwiftUI

/// 遥控拍摄视图（完整版）
///
/// 实时取景 + 参数控制栏 + 功能按钮 + 快门。
struct RemoteShootView: View {
    @StateObject private var viewModel = RemoteShootViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 0) {
                        // 实时取景区域
                        liveViewArea

                        Spacer(minLength: 0)

                        // 参数栏
                        ParameterBar(
                            params: viewModel.shootingParams,
                            onSelectParameter: { param in
                                viewModel.selectParameter(param)
                            },
                            editingParameter: $viewModel.editingParameter
                        )

                        // 功能按钮 + 快门
                        controlArea
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 8)
                    }
                }
            }
            .navigationTitle("遥控拍摄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.toggleLiveView() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isLiveViewEnabled
                                  ? "video.fill" : "video.slash.fill")
                            Text(viewModel.isLiveViewEnabled ? "关闭" : "开启")
                        }
                        .font(.subheadline)
                        .foregroundColor(viewModel.isLiveViewEnabled ? .green : .white)
                    }
                    .disabled(viewModel.isTogglingLiveView)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("错误", isPresented: $viewModel.showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            .sheet(isPresented: $viewModel.showParameterPicker) {
                parameterPickerSheet
            }
            .task {
                await viewModel.loadParameters()
            }
            .onDisappear {
                viewModel.cleanup()
            }
        }
    }

    // MARK: - 实时取景区域

    private var liveViewArea: some View {
        ZStack {
            if let frame = viewModel.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.isLiveViewEnabled
                          ? "antenna.radiowaves.left.and.right" : "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)

                    if viewModel.isLiveViewEnabled {
                        ProgressView().tint(.white)
                        Text("等待画面...").font(.caption).foregroundColor(.gray)
                    } else {
                        Text("点击「开启」启动实时取景")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .frame(minHeight: 300)
        .background(Color.black)
        .clipped()
    }

    // MARK: - 参数选择器

    private var parameterPickerSheet: some View {
        Group {
            if let param = viewModel.editingParameter {
                ParameterPicker(
                    title: CCAPIPropertyName.displayName(for: param),
                    currentValue: viewModel.shootingParams.parameterValue(for: param),
                    availableValues: viewModel.editingAvailableValues
                ) { newValue in
                    Task {
                        await viewModel.setParameterValue(param, value: newValue)
                    }
                }
            }
        }
    }

    // MARK: - 控制区域

    private var controlArea: some View {
        VStack(spacing: 12) {
            // 功能按钮行
            HStack(spacing: 20) {
                functionButton(icon: "bolt", label: "连拍")
                functionButton(icon: "timer", label: "自拍")
                functionButton(icon: "chart.bar", label: "直方图")
                functionButton(icon: "target", label: "AF")
            }
            .padding(.horizontal)

            // 快门按钮
            ShutterButton(
                onHalfPress: { await viewModel.focus() },
                onFullPress: { await viewModel.takePhoto() },
                isEnabled: viewModel.isLiveViewEnabled
            )
            .padding(.bottom, 8)

            Text(viewModel.isLiveViewEnabled ? "半按对焦 · 全按拍摄" : "请先开启实时取景")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: - 功能按钮

    private func functionButton(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(width: 52, height: 44)
        .background(.white.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    RemoteShootView()
}
