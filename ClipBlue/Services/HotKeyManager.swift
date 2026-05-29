//
//  HotKeyManager.swift
//  ClipBlue
//
//  全局快捷键管理（M8）
//
//  规范依据：需求文档.md § 4.8 全局快捷键
//
//  实现方式：直接调用 Apple 原生 Carbon API `RegisterEventHotKey`
//  （不引入 HotKey 第三方库，避免额外 SPM 依赖）
//
//  默认快捷键：⌘ + Shift + V
//

import AppKit
import Carbon.HIToolbox
import Foundation
import os

/// 全局快捷键管理器
///
/// 通过 Carbon `RegisterEventHotKey` 在系统级注册快捷键，
/// 即使 ClipBlue 不在前台也能捕获到按键。
///
/// 注意：使用全局快捷键需要 **辅助功能权限**（Accessibility）。
@MainActor
final class HotKeyManager {

    // MARK: - 默认快捷键

    /// ⌘ + Shift + V 的虚拟键值 + 修饰键
    /// kVK_ANSI_V = 9（V 键的硬件键码，与系统语言无关）
    private static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    private static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    // MARK: - State

    /// Carbon 注册返回的 HotKey 引用（注销时使用）
    private var hotKeyRef: EventHotKeyRef?

    /// Carbon 事件 handler 引用
    private var eventHandlerRef: EventHandlerRef?

    /// 按下快捷键时触发的回调
    private let onTrigger: () -> Void

    /// 标识全局唯一的 HotKeyID（同进程内的多个快捷键用不同的 id 区分）
    private static let hotKeyId: UInt32 = 0xC117B17E  // "ClipBlue" 谐音

    // MARK: - Init

    /// - Parameter onTrigger: 按下快捷键时的回调（在主线程触发）
    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        // deinit 在 actor 隔离要求外，必须用 nonisolated 方式释放
        // 这里直接同步释放，Carbon API 是线程安全的
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Public API

    /// 注册默认快捷键 ⌘ + Shift + V
    /// - Returns: 是否注册成功
    @discardableResult
    func register() -> Bool {
        return register(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers)
    }

    /// 注册指定快捷键
    /// - Parameters:
    ///   - keyCode: 虚拟键值（如 `kVK_ANSI_V`）
    ///   - modifiers: 修饰键组合（`cmdKey | shiftKey` 等 Carbon 常量）
    /// - Returns: 是否注册成功
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // 防重复注册
        unregister()

        // 1. 安装 Event Handler（同进程只装一次）
        if eventHandlerRef == nil {
            installEventHandler()
        }

        // 2. 注册 HotKey
        let hotKeyID = EventHotKeyID(signature: OSType("CLIP".fourCharCode), id: Self.hotKeyId)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            Log.hotkey.error("❌ 注册全局快捷键失败 status=\(status) —— 检查辅助功能权限")
            return false
        }

        self.hotKeyRef = ref
        Log.hotkey.info("✅ 全局快捷键已注册：⌘+Shift+V（keyCode=\(keyCode), modifiers=\(modifiers)）")
        return true
    }

    /// 注销当前快捷键
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            Log.hotkey.info("🚫 全局快捷键已注销")
        }
    }

    // MARK: - 权限检查

    /// 当前 App 是否拥有辅助功能权限（全局快捷键依赖）
    nonisolated static func hasAccessibilityPermission() -> Bool {
        // 不弹系统提示，仅检查
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 弹出系统辅助功能权限请求（首次启动或检测到无权限时调用）
    nonisolated static func requestAccessibilityPermission() {
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - 私有实现

    /// 安装 Carbon 事件 handler，把 kEventHotKeyPressed 路由到 onTrigger
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // 用 Unmanaged 把 self 桥接到 C 回调
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

            // 取出 EventHotKeyID 验证是不是我们关心的快捷键
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr, hkID.id == HotKeyManager.hotKeyId else {
                return OSStatus(eventNotHandledErr)
            }

            // 回调到 Swift（异步派发到主线程）
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onTrigger()
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )

        if status == noErr {
            self.eventHandlerRef = handlerRef
        } else {
            Log.hotkey.error("❌ 安装快捷键 EventHandler 失败 status=\(status)")
        }
    }
}

// MARK: - String → OSType (FourCharCode)

private extension String {
    /// 把 4 个字符的字符串转成 FourCharCode（Carbon 用于事件签名）
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf16.prefix(4) {
            result = (result << 8) + FourCharCode(char & 0xff)
        }
        return result
    }
}
