//
//  AppIconCache.swift
//  ClipBlue
//
//  来源 App 图标缓存服务（M4）
//
//  对应 Milestone：M4 主面板 UI
//  规范依据：需求文档.md § 4.4.4
//
//  缓存策略：
//  - 内存级缓存：按 bundleId 缓存 NSImage（轻量，重启重建）
//  - 未启用本地持久化（ClipboardItem.sourceAppIconPath 字段预留给 M7/M14 优化）
//

import AppKit
import Foundation

/// 来源 App 图标缓存
///
/// 用法：
/// ```swift
/// if let icon = AppIconCache.shared.icon(forBundleId: "com.tencent.xinWeChat") {
///     // 显示 NSImage
/// }
/// ```
///
/// 注意：必须在主线程访问（`NSWorkspace` 仅在主线程安全）。
@MainActor
final class AppIconCache {

    // MARK: - Singleton

    static let shared = AppIconCache()

    private init() {}

    // MARK: - Cache

    /// 已缓存的图标（key = bundleId）
    private var cache: [String: NSImage] = [:]

    /// "已确认无图标" 的 bundleId 集合（避免重复查找）
    private var notFoundSet: Set<String> = []

    // MARK: - Public API

    /// 获取指定 bundleId 对应的 App 图标
    /// - Parameter bundleId: 应用 Bundle ID（如 "com.tencent.xinWeChat"）
    /// - Returns: NSImage（未找到返回 nil，由上层显示默认占位）
    func icon(forBundleId bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }

        // 1. 命中缓存
        if let cached = cache[bundleId] {
            return cached
        }

        // 2. 已确认未找到的不再重试
        if notFoundSet.contains(bundleId) {
            return nil
        }

        // 3. 查 App 路径并取系统图标
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            notFoundSet.insert(bundleId)
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        // 设统一展示尺寸（16x16 在 Retina 下也清晰）
        icon.size = NSSize(width: 32, height: 32)
        cache[bundleId] = icon
        return icon
    }

    /// 清空缓存（用户切换主题、调试用）
    func clear() {
        cache.removeAll()
        notFoundSet.removeAll()
    }
}
