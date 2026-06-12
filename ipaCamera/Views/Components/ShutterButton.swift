import SwiftUI

/// 快门按钮组件
///
/// 大圆快门按钮，支持半按（对焦）和全按（拍照）。
struct ShutterButton: View {
    let onHalfPress: () async -> Void
    let onFullPress: () async -> Void
    let isEnabled: Bool

    @State private var isPressed = false
    @State private var isPerformingAction = false

    var body: some View {
        ZStack {
            // 外圈
            Circle()
                .stroke(lineWidth: 4)
                .fill(isEnabled ? Color.white : Color.gray.opacity(0.4))
                .frame(width: 72, height: 72)

            // 内圈
            Circle()
                .fill(shutterColor)
                .frame(width: 60, height: 60)
                .overlay {
                    if isPerformingAction {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.spring(response: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled && !isPressed else { return }
                    isPressed = true
                    isPerformingAction = true
                    Task {
                        await onHalfPress()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    Task {
                        await onFullPress()
                        isPerformingAction = false
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    guard isEnabled else { return }
                    isPerformingAction = true
                    Task {
                        await onFullPress()
                        isPerformingAction = false
                    }
                }
        )
    }

    private var shutterColor: Color {
        if !isEnabled { return Color.gray.opacity(0.6) }
        if isPressed { return Color.red.opacity(0.7) }
        return Color.red
    }
}

#Preview {
    ZStack {
        Color.black
        ShutterButton(
            onHalfPress: { print("对焦") },
            onFullPress: { print("拍照") },
            isEnabled: true
        )
    }
}
