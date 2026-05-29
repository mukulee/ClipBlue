//
//  AppDelegate.swift
//  ClipBlue
//
//  App 生命周期 + 菜单栏图标管理 + 剪贴板监听启动
//

import AppKit
import Combine
import os

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Combine

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Properties

    /// 菜单栏图标 + Popover 的统一管理器
    private var menuBarController: MenuBarController?

    /// 剪贴板监听服务
    private var clipboardMonitor: ClipboardMonitor?

    /// 自动清理服务（M7）
    private var cleanupService: CleanupService?

    /// 全局快捷键管理（M8）
    private var hotKeyManager: HotKeyManager?

    /// 全局快捷键唤起的独立面板（M8）
    private var panelWindowController: MainPanelWindowController?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("ClipBlue 启动")

        // 1. 触发 StorageService 初始化（懒加载）
        _ = StorageService.shared

        // 2. 构建菜单栏 UI
        menuBarController = MenuBarController()

        // 3. 清理 M2 阶段的自检数据（一次性，不影响新数据）
        cleanupM2SelfCheckData()

        // 4. 启动剪贴板监听（M3）
        let monitor = ClipboardMonitor()
        monitor.start()
        clipboardMonitor = monitor

        // 5. 启动自动清理服务（M7：启动时跑一次 + 每小时巡检）
        let cleanup = CleanupService()
        cleanup.start()
        cleanupService = cleanup

        // 6. 创建独立面板控制器（M8：⌘+Shift+V 唤起用）
        let windowController = MainPanelWindowController()
        panelWindowController = windowController

        // 7. 注册全局快捷键 ⌘+Shift+V → 切换独立面板
        //
        // 注：Carbon RegisterEventHotKey 不需要辅助功能权限，
        // 它由系统按键事件路由直接派发给本进程。
        let hk = HotKeyManager { [weak windowController] in
            windowController?.toggle()
        }
        if hk.register() {
            Log.app.info("⌨️ 全局快捷键 ⌘+Shift+V 注册成功 · 在任意 App 中按下即可唤起主面板")
        } else {
            Log.app.error("❌ 全局快捷键注册失败（可能与其它 App 冲突）")
        }
        hotKeyManager = hk

        // 8. 同步开机自启状态（M12：把 UserDefaults 中的设置同步到系统）
        LoginItemManager.sync(to: AppSettings.shared.launchAtLogin)
        // 监听设置变化 → 实时同步
        AppSettings.shared.$launchAtLogin
            .dropFirst()   // 跳过初始值
            .sink { newValue in
                // sink closure 默认 @Sendable nonisolated，
                // 而 @Published var launchAtLogin 在主线程修改，所以一定在主线程触发，
                // 用 MainActor.assumeIsolated 解决 actor 隔离冲突。
                // sync(to:) 返回 Bool，必须显式 _ = 丢弃，否则泛型 T 推断冲突（Void vs Bool）
                MainActor.assumeIsolated {
                    _ = LoginItemManager.sync(to: newValue)
                }
            }
            .store(in: &cancellables)

        Log.app.info("🚀 启动完成 · 监听 + 自动清理 + 快捷键 + 开机自启已就绪")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("ClipBlue 退出")
        clipboardMonitor?.stop()
        cleanupService?.stop()
        hotKeyManager?.unregister()
    }

    /// 当所有窗口关闭时，菜单栏 App 不应退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Cleanup

    /// 清理 M2 阶段的自检数据（来源 = "ClipBlue.SelfCheck"）
    /// 让 M3 测试从干净状态开始
    private func cleanupM2SelfCheckData() {
        Task.detached(priority: .utility) {
            do {
                let count = try await StorageService.shared.deleteAll(bySourceAppName: "ClipBlue.SelfCheck")
                if count > 0 {
                    Log.app.info("🧹 清理 M2 自检数据 \(count) 条")
                }
            } catch {
                Log.app.error("清理 M2 自检数据失败：\(error.localizedDescription)")
            }
        }
    }
}
