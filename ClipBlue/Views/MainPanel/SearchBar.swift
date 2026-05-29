//
//  SearchBar.swift
//  ClipBlue
//
//  主面板顶部搜索栏（M4 仅做 UI 骨架；搜索过滤逻辑见 M6；钉住功能见 M9）
//
//  规范依据：
//   - 需求文档.md § 4.5.4 搜索框交互
//   - 需求文档.md § 5.1 主面板布局（顶部 44px）
//

import SwiftUI

/// 主面板顶部搜索栏
///
/// 包含：🔍 + 输入框 + 清空按钮（仅在有文本时）+ 📍 钉住按钮（M9，仅 NSPanel 模式）
struct SearchBar: View {

    // MARK: - Bindings

    /// 搜索关键词
    @Binding var query: String

    /// 是否已钉住（M9 接通）
    @Binding var isPinned: Bool

    /// 关闭面板回调（仅钉住状态下右上角 ⊗ 使用）
    var onClose: (() -> Void)?

    /// 是否显示钉住按钮（菜单栏 popover 模式下为 false，因为 NSPopover 本身就是 transient）
    var showPinButton: Bool = true

    // MARK: - Focus / Hover

    /// 跟踪搜索框聚焦状态
    @FocusState private var isSearchFocused: Bool

    /// 鼠标悬停状态（用于三处反馈：搜索框 / 钉住按钮 / 关闭按钮 / 顶栏空白）
    @State private var isSearchHovered: Bool = false
    @State private var isPinHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isBarHovered: Bool = false

    // MARK: - Constants

    private static let barHeight: CGFloat = 44

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // 1. 🔍 + 输入框
            searchField

            // 2. 📍 钉住按钮（仅 NSPanel 模式显示）
            if showPinButton {
                pinButton
            }

            // 3. ⊗ 关闭按钮（仅钉住状态展示）
            if showPinButton, isPinned, onClose != nil {
                closeButton
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
        .background(
            // 整个顶栏的极淡 hover 提示（呼应可拖拽语义）
            Rectangle()
                .fill(isBarHovered ? Palette.primaryLight.opacity(0.25) : Color.clear)
                .animation(.easeOut(duration: 0.12), value: isBarHovered)
        )
        .onHover { isBarHovered = $0 }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isSearchFocused ? Palette.primaryHover : Palette.textSecondary)

            // 聚焦时清掉提示文字 "搜索历史…"，让用户看清光标
            TextField("", text: $query, prompt: isSearchFocused ? nil : Text("搜索历史…"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .focused($isSearchFocused)

            // 清空按钮（仅有内容时显示）
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(searchFieldBackground)
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
        .animation(.easeOut(duration: 0.12), value: isSearchHovered)
        .onHover { isSearchHovered = $0 }
    }

    /// 搜索框背景：四态切换 默认 / hover / 已聚焦 / hover+聚焦
    @ViewBuilder
    private var searchFieldBackground: some View {
        let fillColor: Color = {
            if isSearchFocused {
                return Palette.primaryLight.opacity(0.55)
            }
            if isSearchHovered {
                return Color.gray.opacity(0.22)   // hover 时背景稍微变深
            }
            return Color.gray.opacity(0.12)
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSearchFocused ? Palette.primary : Color.clear,
                        lineWidth: 1.2)
        }
    }

    private var pinButton: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPinned ? Palette.primaryHover : Palette.textSecondary)
                .rotationEffect(.degrees(isPinned ? -30 : 0))
                .animation(.easeOut(duration: 0.15), value: isPinned)
                .frame(width: 26, height: 26)
                .background(Circle().fill(pinButtonFill))
        }
        .buttonStyle(.plain)
        .onHover { isPinHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isPinHovered)
        .help(isPinned ? "取消钉住" : "钉住面板（保持在前）")
    }

    /// 钉住按钮背景：默认透明 / hover 淡蓝 / 已激活淡蓝
    private var pinButtonFill: Color {
        if isPinned { return Palette.primaryLight }
        if isPinHovered { return Palette.primaryLight.opacity(0.55) }
        return Color.clear
    }

    private var closeButton: some View {
        Button {
            onClose?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isCloseHovered ? Palette.error : Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isCloseHovered ? Color.red.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isCloseHovered)
        .help("关闭面板")
    }
}

// MARK: - Preview

#Preview("默认") {
    StatefulPreviewWrapper(query: "", isPinned: false)
        .frame(width: 380)
        .padding()
}

#Preview("已钉住") {
    StatefulPreviewWrapper(query: "微信", isPinned: true)
        .frame(width: 380)
        .padding()
}

// 帮 #Preview 在不依赖外部 @State 的情况下展示 Binding 子视图
private struct StatefulPreviewWrapper: View {
    @State var query: String
    @State var isPinned: Bool

    var body: some View {
        SearchBar(query: $query, isPinned: $isPinned, onClose: {})
    }
}
