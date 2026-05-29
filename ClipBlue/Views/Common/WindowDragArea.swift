//
//  WindowDragArea.swift
//  ClipBlue
//
//  SwiftUI 桥接：一个透明的 NSView，按住后触发"窗口拖动"
//
//  用于把 SwiftUI 的某个区域（如 SearchBar 顶部空白处）变成"窗口拖拽把手"，
//  类似 macOS 标准窗口的标题栏拖动效果。
//
//  原理：NSView.mouseDown 中调用 window?.performDrag(with:)
//  让 AppKit 接管后续的鼠标拖动 → 窗口位置跟随鼠标移动
//

import SwiftUI
import AppKit

/// 可拖动窗口的透明区域
///
/// 用法（推荐挂在 `.background` 而不是覆盖在内容上，
/// 让子视图的按钮/输入框能正常接收点击）：
/// ```swift
/// SearchBar(...)
///     .background(WindowDragArea(showsDragCursor: supportsPinning))
/// ```
///
/// 子视图（如 TextField、Button）会优先拦截鼠标事件，
/// 只有点在没有交互控件的"空白处"才会触发窗口拖动 —— 这正是我们想要的。
///
/// - Parameter showsDragCursor: 是否在 hover 时显示手型光标。
///   快捷键面板传 `true`（面板可拖动），菜单栏 popover 传 `false`（面板不可拖动）。
struct WindowDragArea: NSViewRepresentable {

    /// 是否在鼠标悬停时显示 openHand 光标
    let showsDragCursor: Bool

    func makeNSView(context: Context) -> NSView {
        DragHandleNSView(showsDragCursor: showsDragCursor)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? DragHandleNSView {
            view.showsDragCursor = showsDragCursor
        }
    }
}

/// 实际响应鼠标按下事件的 NSView
private final class DragHandleNSView: NSView {

    /// 是否在鼠标悬停时显示 openHand 光标
    var showsDragCursor: Bool

    init(showsDragCursor: Bool) {
        self.showsDragCursor = showsDragCursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.showsDragCursor = false
        super.init(coder: coder)
    }

    /// 不接收 first responder（避免抢走搜索框的键盘焦点）
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Tracking Area（光标变化）

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    /// 鼠标进入区域 → 仅在可拖动面板时显示"张开的手"提示用户
    override func cursorUpdate(with event: NSEvent) {
        if showsDragCursor {
            NSCursor.openHand.set()
        }
    }

    // MARK: - 拖动

    /// 鼠标按下时把后续拖动交给 NSWindow（同步阻塞到松手）
    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        NotificationCenter.default.post(name: .clipBlueWindowDragWillStart, object: nil)
        window?.performDrag(with: event)
        NSCursor.openHand.set()
        NotificationCenter.default.post(name: .clipBlueWindowDragDidEnd, object: nil)
    }
}

// MARK: - 通知名

extension Notification.Name {
    /// 用户按下拖拽区，即将开始移动窗口
    static let clipBlueWindowDragWillStart = Notification.Name("ClipBlue.windowDragWillStart")
    /// 用户松开鼠标，窗口拖动结束
    static let clipBlueWindowDragDidEnd = Notification.Name("ClipBlue.windowDragDidEnd")
}
