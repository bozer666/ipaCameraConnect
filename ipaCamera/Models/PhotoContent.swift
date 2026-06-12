import Foundation

/// 照片内容元数据
struct PhotoContent: Identifiable, Codable, Equatable {
    /// 内容 ID（完整路径，如 "100CANON/IMG_0001.JPG"）
    let id: String
    /// 文件名
    let name: String
    /// 文件大小（字节）
    let size: Int
    /// 拍摄日期
    let date: Date?
    /// 图片宽度
    let width: Int
    /// 图片高度
    let height: Int
    /// 是否为 RAW 格式
    let isRaw: Bool
    /// 目录路径
    let directory: String
    /// 缩略图 URL 路径
    var thumbnailPath: String {
        "contents/sd/\(id)/image?size=small"
    }
    /// 原图 URL 路径
    var originalPath: String {
        "contents/sd/\(id)/image"
    }
    /// 详情 URL 路径
    var detailPath: String {
        "contents/sd/\(id)"
    }

    // MARK: - 便利属性

    /// 格式化文件大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// 图片尺寸描述
    var dimensionsDescription: String {
        "\(width) × \(height)"
    }

    /// 文件扩展名
    var fileExtension: String {
        (name as NSString).pathExtension.uppercased()
    }

    /// 是否为图片文件（非 RAW 的图片格式）
    var isImage: Bool {
        !isRaw && ["JPG", "JPEG", "HEIF", "HEIC"].contains(fileExtension)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case name, size, width, height, directory
        case date = "dateTime"
        case isRaw = "isRaw"
    }

    // MARK: - 自定义解码

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.size = try container.decode(Int.self, forKey: .size)
        self.width = try container.decode(Int.self, forKey: .width)
        self.height = try container.decode(Int.self, forKey: .height)
        self.directory = try container.decode(String.self, forKey: .directory)
        self.isRaw = try container.decodeIfPresent(Bool.self, forKey: .isRaw) ?? false

        // 解析日期
        let dateStr = try container.decodeIfPresent(String.self, forKey: .date)
        if let dateStr = dateStr {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.date = formatter.date(from: dateStr)
            ?? ISO8601DateFormatter().date(from: dateStr)
        } else {
            self.date = nil
        }

        // id 从 directory + name 组合
        self.id = directory.hasPrefix("/") ? "\(directory)/\(name)" : "/\(directory)/\(name)"
    }

    // MARK: - 编码

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(directory, forKey: .directory)
        try container.encode(isRaw, forKey: .isRaw)
    }

    // MARK: - 手动初始化（用于预览/Mock）

    init(id: String, name: String, size: Int, date: Date?, width: Int, height: Int, isRaw: Bool, directory: String) {
        self.id = id
        self.name = name
        self.size = size
        self.date = date
        self.width = width
        self.height = height
        self.isRaw = isRaw
        self.directory = directory
    }
}

/// 内容列表响应（CCAPI 格式）
struct ContentListResponse: Decodable {
    let urls: [String]

    /// 解析出内容 ID 列表
    var contentIds: [String] {
        urls.compactMap { urlString -> String? in
            // 从 URL 中提取 contents/sd/ 后面的路径
            guard let range = urlString.range(of: "/contents/sd/") else { return nil }
            return String(urlString[range.upperBound...])
        }
    }
}

/// 内容列表（带分页信息）
struct PaginatedContent {
    let contents: [PhotoContent]
    let hasMore: Bool
    let totalCount: Int?
}
