//
//  CleanupService.swift
//  ClipBlue
//
//  自动清理服务（M7）
//
//  规范依据：需求文档.md § 4.2 保留时长与自动清理
//
//  职责：
//  - App 启动时执行一次完整清理
//  - 每小时定时清理一次
//  - 删除过期的非置顶条目
//  - 普通记录超 500 条时按 FIFO 删除最旧的
//  - 置顶条目永不参与清理
//  - 删除时同步清理硬盘文件
//

import Foundation
import os

/// 保留时长选项（详见需求文档 § 4.2.1）
enum RetentionDays: Int, CaseIterable, Sendable {
    case one = 1
    case three = 3       // 默认
    case five = 5
    case seven = 7

    /// 默认 3 天
    static let `default`: RetentionDays = .three

    /// 对应的秒数（用于计算过期截止时间）
    var seconds: TimeInterval {
        TimeInterval(rawValue * 24 * 60 * 60)
    }

    var displayName: String { "\(rawValue) 天" }
}

/// 自动清理服务
@MainActor
final class CleanupService {

    // MARK: - Constants

    /// 普通记录条数上限（详见需求文档 § 4.2.4）
    static let normalItemsCap: Int = 500

    /// 后台清理间隔：每 1 小时
    private static let backgroundInterval: TimeInterval = 60 * 60

    // MARK: - Dependencies

    private let storage: StorageService

    /// 保留时长（从 AppSettings 实时获取）
    var retention: RetentionDays {
        AppSettings.shared.retentionDays
    }

    // MARK: - State

    private var timer: Timer?
    private(set) var isRunning: Bool = false

    // MARK: - Init

    init(storage: StorageService = .shared) {
        self.storage = storage
    }

    // MARK: - Lifecycle

    /// 启动服务：立即执行一次 + 开启定时器
    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.cleanup.info("🧹 CleanupService 启动")

        // 启动时立即跑一次
        runCleanupAsync(reason: "App 启动")

        // 定时器：每小时一次
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.backgroundInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runCleanupAsync(reason: "定时巡检")
            }
        }
    }

    /// 停止服务
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        Log.cleanup.info("🛑 CleanupService 停止")
    }

    // MARK: - Cleanup（异步触发）

    /// 触发一次清理（不阻塞调用方）
    func runCleanupAsync(reason: String) {
        Task { await runCleanup(reason: reason) }
    }

    /// 执行完整清理：过期 + FIFO 超限
    @discardableResult
    func runCleanup(reason: String) async -> CleanupReport {
        Log.cleanup.info("🧹 开始清理：原因=\(reason, privacy: .public)，保留 \(self.retention.rawValue) 天")

        var report = CleanupReport()
        let now = Date()
        let expireBefore = now.addingTimeInterval(-self.retention.seconds)

        // 1. 删过期非置顶
        do {
            let expired = try await storage.fetchExpiredNonPinned(expireBefore: expireBefore)
            if !expired.isEmpty {
                let deleted = try await storage.deleteItemsWithFiles(expired)
                report.expiredDeleted = deleted
                Log.cleanup.info("🧹 删除过期条目 \(deleted) 条（更早于 \(expireBefore, privacy: .public)）")
            }
        } catch {
            Log.cleanup.error("清理过期条目失败：\(error.localizedDescription)")
            report.errors.append("过期清理失败：\(error.localizedDescription)")
        }

        // 2. FIFO：普通条目超 cap 时删最旧
        do {
            let overflowing = try await storage.fetchNormalOverflowing(cap: Self.normalItemsCap)
            if !overflowing.isEmpty {
                let deleted = try await storage.deleteItemsWithFiles(overflowing)
                report.overflowDeleted = deleted
                Log.cleanup.info("🧹 FIFO 删除最旧条目 \(deleted) 条（超出 \(Self.normalItemsCap) 上限）")
            }
        } catch {
            Log.cleanup.error("FIFO 清理失败：\(error.localizedDescription)")
            report.errors.append("FIFO 清理失败：\(error.localizedDescription)")
        }

        Log.cleanup.info("✅ 清理完成：过期 \(report.expiredDeleted) + FIFO \(report.overflowDeleted)")

        // 通知 UI 刷新（撤销条不响应清理，列表会自动 reload）
        if report.totalDeleted > 0 {
            NotificationCenter.default.post(
                name: ClipboardMonitor.didInsertItemNotification,
                object: nil
            )
        }

        return report
    }
}

// MARK: - Report

/// 单次清理的统计报告（用于日志 + 单测断言）
struct CleanupReport: Sendable {
    var expiredDeleted: Int = 0
    var overflowDeleted: Int = 0
    var errors: [String] = []

    var totalDeleted: Int { expiredDeleted + overflowDeleted }
    var hadErrors: Bool { !errors.isEmpty }
}
