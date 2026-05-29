//
//  LoginItemManager.swift
//  ClipBlue
//
//  开机自动启动管理（M12）
//
//  规范依据：需求文档.md § 4.11.2 + § 九（权限）
//
//  实现方式：macOS 13+ 的 SMAppService.mainApp（取代旧的 SMLoginItemSetEnabled）
//

import Foundation
import ServiceManagement
import os

/// 开机自启动管理
@MainActor
enum LoginItemManager {

    /// 当前是否设置了开机自启
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 启用开机自启
    /// - Returns: 是否成功
    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            Log.app.info("✅ 开机自启动已启用")
            return true
        } catch {
            Log.app.error("❌ 启用开机自启失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 禁用开机自启
    /// - Returns: 是否成功
    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            Log.app.info("✅ 开机自启动已禁用")
            return true
        } catch {
            Log.app.error("❌ 禁用开机自启失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 把状态同步到目标值
    @discardableResult
    static func sync(to desired: Bool) -> Bool {
        if desired == isEnabled { return true }
        return desired ? enable() : disable()
    }
}
