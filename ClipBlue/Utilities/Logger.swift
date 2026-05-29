//
//  Logger.swift
//  ClipBlue
//
//  统一日志入口（基于 Apple 原生 os.Logger）
//
//  规范依据：docs/05-代码规范.md § 一·禁止事项
//  - 禁止使用 print() 输出日志
//  - 必须用 Logger 输出到 Console.app / Xcode Console
//
//  ⚠️ 注意：使用 Log.xxx.info(...) 等方法的文件必须 `import os`
//  （Swift 6 MEMBER_IMPORT_VISIBILITY 要求显式 import 才能调用扩展方法）
//

import Foundation
import os

/// ClipBlue 全局 Logger
///
/// 用法（调用文件需 `import os`）：
/// ```swift
/// import os
///
/// Log.app.info("App 启动完成")
/// Log.storage.error("数据库写入失败：\(error)")
/// ```
///
/// 在 Console.app 中按 Subsystem `com.liningyu.ClipBlue` 可筛选所有日志。
enum Log {

    /// 当前 App 的 Bundle ID（subsystem）
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "com.liningyu.ClipBlue"

    // MARK: - Category Loggers
    //
    // 使用 nonisolated 让这些 static 属性可在任意 actor 中访问
    // （Logger 本身是 Sendable，安全）

    /// App 生命周期相关
    nonisolated static let app = Logger(subsystem: subsystem, category: "App")

    /// 数据库存储相关
    nonisolated static let storage = Logger(subsystem: subsystem, category: "Storage")

    /// 剪贴板监听相关
    nonisolated static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")

    /// 清理任务相关
    nonisolated static let cleanup = Logger(subsystem: subsystem, category: "Cleanup")

    /// 全局快捷键相关
    nonisolated static let hotkey = Logger(subsystem: subsystem, category: "HotKey")

    /// UI 相关（少用）
    nonisolated static let ui = Logger(subsystem: subsystem, category: "UI")
}
