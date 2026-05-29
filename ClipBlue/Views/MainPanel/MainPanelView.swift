//
//  MainPanelView.swift
//  ClipBlue
//
//  主面板视图（M4 列表 + M5 交互/撤销条/Toast）
//
//  规范依据：
//   - 需求文档.md § 4.3 历史列表
//   - 需求文档.md § 4.4.5 / 4.7 卡片交互 + 删除撤销
//   - 需求文档.md § 5.1 / 5.2 主面板布局 + 撤销条
//

import SwiftUI

/// 主面板：菜单栏点击或全局快捷键弹出的窗口
struct MainPanelView: View {

    // MARK: - Constants

    private static let panelWidth: CGFloat = 380
    private static let panelHeight: CGFloat = 520

    /// 搜索输入 → 实际查询的去抖延时（避免每打一个字就查一次数据库）
    private static let searchDebounceMs: Int = 150

    // MARK: - Input

    /// 是否支持钉住功能
    /// - 菜单栏 popover：传 `false`（NSPopover 是 transient，没法做钉住）
    /// - ⌘+Shift+V NSPanel：传 `true`
    var supportsPinning: Bool = true

    // MARK: - State

    @StateObject private var viewModel = ClipboardListViewModel()
    @State private var isPinned: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // 1. 毛玻璃背景
            VisualEffectBackground(
                material: .popover,
                blendingMode: .behindWindow,
                state: .active
            )

            // 2. 内容主结构
            VStack(spacing: 0) {
                SearchBar(
                    query: $viewModel.searchQuery,
                    isPinned: $isPinned,
                    onClose: {
                        // ⊗ 按钮：强制关面板（即使钉住状态也关）
                        NotificationCenter.default.post(
                            name: .clipBlueRequestClosePanel,
                            object: nil
                        )
                    },
                    showPinButton: supportsPinning
                )
                // 把顶部搜索栏背景变成"窗口拖拽把手"
                // 子视图（输入框、📍 按钮、⊗ 按钮）会优先拦截点击，
                // 只有按在搜索栏空白处才会触发窗口拖动。
                // showsDragCursor: 仅快捷键面板显示手型光标提示可拖动，
                // 菜单栏 popover 不显示（不可移动）
                .background(WindowDragArea(showsDragCursor: supportsPinning))
                Divider().opacity(0.5)

                // 撤销条 —— 仅在 pendingDeletion 存在时插入
                UndoToast(pending: viewModel.pendingDeletion) {
                    viewModel.undoDelete()
                }
                .animation(.easeOut(duration: 0.20), value: viewModel.pendingDeletion)

                if viewModel.items.isEmpty {
                    if viewModel.isSearching {
                        noResultsState
                    } else {
                        emptyState
                    }
                } else {
                    listView
                }
            }

            // 3. 全局 Toast（位于面板中央偏上的位置）
            VStack {
                Spacer().frame(height: 70)
                InlineToastView(toast: viewModel.toast)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.toast)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        // 关键：在 SwiftUI 端把整个内容切成 16px 圆角矩形
        // 这样无论 NSPanel 的 contentView 圆角是否生效，
        // SwiftUI 内部的所有视图（毛玻璃 / 列表 / 搜索栏）都被切到圆角内
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            viewModel.reload()
            // 不自动选中任何卡片 —— 鼠标用户看到的是干净的列表，
            // 键盘用户按 ↑ ↓ 时再触发选中态（详见 ViewModel.selectNext/selectPrevious 的回退逻辑）
        }
        .onDisappear {
            viewModel.clearSelection()
        }
        // 输入框文字变化 → debounce 150ms → 触发数据库查询
        .onChange(of: viewModel.searchQuery) { _, _ in
            scheduleSearch()
            // 搜索时清空选中（鼠标用户也不会看到突兀的蓝色卡片）
            viewModel.selectedItemId = nil
        }
        // 钉住按钮状态变化 → 通知 WindowController 切换 NSPanel 行为
        .onChange(of: isPinned) { _, newValue in
            NotificationCenter.default.post(
                name: .clipBluePinStateChanged,
                object: nil,
                userInfo: ["isPinned": newValue]
            )
        }
        // Esc 清空搜索（系统快捷键）
        .onExitCommand { handleEscape() }
        // 全局键盘事件（↑ ↓ Enter Delete）
        .background(
            KeyEventCatcher(
                onArrowDown: { viewModel.selectNext() },
                onArrowUp:   { viewModel.selectPrevious() },
                onReturn:    { viewModel.activateSelected() },
                onDelete:    { viewModel.deleteSelected() }
            )
        )
    }

    // MARK: - 搜索 Debounce

    /// 用 Task + 短暂 sleep 实现去抖，避免每个键击都打数据库
    @State private var debounceTask: Task<Void, Never>?

    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.searchDebounceMs) * 1_000_000)
            if !Task.isCancelled {
                viewModel.applySearch()
            }
        }
    }

    /// Esc 处理：
    /// - 若搜索框有内容 → 先清空搜索（钉住与否都是这个行为）
    /// - 若搜索框为空且**未钉住** → 关面板
    /// - 若搜索框为空且**已钉住** → 不做事（符合需求 § 4.10.3）
    private func handleEscape() {
        if !viewModel.searchQuery.isEmpty {
            viewModel.searchQuery = ""
            return
        }
        if !isPinned {
            NotificationCenter.default.post(
                name: .clipBlueRequestClosePanel,
                object: nil
            )
        }
    }

    // MARK: - 列表视图

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {

                    // 搜索态下隐藏分组标题（详见需求文档 § 4.5.2）
                    let hideGroupHeaders = viewModel.isSearching

                    // 置顶组
                    if !viewModel.pinnedItems.isEmpty {
                        if !hideGroupHeaders {
                            groupHeader(title: "置顶", icon: "pin.fill")
                        }
                        ForEach(viewModel.pinnedItems) { item in
                            cardView(for: item)
                        }
                    }

                    // 分隔线（两组都有 & 非搜索态时）
                    if !hideGroupHeaders
                        && !viewModel.pinnedItems.isEmpty
                        && !viewModel.normalItems.isEmpty {
                        Divider()
                            .opacity(0.6)
                            .padding(.vertical, 4)
                    }

                    // 普通组
                    if !viewModel.normalItems.isEmpty {
                        if !hideGroupHeaders && !viewModel.pinnedItems.isEmpty {
                            groupHeader(title: "最近", icon: "clock")
                        }
                        ForEach(viewModel.normalItems) { item in
                            cardView(for: item)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 24)   // 底部多留点空间，避免最后一张卡片贴边
                .animation(.spring(response: 0.30, dampingFraction: 0.85), value: viewModel.pinnedItems)
                .animation(.spring(response: 0.30, dampingFraction: 0.85), value: viewModel.normalItems)
            }
            // 底部柔和渐变，让"内容少时下方空白"不那么生硬
            .mask(
                VStack(spacing: 0) {
                    Rectangle().fill(.black)
                    LinearGradient(
                        colors: [.black, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                }
            )
            // 选中变化时自动滚到选中卡片可见区域
            .onChange(of: viewModel.selectedItemId) { _, newId in
                if let id = newId {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// 包装一张卡片 + 接通 ViewModel 的所有动作回调
    private func cardView(for item: ClipboardItem) -> some View {
        ClipboardCard(
            item: item,
            isFlashing: viewModel.flashingItemId == item.id,
            isKeyboardSelected: viewModel.selectedItemId == item.id,
            onCopy: { viewModel.copy(item) },
            onCopyAndClose: { viewModel.copyAndClosePanel(item) },
            onTogglePin: { viewModel.togglePin(item) },
            onDelete: { viewModel.softDelete(item) },
            onShowFullContent: { FullContentWindow.show(for: item) }
        )
        // ⚠️ 关键：把 isPinned 编入 .id，置顶状态变化时强制重建视图，
        //         避免 SwiftUI 视图复用机制导致 ClipboardCard 内部 let item 没刷新
        .id("\(item.id)#\(item.isPinned)")
    }

    /// 分组标题
    private func groupHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .frame(height: 20)
        .padding(.top, 4)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Palette.primary)
                .opacity(0.7)

            Text("还没有任何复制记录哦~")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textPrimary)

            Text("复制点什么试试吧 ✨")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// 搜索无结果状态（详见需求文档 § 4.5.3）
    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.textTertiary)

            Text("没找到「\(viewModel.searchQuery)」相关内容")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text("换个关键词试试？")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    MainPanelView()
}
