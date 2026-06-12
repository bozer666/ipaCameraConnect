import SwiftUI

/// 参数栏组件
///
/// 显示当前拍摄参数（拍摄模式、快门速度、光圈、ISO），
/// 点击任一参数弹出参数选择器滚轮。
struct ParameterBar: View {
    let params: ShootingParams
    let onSelectParameter: (String) -> Void

    /// 当前正在编辑的参数
    @Binding var editingParameter: String?
    @State private var showPicker = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // 拍摄模式
                parameterChip(
                    value: params.shootingMode,
                    label: params.shootingMode,
                    isActive: editingParameter == "shootingmode",
                    width: 44
                )
                .onTapGesture { startEditing("shootingmode") }

                divider

                // 快门速度
                parameterChip(
                    value: params.shutterSpeed,
                    label: params.shutterSpeed,
                    isActive: editingParameter == "shutterspeed",
                    width: 72
                )
                .onTapGesture { startEditing("shutterspeed") }

                divider

                // 光圈
                parameterChip(
                    value: params.aperture,
                    label: params.aperture,
                    isActive: editingParameter == "aperture",
                    width: 60
                )
                .onTapGesture { startEditing("aperture") }

                divider

                // ISO
                parameterChip(
                    value: params.iso,
                    label: "ISO",
                    isActive: editingParameter == "iso",
                    width: 68
                )
                .onTapGesture { startEditing("iso") }

                divider

                // 曝光补偿
                parameterChip(
                    value: params.exposureCompensation,
                    label: params.exposureCompensation,
                    isActive: editingParameter == "exposurecompensation",
                    width: 52
                )
                .onTapGesture { startEditing("exposurecompensation") }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    // MARK: - 组件

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 24)
    }

    private func parameterChip(value: String, label: String, isActive: Bool, width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(isActive ? .yellow : .white)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(width: width, height: 40)
        .background(isActive ? Color.white.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }

    // MARK: - 操作

    private func startEditing(_ param: String) {
        editingParameter = param
        onSelectParameter(param)
    }
}

#Preview {
    ZStack {
        Color.black
        ParameterBar(
            params: ShootingParams(
                shootingMode: "M",
                aperture: "f/4.0",
                shutterSpeed: "1/125",
                iso: "400",
                exposureCompensation: "+0.3",
                whiteBalance: "AWB",
                focusMode: "AF"
            ),
            onSelectParameter: { print("编辑: \($0)") },
            editingParameter: .constant(nil)
        )
    }
}
