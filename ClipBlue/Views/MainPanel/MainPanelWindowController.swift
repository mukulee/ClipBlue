//
//  MainPanelWindowController.swift
//  ClipBlue
//
//  独立 NSPanel 窗口控制器（M8）
//
//  规范依据：需求文档.md § 4.8.2 / § 4.10
//
//  与 NSPopover（菜单栏点击）的区别：
//  - 通过 ⌘+Shift+V 全局快捷键唤起
//  - 显示在鼠标所在屏幕的中央偏上
//  - 可拖动（顶部搜索栏区域作为拖拽把手）
//  - 失焦自动关闭（未钉住状态；M9 钉住功能扩展为不自动关）
//  - 共享同一份 MainPanelView，UI 一致
//

import AppKit
import SwiftUI
import os

/// 主面板 NSPanel 控制器
@MainActor
final class MainPanelWindowController: NSObject {

    // MARK: - Constants

    /// 主面板内容尺寸（与 MenuBarController 中的 panelSize 一致）
    private static let panelSize = CGSize(width: 380, height: 520)

    // MARK: - Properties

    private var panel: KeyableNSPanel?

    /// 用于监听点击外部自动关闭面板
    private var globalClickMonitor: Any?

    /// 是否已钉住（M9 主功能）
    /// 仅运行时存活，退出 App 后下次启动重置为 false（详见需求文档 § 4.10.5）
    private var isPinned: Bool = false {
        didSet { applyPinState() }
    }

    /// 监听"请求关闭面板"通知（双击复制后由 ViewModel 发出）
    private var closeRequestObserver: NSObjectProtocol?

    /// 互斥关闭通知监听
    private var closeAllObserver: NSObjectProtocol?

    /// 钉住状态变化监听（SearchBar 📍 按钮 → MainPanelView → 发通知）
    private var pinStateObserver: NSObjectProtocol?

    /// 拖拽开始监听（M10：用户开始拖卡片，未钉住时关面板让出空间）
    private var dragStartObserver: NSObjectProtocol?

    /// 窗口拖动开始 / 结束监听（M13：移动面板时透明度反馈）
    private var windowDragStartObserver: NSObjectProtocol?
    private var windowDragEndObserver: NSObjectProtocol?

    /// 用户开始移动面板前的"基础透明度"（结束时恢复到这个值）
    private var baselineAlphaValue: CGFloat = 1.0

    // MARK: - Init / Deinit

    override init() {
        super.init()
        let center = NotificationCenter.default

        // 注：所有 addObserver(forName:...) 的回调都是 @Sendable nonisolated，
        // 即使指定了 queue: .main，闭包内部也不能直接访问 MainActor 隔离的成员。
        // 这里用 `MainActor.assumeIsolated` 显式断言"我们在主线程"，从而合法访问。
        // 这要求 queue 必须是 .main，否则会崩溃。

        // 双击复制后自动关面板
        closeRequestObserver = center.addObserver(
            forName: .clipBlueRequestClosePanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated {
                    self?.close()
                }
            }
        }

        // 互斥：菜单栏 popover 要打开 → 关掉本 NSPanel
        closeAllObserver = center.addObserver(
            forName: .clipBlueCloseAllPanels,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let sender = note.object as AnyObject?
            MainActor.assumeIsolated {
                guard let self else { return }
                if let sender, sender === self { return }
                self.close()
            }
        }

        // 监听 SwiftUI 端的钉住状态切换（SearchBar 📍 按钮 → MainPanelView → 发通知）
        pinStateObserver = center.addObserver(
            forName: .clipBluePinStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // 先把 Sendable 数据取出来，再跳进 MainActor 写状态
            let pinned = note.userInfo?["isPinned"] as? Bool
            MainActor.assumeIsolated {
                guard let self, let pinned else { return }
                self.isPinned = pinned
            }
        }

        // M10：用户开始拖卡片 → 未钉住时关面板让出空间
        dragStartObserver = center.addObserver(
            forName: .clipBlueDragDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPinned else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated {
                        self.close()
                    }
                }
            }
        }

        // M13：用户按住搜索栏背景开始移动面板 → 面板半透明做"正在移动"反馈
        windowDragStartObserver = center.addObserver(
            forName: .clipBlueWindowDragWillStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.baselineAlphaValue = panel.alphaValue
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.10
                    panel.animator().alphaValue = 0.78
                }
            }
        }

        // M13：用户松手，恢复到原透明度（钉住 0.95 / 未钉 1.0）
        windowDragEndObserver = center.addObserver(
            forName: .clipBlueWindowDragDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    panel.animator().alphaValue = self.baselineAlphaValue
                }
            }
        }
    }

    deinit {
        let center = NotificationCenter.default
        if let observer = closeRequestObserver {
            center.removeObserver(observer)
        }
        if let observer = closeAllObserver {
            center.removeObserver(observer)
        }
        if let observer = pinStateObserver {
            center.removeObserver(observer)
        }
        if let observer = dragStartObserver {
            center.removeObserver(observer)
        }
        if let observer = windowDragStartObserver {
            center.removeObserver(observer)
        }
        if let observer = windowDragEndObserver {
            center.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// 切换显示/隐藏（绑定到全局快捷键）
    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    /// 显示面板
    func show() {
        // 互斥：广播"关掉其他面板"，object: self 让自己不响应
        NotificationCenter.default.post(name: .clipBlueCloseAllPanels, object: self)

        let panel = panel ?? buildPanel()
        self.panel = panel

        // 位置：鼠标所在屏幕的中央偏上
        positionAtScreenCenterTop(panel: panel)

        // 激活 App + 显示窗口
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // 应用当前钉住状态（同时会接管 globalClickMonitor 的启停）
        applyPinState()
        if !isPinned {
            // 未钉住才启动全局点击监听
            startGlobalClickMonitor()
        }

        // 让阴影根据 SwiftUI 圆角 clipShape 后的真实形状重新计算
        // 否则阴影仍按矩形画，会"露出 4 个角"看起来不和谐
        DispatchQueue.main.async {
            panel.invalidateShadow()
        }
    }

    /// 关闭面板
    func close() {
        panel?.orderOut(nil)
        stopGlobalClickMonitor()
    }

    /// 强制关闭（即使在钉住状态下也关，用于显式点 ⊗ 关闭按钮）
    func forceClose() {
        isPinned = false   // 关之前先取消钉住，确保 close 不被拦截
        close()
    }

    // MARK: - 钉住状态应用

    /// 把 isPinned 状态映射到 NSPanel 的实际行为
    private func applyPinState() {
        guard let panel else { return }

        if isPinned {
            // 1. 浮于一切窗口之上（即使切换 App 也不消失）
            panel.level = .statusBar      // 比 .floating 更高，覆盖 popover、灯光控制等
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // 2. 降低不透明度到 95%
            panel.alphaValue = 0.95

            // 3. 关掉全局点击监听 → 点外面不再触发关闭
            stopGlobalClickMonitor()

            Log.ui.info("📌 面板已钉住：浮于最前 + 透明度 95% + 失焦不关")
        } else {
            // 恢复默认行为
            panel.level = .floating
            panel.collectionBehavior = []
            panel.alphaValue = 1.0

            // 启动全局点击监听 → 点外面关面板
            if panel.isVisible {
                startGlobalClickMonitor()
            }

            Log.ui.info("📍 已取消钉住：恢复正常行为")
        }
    }

    /// 是否正在显示
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - 构建 NSPanel

    private func buildPanel() -> KeyableNSPanel {
        let rect = NSRect(origin: .zero, size: Self.panelSize)
        // 用 .borderless 让窗口完全无框架（无标题栏），由 contentView 全权控制视觉
        // 这样顶部、底部都能受 contentView.layer.cornerRadius 圆角影响
        let panel = KeyableNSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 拖动 —— 只允许从"顶部搜索栏的空白处"拖动（由 SwiftUI 端的 WindowDragArea 实现）
        // 如果开 isMovableByWindowBackground，会和卡片的 .onDrag 互相抢占，
        // 导致钉住面板时拖卡片到其他 App 失效（面板被拖走了，卡片的拖拽没触发）
        panel.isMovable = true
        panel.isMovableByWindowBackground = false

        // 透明背景 + 系统阴影（毛玻璃效果由 SwiftUI 内部 VisualEffectBackground 提供）
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating  // 浮在普通窗口之上

        // 圆角（4 个角都受控）
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 16
        panel.contentView?.layer?.masksToBounds = true

        // SwiftUI 内容
        let hosting = NSHostingController(rootView: MainPanelView())
        panel.contentViewController = hosting

        // 给整个面板内容区添加光标跟踪：
        // 鼠标悬停在空白处 → openHand 光标（提示可拖动）
        // 鼠标悬停在卡片/按钮/输入框上 → 不干预（让控件自己的光标生效）
        if let contentView = panel.contentView {
            let trackingArea = NSTrackingArea(
                rect: contentView.bounds,
                options: [.activeAlways, .cursorUpdate, .inVisibleRect],
                owner: panel,
                userInfo: nil
            )
            contentView.addTrackingArea(trackingArea)
        }

        // 失焦时自动关闭（未钉住）
        panel.onResignKey = { [weak self] in
            guard let self, !self.isPinned else { return }
            self.close()
        }

        return panel
    }

    // MARK: - 位置计算

    /// 把面板放在**鼠标位置旁边**（右下方），同时做屏幕边界保护，
    /// 避免面板被屏幕边缘裁掉一半。
    private func positionAtScreenCenterTop(panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation

        // 取鼠标所在的屏幕（多屏支持）
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }

        let panelSize = panel.frame.size

        // 默认：面板**左上角**贴近鼠标右侧 12px
        // macOS 坐标系：原点在屏幕左下角，y 向上为正
        // 面板的 origin 是左下角，所以 y = mouseY - panelHeight
        var x = mouseLocation.x + 12
        var y = mouseLocation.y - panelSize.height

        // 边界保护：水平方向不要超出屏幕右侧（如果鼠标靠右，把面板放在鼠标左侧）
        if x + panelSize.width > screenFrame.maxX - 8 {
            x = mouseLocation.x - panelSize.width - 12
        }
        // 兜底：不要溢出屏幕左侧
        x = max(x, screenFrame.minX + 8)

        // 边界保护：垂直方向不要溢出屏幕下方（如果鼠标靠下，把面板向上挪）
        if y < screenFrame.minY + 8 {
            y = screenFrame.minY + 8
        }
        // 不要超出屏幕顶部
        y = min(y, screenFrame.maxY - panelSize.height - 8)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 点外部关闭

    private func startGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isPinned else { return }
            self.close()
        }
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

// MARK: - KeyableNSPanel（让 NSPanel 能接收键盘焦点 + 空白区域拖动 + 光标反馈）

/// 自定义 NSPanel 子类
///
/// 默认 NSPanel 无法成为 keyWindow 接收键盘事件。
/// 这里覆写 `canBecomeKey` / `canBecomeMain` 让它能接收键盘事件，
/// 并通过 `onResignKey` 在失焦时通知外部。
///
/// 额外覆写 `sendEvent` 实现"空白区域拖动窗口"：
/// - 如果鼠标点击在交互控件上（Button / TextField / 有 gesture recognizer 的视图）→ 正常处理
/// - 如果鼠标点击在空白区域 → 调用 `performDrag` 触发窗口拖动
///
/// 覆写 `cursorUpdate` 实现"空白区域 hover 手型光标"：
/// - 鼠标悬停在卡片/按钮/输入框上 → 不干预，让控件自己的 cursorUpdate 生效
/// - 鼠标悬停在空白区域 → 显示 openHand 光标提示可拖动
final class KeyableNSPanel: NSPanel {

    /// 失焦回调（点其他 App 或点面板外）
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    // MARK: - 空白区域拖动窗口

    /// 判断点击位置是否在有交互的控件上。
    ///
    /// 用 `hitTest` 找到点击位置对应的视图，沿视图链向上查找：
    /// - 命中 `NSControl`（按钮/输入框/滑块/滚动条）→ 交互控件
    /// - 命中有「可操作的」手势识别器（点击/拖拽/长按/捏合/旋转）的视图 → 交互控件（卡片）
    /// - 只有 hover 手势 → 不是交互控件 → 视为空白区域
    private func isHitOnInteractiveView(at point: NSPoint) -> Bool {
        guard let contentView else { return false }
        let localPoint = contentView.convert(point, from: nil)
        guard let hitView = contentView.hitTest(localPoint) else { return false }

        var current: NSView? = hitView
        while let view = current {
            // 1. AppKit 原生交互控件（TextField / Button / Scroller / Slider 等）
            if view is NSControl {
                return true
            }

            // 2. 检查手势识别器：用 `is` 类型判断而非字符串匹配类名。
            //    标准 AppKit 手势识别器会被 SwiftUI 的 onTapGesture / onDrag 使用；
            //    SwiftUI 内部的 hover/tracking 手势识别器不是这些标准类的实例，会被跳过。
            for gr in view.gestureRecognizers {
                switch gr {
                case is NSClickGestureRecognizer:         // 单击 / 双击
                    fallthrough
                case is NSPressGestureRecognizer:         // 长按
                    fallthrough
                case is NSPanGestureRecognizer:           // 拖拽 / 滑动
                    fallthrough
                case is NSMagnificationGestureRecognizer: // 捏合缩放手势
                    fallthrough
                case is NSRotationGestureRecognizer:      // 旋转手势
                    return true
                default:
                    break   // hover / tracking 等内部手势 → 不是交互控件，跳过
                }
            }

            current = view.superview
        }
        return false
    }

    // MARK: - 光标反馈：空白处 hover 显示手型

    /// 覆写 tracking area 的光标回调。
    /// 内容区装了一个 `NSTrackingArea`（在 `buildPanel` 中）
    /// 当鼠标在面板内移动时系统会触发此方法。
    override func cursorUpdate(with event: NSEvent) {
        // 先检查鼠标当前位置是否在交互控件上。
        // 如果在卡片/按钮/输入框上 → 让控件自己处理光标（不设置手型）
        // 如果在空白区域 → 显示 openHand 提示用户"这里可以拖动"
        if !isHitOnInteractiveView(at: event.locationInWindow) {
            NSCursor.openHand.set()
            return
        }
        // 在交互控件上 → 什么都不做，让视图链里的 DragHandleNSView / 控件来设光标
        super.cursorUpdate(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        // 只在鼠标左键按下时检查
        if event.type == .leftMouseDown {
            if !isHitOnInteractiveView(at: event.locationInWindow) {
                // 点击在空白区域 → 触发窗口拖动（带透明度反馈）
                NSCursor.closedHand.set()
                NotificationCenter.default.post(name: .clipBlueWindowDragWillStart, object: nil)
                performDrag(with: event)
                NSCursor.openHand.set()
                NotificationCenter.default.post(name: .clipBlueWindowDragDidEnd, object: nil)
                return
            }
        }
        super.sendEvent(event)
    }
}
