//
//  KeyEventCatcher.swift
//  ClipBlue
//
//  键盘事件捕获器（M8）
//
//  把 NSView 的 keyDown 桥接到 SwiftUI 回调，
//  用于在主面板中响应 ↑↓ / Enter / Delete 等导航键。
//
//  原理：用一个不可见的 NSView 自动成为 first responder，
//  接收 NSPanel 的 keyDown 事件并转发到 Swift 闭包。
//

import SwiftUI
import AppKit

/// 键盘事件捕获器
///
/// 用法：作为 `.background(KeyEventCatcher(...))` 挂到 SwiftUI 视图上
///
/// **注意**：
/// - 当 NSTextField/NSTextView（如搜索框）聚焦时，键盘事件会被它优先拦截，
///   仅在搜索框失焦时本组件才生效；这是符合用户预期的行为
///   （在搜索框内按 ↑↓ 应该是光标移动而非切换列表项）
struct KeyEventCatcher: NSViewRepresentable {

    var onArrowDown: () -> Void = {}
    var onArrowUp: () -> Void = {}
    var onReturn: () -> Void = {}
    var onDelete: () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherNSView()
        view.onArrowDown = onArrowDown
        view.onArrowUp = onArrowUp
        view.onReturn = onReturn
        view.onDelete = onDelete

        // 视图挂上去后短暂延时让自己成为 first responder
        // （延时是因为同 layout cycle 中 window 可能还没就绪）
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherNSView else { return }
        view.onArrowDown = onArrowDown
        view.onArrowUp = onArrowUp
        view.onReturn = onReturn
        view.onDelete = onDelete
    }
}

// MARK: - NSView 实现

private final class KeyCatcherNSView: NSView {

    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 挂入 window 时立即抢占 first responder
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // 虚拟键值（与系统语言无关，详见 HIToolbox/Events.h）
        switch event.keyCode {
        case 125:           // down arrow
            onArrowDown?()
        case 126:           // up arrow
            onArrowUp?()
        case 36, 76:        // return / numpad enter
            onReturn?()
        case 51, 117:       // delete / forward delete
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }
}
