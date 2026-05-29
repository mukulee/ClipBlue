//
//  ClipboardListViewModel.swift
//  ClipBlue
//
//  主面板列表的 ViewModel
//
//  M4：数据加载、监听通知刷新、分组（置顶 / 普通）
//  M5：单击复制、双击复制+关面板、悬停按钮（置顶/删除）、删除撤销、右键菜单
//

import Foundation
import Combine
import AppKit
import os

/// 主面板列表 ViewModel
@MainActor
final class ClipboardListViewModel: ObservableObject {

    // MARK: - Constants

    /// 置顶上限（详见需求文档.md § 4.6.1）
    static let pinnedLimit: Int = 20

    /// 删除撤销的倒计时秒数（详见需求文档.md § 4.7.1）
    static let undoCountdownSeconds: Int = 5

    // MARK: - Published State

    /// 全量条目（已按 置顶 + 时间倒序 排好）
    @Published private(set) var items: [ClipboardItem] = []

    /// 置顶组（is_pinned = 1）
    @Published private(set) var pinnedItems: [ClipboardItem] = []

    /// 普通组（is_pinned = 0）
    @Published private(set) var normalItems: [ClipboardItem] = []

    /// 当前搜索关键词（空字符串 = 不过滤）
    @Published var searchQuery: String = "" {
        didSet {
            // 不立即查询，由 MainPanelView 的 .onChange + debounce 调用 applySearch
        }
    }

    /// 是否处于"搜索态"（用户输入了非空关键词）
    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 是否正在加载
    @Published private(set) var isLoading: Bool = false

    /// 最近一次操作引发的错误（UI 可弹错提示，nil 表示无错）
    @Published var lastError: String?

    /// 全局 Toast 消息（如「✓ 已复制」「置顶已达上限」），nil 表示不显示
    @Published var toast: ToastMessage?

    /// 待撤销的删除操作（nil 表示没有进行中的撤销窗口）
    @Published private(set) var pendingDeletion: PendingDeletion?

    /// 高亮闪动的卡片 ID（单击复制成功时短暂高亮）
    @Published private(set) var flashingItemId: String?

    /// 当前键盘选中的卡片 ID（用于 ↑↓ 导航，nil = 没选中）
    @Published var selectedItemId: String?

    // MARK: - Dependencies

    private let storage: StorageService

    /// 数据库通知监听句柄（deinit 时移除）
    private var observer: NSObjectProtocol?

    /// 撤销定时器
    private var undoTimer: Timer?

    /// 闪动定时器
    private var flashTimer: Timer?

    /// Toast 定时器
    private var toastTimer: Timer?

    // MARK: - Init / Deinit

    init(storage: StorageService = .shared) {
        self.storage = storage
        startObserving()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        undoTimer?.invalidate()
        flashTimer?.invalidate()
        toastTimer?.invalidate()
    }

    // MARK: - Reload

    /// 主动触发一次加载（如打开主面板时）
    func reload() {
        Task { await loadItems() }
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: ClipboardMonitor.didInsertItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadItems()
            }
        }
        Task { await loadItems() }
    }

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 根据搜索状态走不同查询
            let all: [ClipboardItem]
            if isSearching {
                let tokens = searchQuery
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                all = try await storage.search(tokens: tokens)
            } else {
                all = try await storage.fetchAll()
            }

            // 过滤掉"待删除区"中的条目（视觉上立即消失，但数据库仍未真删）
            let visibleAll: [ClipboardItem]
            if let pending = pendingDeletion {
                visibleAll = all.filter { $0.id != pending.item.id }
            } else {
                visibleAll = all
            }
            self.items = visibleAll
            self.pinnedItems = visibleAll.filter { $0.isPinned }
            self.normalItems = visibleAll.filter { !$0.isPinned }
            self.lastError = nil
            Log.ui.debug("主面板列表已刷新，共 \(visibleAll.count) 条 [搜索=\(self.isSearching ? "是" : "否")]")
        } catch {
            self.lastError = error.localizedDescription
            Log.ui.error("加载剪贴板列表失败：\(error.localizedDescription)")
        }
    }

    /// 由 MainPanelView 的 SearchBar 通过 debounce 触发
    func applySearch() {
        reload()
    }

    // MARK: - 单击复制

    /// 单击卡片：把内容写回剪贴板 + 给该卡片打上短暂高亮 + 全局 Toast「✓ 已复制」
    /// - Parameter item: 被点击的卡片
    func copy(_ item: ClipboardItem) {
        let ok = PasteboardWriter.write(item)
        guard ok else {
            showToast(.error("复制失败"))
            return
        }
        flashCard(id: item.id)
        showToast(.success("已复制"))
        // 同时更新该条的"最近复制时间"，让它升到列表最前
        Task {
            try? await storage.touchUpdatedAt(id: item.id)
            // 不需手动 reload，touchUpdatedAt 后下次 reload 会重新排序；
            // 但为了立即体感，直接重排本地数组
            bumpLocal(itemId: item.id)
        }
    }

    /// 双击卡片：复制 + 请求 MenuBarController 关闭面板
    func copyAndClosePanel(_ item: ClipboardItem) {
        copy(item)
        // 通过通知请求关面板（MenuBarController / WindowController 都监听）
        NotificationCenter.default.post(name: .clipBlueRequestClosePanel, object: nil)
    }

    // MARK: - 键盘导航（M8）

    /// 列表中所有可被键盘选中的条目（顺序：置顶组在前，普通组在后）
    private var navigableItems: [ClipboardItem] {
        pinnedItems + normalItems
    }

    /// 选中下一项（↓）
    func selectNext() {
        let items = navigableItems
        guard !items.isEmpty else { return }
        if let current = selectedItemId,
           let idx = items.firstIndex(where: { $0.id == current }) {
            let nextIdx = min(idx + 1, items.count - 1)
            selectedItemId = items[nextIdx].id
        } else {
            selectedItemId = items.first?.id
        }
    }

    /// 选中上一项（↑）
    func selectPrevious() {
        let items = navigableItems
        guard !items.isEmpty else { return }
        if let current = selectedItemId,
           let idx = items.firstIndex(where: { $0.id == current }) {
            let prevIdx = max(idx - 1, 0)
            selectedItemId = items[prevIdx].id
        } else {
            selectedItemId = items.last?.id
        }
    }

    /// 激活当前选中项：复制并请求关面板（对应 Enter 键）
    func activateSelected() {
        guard let id = selectedItemId,
              let item = navigableItems.first(where: { $0.id == id }) else { return }
        copyAndClosePanel(item)
    }

    /// 删除当前选中项（对应 Delete 键）
    func deleteSelected() {
        guard let id = selectedItemId,
              let item = navigableItems.first(where: { $0.id == id }) else { return }
        // 删除后选中下一条
        let items = navigableItems
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if idx + 1 < items.count {
                selectedItemId = items[idx + 1].id
            } else if idx - 1 >= 0 {
                selectedItemId = items[idx - 1].id
            } else {
                selectedItemId = nil
            }
        }
        softDelete(item)
    }

    /// 清空选中状态（面板关闭时调用）
    func clearSelection() {
        selectedItemId = nil
    }

    /// 若当前无选中，则默认选中第一条（面板首次打开时调用）
    func selectFirstIfNeeded() {
        if selectedItemId == nil {
            selectedItemId = navigableItems.first?.id
        }
    }

    // MARK: - 置顶

    /// 切换置顶状态
    func togglePin(_ item: ClipboardItem) {
        Task {
            let willPin = !item.isPinned
            Log.ui.info("🔄 togglePin 调用：id=\(item.id, privacy: .public), 当前 isPinned=\(item.isPinned), 目标 willPin=\(willPin)")

            // 置顶时检查上限
            if willPin {
                do {
                    let count = try await storage.pinnedCount()
                    if count >= Self.pinnedLimit {
                        showToast(.warning("置顶已达上限（\(Self.pinnedLimit) 条）"))
                        return
                    }
                } catch {
                    Log.ui.error("查询置顶数量失败：\(error.localizedDescription)")
                }
            }

            do {
                try await storage.setPinned(id: item.id, isPinned: willPin)

                // 数据库验证：读回看看实际持久化的值
                if let fresh = try await storage.fetch(id: item.id) {
                    Log.ui.info("🔍 写入后数据库读回：id=\(fresh.id, privacy: .public), isPinned=\(fresh.isPinned), pinnedAt=\(String(describing: fresh.pinnedAt))")
                }

                Log.ui.info("\(willPin ? "📌 置顶" : "📍 取消置顶")条目 \(item.id, privacy: .public)")
                await loadItems()

                // ViewModel 状态验证
                Log.ui.info("📊 reload 后：pinnedItems=\(self.pinnedItems.count), normalItems=\(self.normalItems.count)")
            } catch {
                showToast(.error("操作失败：\(error.localizedDescription)"))
            }
        }
    }

    // MARK: - 删除 + 撤销

    /// 软删除：暂存到"待删除区"，UI 立即移除该卡片，撤销条出现 5 秒倒计时
    /// - Parameter item: 被删除的卡片
    func softDelete(_ item: ClipboardItem) {
        // 1. 如果已有未完成的撤销窗口，先把之前的真删
        if let prev = pendingDeletion {
            finalizeDelete(prev.item)
        }

        // 2. 进入待删除区
        let pending = PendingDeletion(item: item, startedAt: Date())
        pendingDeletion = pending

        // 3. 立即从 UI 移除（不等数据库）
        items.removeAll { $0.id == item.id }
        pinnedItems.removeAll { $0.id == item.id }
        normalItems.removeAll { $0.id == item.id }

        // 4. 启动 5 秒倒计时
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(Self.undoCountdownSeconds),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.pendingDeletion, p.item.id == item.id else { return }
                self.finalizeDelete(p.item)
                self.pendingDeletion = nil
            }
        }
        Log.ui.info("🗑 软删除条目 \(item.id, privacy: .public)，\(Self.undoCountdownSeconds) 秒后真删")
    }

    /// 撤销删除：取消倒计时 + 恢复 UI
    func undoDelete() {
        undoTimer?.invalidate()
        undoTimer = nil
        pendingDeletion = nil
        // 重新拉数据，把那条恢复回来（数据库本就没删）
        reload()
        showToast(.success("已撤销"))
    }

    /// 真删（撤销期超时 / 用户切换到下一次删除时立即触发）
    private func finalizeDelete(_ item: ClipboardItem) {
        Task {
            do {
                // 同步删硬盘文件（图片/RTF）
                storage.deleteAssociatedFile(of: item)
                try await storage.delete(id: item.id)
                Log.ui.info("✅ 已真删条目 \(item.id, privacy: .public)")
            } catch {
                Log.ui.error("真删条目失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    /// 让单击复制的卡片短暂高亮 0.3s
    private func flashCard(id: String) {
        flashingItemId = id
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flashingItemId = nil
            }
        }
    }

    /// 展示一条 Toast，1.2 秒后自动消失
    private func showToast(_ msg: ToastMessage) {
        toast = msg
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toast = nil
            }
        }
    }

    /// 把指定 id 的条目在本地数组中"提到最前"（避免单击复制后等下次 reload）
    private func bumpLocal(itemId: String) {
        if let idx = normalItems.firstIndex(where: { $0.id == itemId }) {
            var item = normalItems.remove(at: idx)
            item.updatedAt = Date()
            normalItems.insert(item, at: 0)
        } else if let idx = pinnedItems.firstIndex(where: { $0.id == itemId }) {
            var item = pinnedItems.remove(at: idx)
            item.updatedAt = Date()
            pinnedItems.insert(item, at: 0)
        }
    }
}

// MARK: - Supporting Types

/// 待删除条目（撤销窗口内暂存）
struct PendingDeletion: Equatable, Sendable {
    let item: ClipboardItem
    let startedAt: Date
}

/// 全局 Toast 消息
struct ToastMessage: Equatable, Sendable, Identifiable {
    enum Kind: Sendable {
        case success   // 绿色 ✓
        case warning   // 黄色 ⚠
        case error     // 红色 ✗
    }
    let id = UUID()
    let kind: Kind
    let text: String

    static func success(_ text: String) -> ToastMessage { .init(kind: .success, text: text) }
    static func warning(_ text: String) -> ToastMessage { .init(kind: .warning, text: text) }
    static func error(_ text: String) -> ToastMessage { .init(kind: .error, text: text) }
}

// MARK: - Notifications

extension Notification.Name {
    /// 通知 MenuBarController 关闭当前面板（双击复制后用）
    static let clipBlueRequestClosePanel = Notification.Name("ClipBlue.requestClosePanel")

    /// 通知所有面板控制器关闭自己（用于打开新面板前互斥）
    static let clipBlueCloseAllPanels = Notification.Name("ClipBlue.closeAllPanels")

    /// 钉住状态变化（M9）
    /// userInfo: ["isPinned": Bool]
    static let clipBluePinStateChanged = Notification.Name("ClipBlue.pinStateChanged")

    /// 用户开始拖拽卡片（M10）—— 未钉住的 NSPanel 监听到后自动隐藏
    static let clipBlueDragDidStart = Notification.Name("ClipBlue.dragDidStart")
}
