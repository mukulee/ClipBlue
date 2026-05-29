//
//  ClipBlueApp.swift
//  ClipBlue
//
//  App 入口
//

import SwiftUI

@main
struct ClipBlueApp: App {

    // MARK: - AppDelegate Bridge

    /// 通过 NSApplicationDelegateAdaptor 接入 AppDelegate，
    /// 用于管理菜单栏图标等系统级 UI（这些只能在 AppKit 中创建）。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Scene

    var body: some Scene {
        // 因为本 App 形态为「菜单栏小图标」(LSUIElement = YES)，
        // 主面板通过 NSPopover 弹出，而不是普通窗口。
        // 此处 Settings 场景仅作为占位（macOS 14 要求 SwiftUI App 至少有一个 Scene）。
        // 实际设置窗口将在 M11 阶段实现。
        Settings {
            EmptyView()
        }
    }
}
