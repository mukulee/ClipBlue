//
//  MenuBarController.swift
//  ClipBlue
//
//  菜单栏图标 + NSPopover 主面板控制器
//
//  对应 Milestone：M1 项目骨架
//  后续 Milestone（M3+）会逐步接入真实数据
//

import AppKit
import SwiftUI

/// 菜单栏图标 + Popover 的统一管理器
///
/// 职责：
/// - 在系统顶部状态栏注册一个常驻图标（NSStatusItem）
/// - 单击图标 → 弹出 / 收起 NSPopover（内嵌 SwiftUI 主面板）
/// - 右键图标 → 弹出系统标准菜单（设置 / 关于 / 退出）
final class MenuBarController: NSObject {

    // MARK: - Constants

    /// 主面板尺寸（详见 docs/03-设计规范文档.md §4.2）
    private static let panelSize = CGSize(width: 380, height: 520)

    // MARK: - Properties

    /// 状态栏项（菜单栏里的小图标）
    private let statusItem: NSStatusItem

    /// 主面板 Popover
    private let popover: NSPopover

    /// 右键菜单
    private let contextMenu: NSMenu

    /// 用于点击外部自动关闭 Popover 的事件监听
    private var eventMonitor: Any?

    /// 监听"请求关闭面板"通知（双击复制后由 ViewModel 发出）
    private var closeRequestObserver: NSObjectProtocol?

    /// 监听"新内容入库"通知（M12 用于触发图标闪烁）
    private var newItemObserver: NSObjectProtocol?

    /// 当前闪烁的 task（避免叠加）
    private var blinkTask: Task<Void, Never>?

    // MARK: - Initialization

    override init() {
        // 1. 创建状态栏项（系统级菜单栏图标）
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 2. 创建 Popover
        self.popover = NSPopover()
        self.popover.contentSize = Self.panelSize
        self.popover.behavior = .transient  // 点外部自动关闭
        self.popover.animates = true
        // 内嵌 SwiftUI 主面板视图
        // 菜单栏 popover 模式：不显示钉住按钮（NSPopover 本身就是 transient，无法做钉住）
        self.popover.contentViewController = NSHostingController(
            rootView: MainPanelView(supportsPinning: false)
        )

        // 3. 创建右键菜单
        self.contextMenu = NSMenu()

        super.init()

        setupStatusItemButton()
        setupContextMenu()
        setupClosePanelObserver()
        setupBlinkObserver()
    }

    deinit {
        removeEventMonitor()
        if let closeRequestObserver {
            NotificationCenter.default.removeObserver(closeRequestObserver)
        }
        if let newItemObserver {
            NotificationCenter.default.removeObserver(newItemObserver)
        }
    }

    // MARK: - 闪烁动画

    /// 监听新内容入库通知 → 触发闪烁（仅当用户在设置中开启）
    private func setupBlinkObserver() {
        newItemObserver = NotificationCenter.default.addObserver(
            forName: ClipboardMonitor.didInsertItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AppSettings.shared.menuBarIconBlink else { return }
                self?.blinkIcon()
            }
        }
    }

    /// 让菜单栏图标短暂闪烁（透明度变化 0.3s）
    private func blinkIcon() {
        guard let button = statusItem.button else { return }
        blinkTask?.cancel()
        blinkTask = Task { @MainActor in
            // 闪一下：变淡 → 恢复
            button.alphaValue = 0.3
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled {
                button.alphaValue = 1.0
            }
        }
    }

    // MARK: - 关面板请求监听

    /// 接收以下两个通知：
    /// - `.clipBlueRequestClosePanel` —— 双击复制后短延时关闭（让用户看到 ✓ 反馈）
    /// - `.clipBlueCloseAllPanels`    —— 互斥关闭（NSPanel 唤起前广播）
    private func setupClosePanelObserver() {
        let center = NotificationCenter.default

        closeRequestObserver = center.addObserver(
            forName: .clipBlueRequestClosePanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated {
                    self?.closePopover()
                }
            }
        }

        // 互斥：NSPanel 要显示了 → 立即关 popover
        _ = center.addObserver(
            forName: .clipBlueCloseAllPanels,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let sender = note.object as AnyObject?
            MainActor.assumeIsolated {
                guard let self else { return }
                if let sender, sender === self { return }
                self.closePopover()
            }
        }

        // M10：用户开始拖卡片 → 关 popover 让出视野
        _ = center.addObserver(
            forName: .clipBlueDragDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated {
                    self?.closePopover()
                }
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItemButton() {
        guard let button = statusItem.button else { return }

        // M13：用 SF Symbol "list.clipboard" 作为菜单栏图标
        //      (剪贴板 + 列表语义贴合)；Template Image 跟随系统深浅自动适配
        let symbolName = "list.clipboard"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: "ClipBlue 历史粘贴板")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }

        // 监听左/右键点击（用 sendAction + button.action 模式）
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupContextMenu() {
        // 「打开历史面板」
        let openItem = NSMenuItem(
            title: "打开历史面板",
            action: #selector(openPanelFromMenu),
            keyEquivalent: "v"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        contextMenu.addItem(openItem)

        contextMenu.addItem(.separator())

        // 「设置...」（M11 实现）
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        contextMenu.addItem(settingsItem)

        // 「关于 ClipBlue」
        let aboutItem = NSMenuItem(
            title: "关于 ClipBlue",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        contextMenu.addItem(aboutItem)

        contextMenu.addItem(.separator())

        // 「退出」
        let quitItem = NSMenuItem(
            title: "退出 ClipBlue",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        contextMenu.addItem(quitItem)
    }

    // MARK: - Click Handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePopover()
            return
        }

        switch currentEvent.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp:
            togglePopover()
        default:
            togglePopover()
        }
    }

    private func showContextMenu() {
        // 显示右键菜单的标准做法：临时设置 menu 然后让系统接管
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        // 显示后清空 menu，恢复左键的 popover 行为
        statusItem.menu = nil
    }

    // MARK: - Popover

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // 互斥：广播"关掉其他面板"，发送方传 self 让自己不响应
        NotificationCenter.default.post(name: .clipBlueCloseAllPanels, object: self)
        // 把 ClipBlue 临时切换到前台，确保 popover 能正确接收焦点
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startEventMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
        removeEventMonitor()
    }

    // MARK: - Event Monitor（点击外部自动关闭）

    private func startEventMonitor() {
        // NSPopover.behavior = .transient 已能处理多数情况，
        // 但加一层全局监听更稳妥（兼容某些边缘场景）。
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Menu Actions

    @objc private func openPanelFromMenu() {
        showPopover()
    }

    @objc private func openSettings() {
        SettingsWindow.show()
    }

    @objc private func showAbout() {
        // 简版「关于」面板，正式版会在 M11 设置窗口的「关于」Tab 实现
        let alert = NSAlert()
        alert.messageText = "ClipBlue"
        alert.informativeText = """
        版本：1.0.0 (Build 1)
        作者：李凝宇
        
        Mac 端剪贴板历史记录工具
        100% 本地存储 · 无任何网络请求
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
