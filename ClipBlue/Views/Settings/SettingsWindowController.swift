//
//  SettingsWindowController.swift
//  ClipBlue
//
//  设置窗口的生命周期管理（M11）
//
//  保证同时只允许打开一个设置窗口。
//

import AppKit
import SwiftUI

@MainActor
enum SettingsWindow {

    /// 持有当前打开的设置窗口控制器
    private static var current: NSWindowController?

    /// 打开设置窗口（已打开则前置）
    static func show() {
        // 已有窗口 → 直接前置
        if let controller = current, let window = controller.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 新建窗口
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipBlue 设置"
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("ClipBlue.SettingsWindow")
        window.isReleasedWhenClosed = false   // 关闭时不销毁，便于复用

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        current = controller
    }
}
