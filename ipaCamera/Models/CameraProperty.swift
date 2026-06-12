import Foundation

/// 相机属性值类型
enum PropertyValueType: Equatable {
    case string(String)
    case int(Int)
    case double(Double)

    var stringValue: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return "\(v)"
        case .double(let v): return String(format: "%.1f", v)
        }
    }
}

/// 相机属性
///
/// 包含当前值和可选值列表。
struct CameraProperty: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let currentValue: PropertyValueType
    let availableValues: [PropertyValueType]

    /// 是否有可选值
    var hasOptions: Bool { !availableValues.isEmpty }

    /// 当前值显示文本
    var displayValue: String {
        currentValue.stringValue
    }
}

/// 拍摄参数集合
///
/// 包含当前所有可调参数的快照。
struct ShootingParams: Equatable {
    var shootingMode: String = "M"
    var aperture: String = "f/0.0"
    var shutterSpeed: String = "1/0"
    var iso: String = "AUTO"
    var exposureCompensation: String = "±0"
    var whiteBalance: String = "AWB"
    var focusMode: String = "AF"

    /// 参数栏显示文本
    var parameterBarText: String {
        "\(shootingMode)  \(shutterSpeed)  \(aperture)  ISO \(iso)"
    }

    /// 根据 CCAPI 属性名获取当前值
    func parameterValue(for name: String) -> String {
        switch name {
        case CCAPIPropertyName.shootingMode: return shootingMode
        case CCAPIPropertyName.aperture: return aperture
        case CCAPIPropertyName.shutterSpeed: return shutterSpeed
        case CCAPIPropertyName.iso: return iso
        case CCAPIPropertyName.exposureCompensation: return exposureCompensation
        case CCAPIPropertyName.whiteBalance: return whiteBalance
        case CCAPIPropertyName.focusMode: return focusMode
        default: return "--"
        }
    }
}

// MARK: - 拍摄模式

/// 拍摄模式
enum ShootingMode: String, CaseIterable, Identifiable {
    case manual = "M"
    case aperturePriority = "Av"
    case shutterPriority = "Tv"
    case program = "P"
    case bulb = "B"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

/// 白平衡
enum WhiteBalance: String, CaseIterable, Identifiable {
    case auto = "auto"
    case daylight = "daylight"
    case shade = "shade"
    case cloudy = "cloudy"
    case tungsten = "tungsten"
    case fluorescent = "fluorescent"
    case custom = "custom"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "AWB"
        case .daylight: return "日光"
        case .shade: return "阴影"
        case .cloudy: return "阴天"
        case .tungsten: return "钨丝灯"
        case .fluorescent: return "荧光灯"
        case .custom: return "自定义"
        }
    }
}

/// 对焦模式
enum FocusMode: String, CaseIterable, Identifiable {
    case oneShot = "oneshot"
    case aiServo = "aiservo"
    case manual = "manual"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .oneShot: return "One-Shot"
        case .aiServo: return "AI Servo"
        case .manual: return "MF"
        }
    }
}

// MARK: - CCAPI 属性名映射

/// CCAPI 属性名常量
struct CCAPIPropertyName {
    static let shootingMode = "shootingmode"
    static let aperture = "aperture"
    static let shutterSpeed = "shutterspeed"
    static let iso = "iso"
    static let exposureCompensation = "exposurecompensation"
    static let whiteBalance = "whitebalance"
    static let focusMode = "focusmode"
    static let continuousShooting = "continuousshooting"
    static let selfTimer = "selftimer"

    /// 属性名 → 显示名映射
    static func displayName(for propertyName: String) -> String {
        switch propertyName.lowercased() {
        case "shootingmode": return "拍摄模式"
        case "aperture": return "光圈"
        case "shutterspeed": return "快门速度"
        case "iso": return "ISO"
        case "exposurecompensation": return "曝光补偿"
        case "whitebalance": return "白平衡"
        case "focusmode": return "对焦模式"
        case "continuousshooting": return "连拍"
        case "selftimer": return "自拍"
        default: return propertyName
        }
    }
}
