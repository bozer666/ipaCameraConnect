import SwiftUI

/// 主视图 — 根据连接状态显示不同内容
struct ContentView: View {
    @EnvironmentObject private var cameraVM: CameraViewModel

    var body: some View {
        Group {
            switch cameraVM.connectionState {
            case .disconnected, .connecting, .probing:
                ConnectView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .connected:
                CameraInfoView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            case .failed(let message):
                ConnectView(errorMessage: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: cameraVM.connectionState)
        .alert("连接错误", isPresented: $cameraVM.showError) {
            Button("重试") {
                cameraVM.reconnect()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraVM.errorMessage ?? "未知错误")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraViewModel())
}
