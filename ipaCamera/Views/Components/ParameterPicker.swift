import SwiftUI

/// 参数选择器组件
///
/// 显示半屏滚轮选择器，用于选择拍摄参数值。
/// 类似系统相机的参数选择体验。
struct ParameterPicker: View {
    let title: String
    let currentValue: String
    let availableValues: [String]
    let onSelect: (String) -> Void

    @State private var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(title: String, currentValue: String, availableValues: [String], onSelect: @escaping (String) -> Void) {
        self.title = title
        self.currentValue = currentValue
        self.availableValues = availableValues
        self.onSelect = onSelect
        self._selectedIndex = State(initialValue: Self.findIndex(value: currentValue, in: availableValues))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题
                Text(title)
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()

                // 滚轮选择器
                Picker(title, selection: $selectedIndex) {
                    ForEach(Array(availableValues.enumerated()), id: \.offset) { index, value in
                        Text(displayValue(value))
                            .tag(index)
                            .font(.system(.title2, design: .monospaced))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 200)

                Divider()

                // 底部按钮
                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    Spacer()

                    Button("确定") {
                        if selectedIndex < availableValues.count {
                            onSelect(availableValues[selectedIndex])
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .presentationDetents([.medium])
        }
    }

    /// 显示友好格式的参数值
    private func displayValue(_ value: String) -> String {
        switch title {
        case "光圈":
            return value.hasPrefix("f/") ? value : "f/\(value)"
        case "ISO":
            return "ISO \(value)"
        case "曝光补偿":
            let prefix = value.hasPrefix("-") ? "" : "+"
            return "\(prefix)\(value) EV"
        default:
            return value
        }
    }

    /// 查找当前值在可选列表中的索引
    private static func findIndex(value: String, in values: [String]) -> Int {
        values.firstIndex { $0 == value } ?? values.count / 2
    }
}

#Preview {
    ParameterPicker(
        title: "光圈",
        currentValue: "f/4.0",
        availableValues: ["f/2.8", "f/3.2", "f/4.0", "f/4.5", "f/5.6", "f/6.3", "f/7.1", "f/8.0"],
        onSelect: { value in print("选中: \(value)") }
    )
}
