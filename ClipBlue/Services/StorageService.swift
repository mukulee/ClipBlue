//
//  StorageService.swift
//  ClipBlue
//
//  数据存储服务（SQLite via GRDB）
//
//  对应 Milestone：M2 数据层
//  规范依据：
//   - docs/02-技术架构文档.md § 四（数据库设计）
//   - docs/02-技术架构文档.md § 五（并发模型）
//   - 需求文档.md § 八（数据存储设计）
//

import Foundation
import GRDB
import os

// MARK: - StorageError

/// 数据存储错误
enum StorageError: Error, LocalizedError {
    case databaseInitFailed(underlying: Error)
    case directoryCreationFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .databaseInitFailed(let error):
            return "数据库初始化失败：\(error.localizedDescription)"
        case .directoryCreationFailed(let path, let error):
            return "无法创建存储目录 \(path)：\(error.localizedDescription)"
        }
    }
}

// MARK: - StorageService

/// 数据存储服务
///
/// 职责：
/// - 管理 SQLite 数据库连接
/// - 提供剪贴板条目的 CRUD 操作
/// - 处理数据库 schema 迁移
///
/// **线程安全**：GRDB 的 `DatabaseQueue` 内部串行，所有方法均线程安全。
/// **存储位置**：`~/Library/Application Support/ClipBlue/database.sqlite`
final class StorageService: @unchecked Sendable {

    // MARK: - Singleton

    /// 全局唯一实例（生产用）
    ///
    /// StorageService 标记为 Sendable（`@unchecked Sendable`，
    /// 安全性由 GRDB DatabaseQueue 内部串行化保证），
    /// 因此 `nonisolated static let` 即可。
    nonisolated static let shared: StorageService = {
        do {
            return try StorageService()
        } catch {
            // 单例初始化失败属于致命错误（无数据库无法工作）
            Log.storage.fault("StorageService 单例初始化失败：\(error.localizedDescription)")
            fatalError("StorageService 初始化失败：\(error)")
        }
    }()

    // MARK: - Properties

    /// GRDB 数据库队列（线程安全）
    private let dbQueue: DatabaseQueue

    /// 数据库文件路径
    let databaseURL: URL

    /// 资源存储根目录（含 images/、rtfs/、app-icons/）
    let supportDirectoryURL: URL

    /// 图片子目录 URL（`<supportDir>/images/`）
    nonisolated var imagesDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("images", isDirectory: true)
    }

    /// 富文本子目录 URL（`<supportDir>/rtfs/`）
    nonisolated var rtfsDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("rtfs", isDirectory: true)
    }

    // MARK: - Initialization

    /// 初始化数据库服务
    /// - Parameter customDatabaseURL: 自定义数据库路径（单元测试用，默认 nil 走标准位置）
    init(customDatabaseURL: URL? = nil) throws {
        // 1. 确定存储根目录
        let supportDir: URL
        if let custom = customDatabaseURL {
            supportDir = custom.deletingLastPathComponent()
            self.databaseURL = custom
        } else {
            supportDir = try Self.defaultSupportDirectory()
            self.databaseURL = supportDir.appendingPathComponent("database.sqlite")
        }
        self.supportDirectoryURL = supportDir

        // 2. 确保目录存在（含子目录 images/ rtfs/ app-icons/）
        try Self.ensureDirectoryExists(at: supportDir)
        try Self.ensureDirectoryExists(at: supportDir.appendingPathComponent("images", isDirectory: true))
        try Self.ensureDirectoryExists(at: supportDir.appendingPathComponent("rtfs", isDirectory: true))
        try Self.ensureDirectoryExists(at: supportDir.appendingPathComponent("app-icons", isDirectory: true))

        // 3. 初始化 GRDB 队列
        do {
            var config = Configuration()
            // Debug 模式下打印 SQL，便于调试
            #if DEBUG
            config.prepareDatabase { db in
                db.trace { event in
                    Log.storage.debug("SQL: \(event.description, privacy: .public)")
                }
            }
            #endif

            self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        } catch {
            throw StorageError.databaseInitFailed(underlying: error)
        }

        // 4. 执行数据库迁移（创建表/索引）
        try Self.migrator.migrate(dbQueue)

        Log.storage.info("数据库初始化成功：\(self.databaseURL.path, privacy: .public)")
    }

    // MARK: - Migrations

    /// 数据库迁移定义
    ///
    /// ⚠️ 重要：每次 schema 变更**只能追加**新 migration，
    /// 不能修改已发布的 migration（详见 docs/02 § 4.3）
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1：创建 clipboard_items 表 + 索引
        migrator.registerMigration("v1_create_clipboard_items") { db in
            try db.create(table: "clipboard_items") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("content_text", .text)
                t.column("content_file_path", .text)
                t.column("content_summary", .text)
                t.column("source_app_name", .text)
                t.column("source_app_bundle_id", .text)
                t.column("source_app_icon_path", .text)
                t.column("is_pinned", .integer).notNull().defaults(to: 0)
                t.column("pinned_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("byte_size", .integer).notNull()
            }

            // 索引：列表查询主索引（先置顶 + 时间倒序）
            try db.create(
                index: "idx_pinned_updated",
                on: "clipboard_items",
                columns: ["is_pinned", "updated_at"]
            )

            // 索引：搜索用
            try db.create(
                index: "idx_summary",
                on: "clipboard_items",
                columns: ["content_summary"]
            )
        }

        return migrator
    }

    // MARK: - CRUD: Insert

    /// 插入一条剪贴板条目
    /// - Parameter item: 待插入的条目
    nonisolated func insert(_ item: ClipboardItem) async throws {
        try await dbQueue.write { db in
            var item = item
            try item.insert(db)
        }
    }

    // MARK: - CRUD: Fetch

    /// 获取所有剪贴板条目（按置顶+时间倒序）
    /// - Returns: 排序后的条目数组
    nonisolated func fetchAll() async throws -> [ClipboardItem] {
        try await dbQueue.read { db in
            try ClipboardItem
                .order(
                    ClipboardItem.Columns.isPinned.desc,
                    ClipboardItem.Columns.updatedAt.desc
                )
                .fetchAll(db)
        }
    }

    /// 按 ID 获取一条
    /// - Parameter id: 条目 ID
    /// - Returns: 找到的条目（不存在返回 nil）
    nonisolated func fetch(id: String) async throws -> ClipboardItem? {
        try await dbQueue.read { db in
            try ClipboardItem.fetchOne(db, key: id)
        }
    }

    /// 按关键词搜索（不区分大小写 + 空格分词 + 多字段 LIKE）
    ///
    /// 规则（详见需求文档 § 4.5）：
    /// - 不区分大小写
    /// - "微信 链接" 用空格分词 → 同时含 "微信" AND "链接"
    /// - 匹配范围：content_summary（涵盖内容文本）+ source_app_name（来源 App 名）
    ///
    /// - Parameter tokens: 已切好的关键词数组（空数组等同于无过滤）
    /// - Returns: 已按置顶 + 时间倒序排好的结果
    nonisolated func search(tokens: [String]) async throws -> [ClipboardItem] {
        // 无 token 等同于全量
        let cleaned = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            return try await fetchAll()
        }

        return try await dbQueue.read { db in
            // 每个 token 拼一个 (content_summary LIKE ? OR source_app_name LIKE ?)，
            // 多个 token 之间用 AND 连接 → 「同时包含」语义
            var whereClauses: [String] = []
            var arguments: [DatabaseValueConvertible] = []
            for token in cleaned {
                // 用 LOWER(...) 让英文不区分大小写；中文本无大小写，不受影响
                whereClauses.append("(LOWER(content_summary) LIKE LOWER(?) OR LOWER(source_app_name) LIKE LOWER(?))")
                let like = "%\(token)%"
                arguments.append(like)
                arguments.append(like)
            }

            let whereSQL = whereClauses.joined(separator: " AND ")
            let sql = """
                SELECT *
                FROM clipboard_items
                WHERE \(whereSQL)
                ORDER BY is_pinned DESC, updated_at DESC
                """

            return try ClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// 统计总数
    nonisolated func count() async throws -> Int {
        try await dbQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    // MARK: - CRUD: Update

    /// 更新一条条目（全字段覆盖）
    nonisolated func update(_ item: ClipboardItem) async throws {
        try await dbQueue.write { db in
            try item.update(db)
        }
    }

    /// 仅更新条目的"置顶状态 + 置顶时间"
    /// - Parameters:
    ///   - id: 条目 ID
    ///   - isPinned: 目标状态
    ///
    /// 拆成 if/else 两条 SQL，避免 `[Int, Date?, String]` 混合参数让 Swift
    /// 类型推断退化成 Optional<Any>，导致写入失败的隐性 bug。
    nonisolated func setPinned(id: String, isPinned: Bool) async throws {
        try await dbQueue.write { db in
            if isPinned {
                try db.execute(
                    sql: "UPDATE clipboard_items SET is_pinned = 1, pinned_at = ? WHERE id = ?",
                    arguments: [Date(), id]
                )
            } else {
                try db.execute(
                    sql: "UPDATE clipboard_items SET is_pinned = 0, pinned_at = NULL WHERE id = ?",
                    arguments: [id]
                )
            }
            Log.storage.info("setPinned 完成：id=\(id, privacy: .public), isPinned=\(isPinned)")
        }
    }

    /// 统计置顶条目数（用于"是否达 20 条上限"判断）
    nonisolated func pinnedCount() async throws -> Int {
        try await dbQueue.read { db in
            try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == true)
                .fetchCount(db)
        }
    }

    // MARK: - CRUD: Delete

    /// 按 ID 删除一条
    /// - Parameter id: 条目 ID
    /// - Returns: 是否实际删除了（true 表示找到并删除；false 表示不存在）
    @discardableResult
    nonisolated func delete(id: String) async throws -> Bool {
        try await dbQueue.write { db in
            try ClipboardItem.deleteOne(db, key: id)
        }
    }

    /// 清空所有条目（保留表结构）
    /// - Parameter includesPinned: 是否包含置顶条目（默认不包含）
    /// - Returns: 删除的条目数
    @discardableResult
    nonisolated func deleteAll(includesPinned: Bool = false) async throws -> Int {
        try await dbQueue.write { db in
            if includesPinned {
                return try ClipboardItem.deleteAll(db)
            } else {
                return try ClipboardItem
                    .filter(ClipboardItem.Columns.isPinned == false)
                    .deleteAll(db)
            }
        }
    }

    /// 按来源 App 删除所有条目（用于清理测试/自检数据）
    /// - Parameter sourceAppName: 来源 App 名（精确匹配）
    /// - Returns: 删除的条目数
    @discardableResult
    nonisolated func deleteAll(bySourceAppName sourceAppName: String) async throws -> Int {
        try await dbQueue.write { db in
            try ClipboardItem
                .filter(ClipboardItem.Columns.sourceAppName == sourceAppName)
                .deleteAll(db)
        }
    }

    // MARK: - Cleanup（M7）

    /// 拉取所有"过期且非置顶"的条目（用于自动清理）
    /// - Parameter expireBefore: 截止时间，updated_at 早于此值的会被认为过期
    /// - Returns: 满足条件的条目（含 contentFilePath，调用方可一并删硬盘文件）
    nonisolated func fetchExpiredNonPinned(expireBefore: Date) async throws -> [ClipboardItem] {
        try await dbQueue.read { db in
            try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == false)
                .filter(ClipboardItem.Columns.updatedAt < expireBefore)
                .fetchAll(db)
        }
    }

    /// 拉取"普通条目中超出 cap 后多出来的最旧 N 条"（用于 FIFO 清理）
    /// - Parameter cap: 普通条目上限（默认 500，详见需求文档 § 4.2.4）
    /// - Returns: 应被删除的最旧 N 条
    nonisolated func fetchNormalOverflowing(cap: Int) async throws -> [ClipboardItem] {
        try await dbQueue.read { db in
            // 先按 updated_at DESC 取，跳过前 cap 条，剩下即为多余
            let total = try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == false)
                .fetchCount(db)
            guard total > cap else { return [] }
            let overflow = total - cap
            return try ClipboardItem
                .filter(ClipboardItem.Columns.isPinned == false)
                .order(ClipboardItem.Columns.updatedAt.asc)   // 最旧的在前
                .limit(overflow)
                .fetchAll(db)
        }
    }

    /// 批量删除条目 + 同步删除关联文件
    /// - Parameter items: 待删除条目（通常由 fetchExpiredNonPinned / fetchNormalOverflowing 取得）
    /// - Returns: 实际删除的条目数
    @discardableResult
    nonisolated func deleteItemsWithFiles(_ items: [ClipboardItem]) async throws -> Int {
        guard !items.isEmpty else { return 0 }
        // 1. 先删硬盘文件（即使数据库删失败，孤儿文件可被下次清理捡到）
        for item in items {
            deleteAssociatedFile(of: item)
        }
        // 2. 批量删数据库
        let ids = items.map(\.id)
        return try await dbQueue.write { db in
            try ClipboardItem
                .filter(ids.contains(ClipboardItem.Columns.id))
                .deleteAll(db)
        }
    }

    // MARK: - Deduplication

    /// 查找与"最近一条"内容相同的条目
    ///
    /// 用于去重：M3 剪贴板监听捕获到新内容时，先查最近一条，
    /// 如果内容相同则只更新时间戳，不重复插入。
    ///
    /// - Parameter contentSummary: 内容摘要（用于匹配）
    /// - Returns: 找到的条目（按 updated_at 降序的最新一条匹配）
    nonisolated func findLatestMatching(contentSummary: String) async throws -> ClipboardItem? {
        try await dbQueue.read { db in
            try ClipboardItem
                .filter(ClipboardItem.Columns.contentSummary == contentSummary)
                .order(ClipboardItem.Columns.updatedAt.desc)
                .fetchOne(db)
        }
    }

    /// 更新条目的"最近一次复制时间"为现在
    /// - Parameter id: 条目 ID
    nonisolated func touchUpdatedAt(id: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_items SET updated_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    // MARK: - File Storage

    /// 保存图片数据到 `images/<uuid>.png`
    /// - Parameter data: PNG 数据
    /// - Returns: 文件名（不含路径，如 "uuid.png"）
    nonisolated func saveImage(data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileName
    }

    /// 保存富文本数据到 `rtfs/<uuid>.rtf`
    /// - Parameter data: RTF 数据
    /// - Returns: 文件名（不含路径，如 "uuid.rtf"）
    nonisolated func saveRTF(data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).rtf"
        let fileURL = rtfsDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileName
    }

    /// 读取图片数据
    nonisolated func loadImage(fileName: String) -> Data? {
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }

    /// 读取富文本数据
    nonisolated func loadRTF(fileName: String) -> Data? {
        let fileURL = rtfsDirectoryURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }

    /// 删除关联文件（图片或富文本）
    ///
    /// 删除数据库条目时调用，确保硬盘文件同步清理
    nonisolated func deleteAssociatedFile(of item: ClipboardItem) {
        guard let fileName = item.contentFilePath else { return }
        let dir: URL
        switch item.type {
        case .image:
            dir = imagesDirectoryURL
        case .rtf:
            dir = rtfsDirectoryURL
        default:
            return
        }
        let fileURL = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    /// 获取默认存储目录：`~/Library/Application Support/ClipBlue/`
    private static func defaultSupportDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("ClipBlue", isDirectory: true)
    }

    /// 确保目录存在（不存在则创建）
    private static func ensureDirectoryExists(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                Log.storage.info("已创建存储目录：\(url.path, privacy: .public)")
            } catch {
                throw StorageError.directoryCreationFailed(path: url.path, underlying: error)
            }
        }
    }
}
