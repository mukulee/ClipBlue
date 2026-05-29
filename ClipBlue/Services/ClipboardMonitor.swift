//
//  ClipboardMonitor.swift
//  ClipBlue
//
//  剪贴板监听服务（M3 核心）
//
//  规范依据：
//   - 需求文档.md § 4.1 自动记录
//   - docs/02-技术架构文档.md § 3.2 监听机制
//

import AppKit
import Foundation
import os

// MARK: - ClipboardMonitor

/// 剪贴板监听服务
///
/// 通过 `NSPasteboard.changeCount` 轮询（每 0.5 秒），
/// 检测到变化后：
/// 1. 跳过密码 / 临时 / ClipBlue 自身 / 空内容
/// 2. 识别类型（text / rtf / image / file / url）
/// 3. 去重（与最近一条对比）
/// 4. 写入数据库 + 关联文件落盘
/// 5. 通过 NotificationCenter 通知 UI 刷新
@MainActor
final class ClipboardMonitor {

    // MARK: - Constants

    /// 轮询间隔（秒）
    /// 0.5s 在响应速度与 CPU 占用间取得平衡（详见 docs/02 § 3.2）
    private static let pollingInterval: TimeInterval = 0.5

    /// 默认图片大小上限（字节）
    private static let defaultImageSizeLimit = 10 * 1024 * 1024 // 10 MB

    /// 数据库内容变化通知名（UI 监听此通知刷新列表）
    static let didInsertItemNotification = Notification.Name("ClipBlue.didInsertItem")

    // MARK: - Properties

    /// 当前监听的剪贴板
    private let pasteboard: NSPasteboard

    /// 存储服务
    private let storage: StorageService

    /// 最近一次记录的 changeCount，用于检测变化
    private var lastChangeCount: Int

    /// 轮询定时器
    private var timer: Timer?

    /// 是否已启动
    private(set) var isRunning: Bool = false

    /// 图片大小上限（可由 Settings 修改，M11 接入）
    var imageSizeLimit: Int = defaultImageSizeLimit

    // MARK: - Initialization

    init(
        pasteboard: NSPasteboard = .general,
        storage: StorageService = .shared
    ) {
        self.pasteboard = pasteboard
        self.storage = storage
        // 初始化时记录当前 changeCount，避免启动瞬间把"用户启动前复制的内容"也记录上
        self.lastChangeCount = pasteboard.changeCount
        // 从 Settings 读取实时配置
        self.imageSizeLimit = AppSettings.shared.imageSizeLimitBytes
    }

    // MARK: - Lifecycle

    /// 启动监听
    func start() {
        guard !isRunning else {
            Log.clipboard.warning("ClipboardMonitor 已在运行，忽略重复 start()")
            return
        }
        isRunning = true
        Log.clipboard.info("📋 剪贴板监听已启动（轮询间隔 \(Self.pollingInterval) 秒）")

        timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            // Timer 回调在 main runloop，配合 @MainActor，安全
            Task { @MainActor [weak self] in
                self?.pollClipboard()
            }
        }
    }

    /// 停止监听
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        Log.clipboard.info("📋 剪贴板监听已停止")
    }

    // MARK: - Polling

    private func pollClipboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // 1. 检查是否应跳过
        if let reason = PasteboardAnalyzer.skipReason(pasteboard: pasteboard) {
            Log.clipboard.debug("⏭ 跳过此次剪贴板变化：\(String(describing: reason))")
            return
        }

        // 每次 poll 都从 Settings 取最新上限（用户改设置可立即生效）
        let currentImageLimit = AppSettings.shared.imageSizeLimitBytes

        // 2. 分析内容
        guard let result = PasteboardAnalyzer.analyze(
            pasteboard: pasteboard,
            imageSizeLimit: currentImageLimit
        ) else {
            Log.clipboard.debug("⏭ 无法识别的剪贴板内容类型，跳过")
            return
        }

        // 3. 按设置开关跳过 富文本 / 文件
        switch result {
        case .rtf where !AppSettings.shared.recordRTF:
            Log.clipboard.debug("⏭ 设置中已关闭'记录富文本'，跳过")
            return
        case .file where !AppSettings.shared.recordFile:
            Log.clipboard.debug("⏭ 设置中已关闭'记录文件路径'，跳过")
            return
        default:
            break
        }

        // 3. 过滤过大图片
        if case .oversizeImage = result {
            Log.clipboard.notice("⚠️ \(result.debugDescription)")
            return
        }

        // 4. 获取来源 App
        let source = PasteboardAnalyzer.currentSourceApp()
        let sourceName = source.name ?? "未知应用"

        // 5. 处理并入库（异步）
        Task.detached(priority: .utility) { [storage] in
            await Self.persist(
                result: result,
                sourceName: source.name,
                sourceBundleId: source.bundleId,
                storage: storage,
                sourceDescription: sourceName
            )
        }
    }

    // MARK: - Persistence

    /// 处理分析结果并写入数据库
    nonisolated private static func persist(
        result: PasteboardAnalyzer.AnalysisResult,
        sourceName: String?,
        sourceBundleId: String?,
        storage: StorageService,
        sourceDescription: String
    ) async {
        do {
            // 构造数据库条目
            let item: ClipboardItem

            switch result {
            case .text(let text):
                item = .text(text, sourceAppName: sourceName, sourceAppBundleId: sourceBundleId)

            case .rtf(let data, let plain):
                let fileName = try storage.saveRTF(data: data)
                item = .rtf(
                    fileName: fileName,
                    plainText: plain,
                    byteSize: data.count,
                    sourceAppName: sourceName,
                    sourceAppBundleId: sourceBundleId
                )

            case .image(let data):
                let fileName = try storage.saveImage(data: data)
                item = .image(
                    fileName: fileName,
                    byteSize: data.count,
                    sourceAppName: sourceName,
                    sourceAppBundleId: sourceBundleId
                )

            case .file(let url):
                item = .file(url: url, sourceAppName: sourceName, sourceAppBundleId: sourceBundleId)

            case .url(let url):
                item = .url(url, sourceAppName: sourceName, sourceAppBundleId: sourceBundleId)

            case .oversizeImage:
                return  // 上层已过滤
            }

            // 去重：与最近一条对比 contentSummary
            if let summary = item.contentSummary,
               let existing = try await storage.findLatestMatching(contentSummary: summary),
               existing.type == item.type {
                // 内容完全一样 → 只更新时间戳（让它升到最前面）
                try await storage.touchUpdatedAt(id: existing.id)
                Log.clipboard.info("🔁 重复内容，更新时间戳：\(result.debugDescription, privacy: .public) ← \(sourceDescription, privacy: .public)")
                // 同步删除新生成的关联文件（避免重复文件占空间）
                storage.deleteAssociatedFile(of: item)
            } else {
                // 新内容 → 插入
                try await storage.insert(item)
                Log.clipboard.info("✅ 记录新内容：\(result.debugDescription, privacy: .public) ← \(sourceDescription, privacy: .public)")
            }

            // 通知 UI 刷新（M4 阶段会接入）
            await MainActor.run {
                NotificationCenter.default.post(
                    name: ClipboardMonitor.didInsertItemNotification,
                    object: nil
                )
            }
        } catch {
            Log.clipboard.error("❌ 记录失败：\(error.localizedDescription)")
        }
    }
}
