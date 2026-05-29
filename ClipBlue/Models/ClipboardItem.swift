//
//  ClipboardItem.swift
//  ClipBlue
//
//  剪贴板条目数据模型
//
//  对应 Milestone：M2 数据层
//  对应数据库表：clipboard_items
//  规范依据：docs/02-技术架构文档.md § 四
//

import Foundation
import GRDB

// MARK: - ItemType

/// 剪贴板条目的内容类型
enum ItemType: String, Codable, DatabaseValueConvertible, Sendable {
    /// 纯文本
    case text
    /// 富文本（保留格式，如颜色、加粗）
    case rtf
    /// 图片
    case image
    /// 文件路径（如从 Finder 复制的文件引用）
    case file
    /// URL 链接
    case url
}

// MARK: - ClipboardItem

/// 剪贴板条目数据模型
///
/// 对应数据库表 `clipboard_items` 的一行。
/// 包含文字、富文本、图片、文件、URL 五种类型。
///
/// **规范来源**：docs/02-技术架构文档.md § 4.1
struct ClipboardItem: Identifiable, Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {

    // MARK: - GRDB Configuration

    /// 对应的数据库表名
    static let databaseTableName = "clipboard_items"

    /// Codable 字段名映射到数据库列名（snake_case）
    /// ⚠️ 必须定义在 struct 主体内（不是 extension 中），
    /// 否则 Swift 6 编译器在自动合成 Codable 时会报 "Circular reference"
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case contentText = "content_text"
        case contentFilePath = "content_file_path"
        case contentSummary = "content_summary"
        case sourceAppName = "source_app_name"
        case sourceAppBundleId = "source_app_bundle_id"
        case sourceAppIconPath = "source_app_icon_path"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case byteSize = "byte_size"
    }

    /// 字段映射（用于 GRDB 查询：`ClipboardItem.Columns.isPinned == true`）
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let contentText = Column(CodingKeys.contentText)
        static let contentFilePath = Column(CodingKeys.contentFilePath)
        static let contentSummary = Column(CodingKeys.contentSummary)
        static let sourceAppName = Column(CodingKeys.sourceAppName)
        static let sourceAppBundleId = Column(CodingKeys.sourceAppBundleId)
        static let sourceAppIconPath = Column(CodingKeys.sourceAppIconPath)
        static let isPinned = Column(CodingKeys.isPinned)
        static let pinnedAt = Column(CodingKeys.pinnedAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let byteSize = Column(CodingKeys.byteSize)
    }

    // MARK: - Properties

    /// 唯一标识符（UUID 字符串，如 "ABC-123..."）
    let id: String

    /// 内容类型
    let type: ItemType

    /// 文字内容（type=text/url 时为内容本身；type=file 时为路径；type=image/rtf 时可为 nil）
    var contentText: String?

    /// 关联文件名（type=image/rtf 时使用，不含路径，如 "uuid.png"）
    var contentFilePath: String?

    /// 用于搜索的纯文本摘要（图片/文件类型也会有"图片"/"文件名"等可搜索文本）
    var contentSummary: String?

    /// 来源 App 名称（如"微信""Safari"）
    var sourceAppName: String?

    /// 来源 App Bundle ID（如 "com.tencent.xinWeChat"）
    var sourceAppBundleId: String?

    /// 缓存的来源 App 图标路径（相对路径，如 "app-icons/com.tencent.xinWeChat.png"）
    var sourceAppIconPath: String?

    /// 是否置顶
    var isPinned: Bool

    /// 置顶时间（非置顶为 nil）
    var pinnedAt: Date?

    /// 首次复制时间
    let createdAt: Date

    /// 最近一次复制时间（去重时更新；用于排序）
    var updatedAt: Date

    /// 内容占用字节数（用于统计存储空间）
    let byteSize: Int

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        type: ItemType,
        contentText: String? = nil,
        contentFilePath: String? = nil,
        contentSummary: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppIconPath: String? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        byteSize: Int
    ) {
        self.id = id
        self.type = type
        self.contentText = contentText
        self.contentFilePath = contentFilePath
        self.contentSummary = contentSummary
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppIconPath = sourceAppIconPath
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.byteSize = byteSize
    }
}

// MARK: - Convenience Factories

extension ClipboardItem {

    /// 快速创建一个文字类型的条目
    static func text(
        _ text: String,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil
    ) -> ClipboardItem {
        // 单条文字最大 10 万字符，超出截断（详见需求文档 § 4.1.3）
        let truncated = String(text.prefix(100_000))
        return ClipboardItem(
            type: .text,
            contentText: truncated,
            contentSummary: truncated,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            byteSize: truncated.utf8.count
        )
    }

    /// 快速创建一个富文本类型的条目
    /// - Parameters:
    ///   - fileName: 富文本存储的文件名（uuid.rtf）
    ///   - plainText: 用于预览和搜索的纯文本
    ///   - byteSize: RTF 数据的字节大小
    static func rtf(
        fileName: String,
        plainText: String,
        byteSize: Int,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil
    ) -> ClipboardItem {
        let truncatedPlain = String(plainText.prefix(100_000))
        return ClipboardItem(
            type: .rtf,
            contentText: truncatedPlain,
            contentFilePath: fileName,
            contentSummary: truncatedPlain,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            byteSize: byteSize
        )
    }

    /// 快速创建一个图片类型的条目
    /// - Parameters:
    ///   - fileName: 图片存储的文件名（uuid.png）
    ///   - byteSize: 图片字节大小
    static func image(
        fileName: String,
        byteSize: Int,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            contentFilePath: fileName,
            contentSummary: "图片",
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            byteSize: byteSize
        )
    }

    /// 快速创建一个文件类型的条目
    static func file(
        url: URL,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil
    ) -> ClipboardItem {
        let path = url.path
        let fileName = url.lastPathComponent
        return ClipboardItem(
            type: .file,
            contentText: path,
            contentSummary: fileName,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            byteSize: path.utf8.count
        )
    }

    /// 快速创建一个 URL 类型的条目
    static func url(
        _ url: URL,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil
    ) -> ClipboardItem {
        let urlString = url.absoluteString
        return ClipboardItem(
            type: .url,
            contentText: urlString,
            contentSummary: urlString,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            byteSize: urlString.utf8.count
        )
    }
}
