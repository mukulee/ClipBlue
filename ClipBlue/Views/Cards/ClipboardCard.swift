//
//  ClipboardCard.swift
//  ClipBlue
//
//  剪贴板条目卡片（M4 渲染 + M5 交互）
//
//  规范依据：需求文档.md § 4.4 卡片设计 + § 4.4.5 卡片交互
//

import SwiftUI
import AppKit

/// 剪贴板条目卡片
///
/// 布局：
/// ```
/// ┌─────────────────────────────────────┐
/// │ [📌 / 🗑]   悬停时浮现       [📌]   │  ← 右上角按钮组(悬停可见) / 置顶角标
/// │                                      │
/// │  内容预览                            │
/// │                                      │
/// │ 3 分钟前 · [图标] 微信              │
/// └─────────────────────────────────────┘
/// ```
struct ClipboardCard: View {

    // MARK: - Input

    let item: ClipboardItem

    /// 是否高亮（单击复制成功后短暂闪动 0.3s）
    var isFlashing: Bool = false

    /// 是否被键盘选中（↑↓ 导航）
    var isKeyboardSelected: Bool = false

    /// 单击：复制
    var onCopy: () -> Void = {}

    /// 双击：复制并关面板
    var onCopyAndClose: () -> Void = {}

    /// 置顶 / 取消置顶
    var onTogglePin: () -> Void = {}

    /// 删除（软删除，5 秒可撤销）
    var onDelete: () -> Void = {}

    /// 显示完整内容
    var onShowFullContent: () -> Void = {}

    // MARK: - State

    @State private var isHovering: Bool = false

    // MARK: - Body

    var body: some View {
        // ZStack 分层 —— 把右上角按钮组放在卡片主体之上，
        // 让按钮的 hit-test 优先于卡片的 onTapGesture，
        // 避免点击按钮时被卡片的"单击复制"抢占
        ZStack(alignment: .topTrailing) {

            // ===== Layer 1：卡片主体（响应单击复制 / 双击关面板 / 右键菜单 / 拖拽）=====
            VStack(alignment: .leading, spacing: 6) {
                content
                footerBar
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(borderOverlay)
            .overlay(flashOverlay)
            .contentShape(Rectangle())
            // 双击优先（SwiftUI 会先尝试匹配 count: 2）
            .onTapGesture(count: 2) { onCopyAndClose() }
            .onTapGesture(count: 1) { onCopy() }
            .contextMenu { contextMenu }
            // M10 拖拽：返回 NSItemProvider 把内容拖到其他 App
            // 拖拽开始时广播通知，让未钉住的 NSPanel 自动关闭让用户看到目标 App
            .onDrag {
                NotificationCenter.default.post(
                    name: .clipBlueDragDidStart,
                    object: nil
                )
                return DragItemFactory.makeItemProvider(for: item)
            }
            .help("单击复制 · 双击关面板 · 长按拖拽到其他 App")

            // ===== Layer 2：右上角按钮组（独立 hit-test）=====
            topRightOverlay
        }
        .animation(.easeOut(duration: 0.10), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isFlashing)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - 背景 / 描边 / 高亮覆盖层

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isKeyboardSelected
                ? Palette.cardBackgroundSelected
                : (isHovering
                   // hover 时叠一层很淡的天空蓝（约 22% 不透明度），既明显又不抢眼
                   ? Palette.primaryLight.opacity(0.45)
                   : Palette.cardBackground)
            )
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(strokeColor, lineWidth: strokeWidth)
    }

    /// 三态边框颜色
    private var strokeColor: Color {
        if isKeyboardSelected { return Palette.primary }       // 键盘选中：天空蓝
        if isHovering         { return Palette.primary.opacity(0.55) }   // 鼠标悬停：淡蓝
        return Palette.divider                                  // 默认：极淡灰
    }

    /// 三态边框粗细
    private var strokeWidth: CGFloat {
        if isKeyboardSelected { return 1.5 }
        if isHovering         { return 1.0 }
        return 0.5
    }

    /// 单击复制后的绿色高亮 + ✓ 对勾
    private var flashOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.success.opacity(isFlashing ? 0.18 : 0))
            if isFlashing {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.success)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 右上角按钮组
    //
    // 设计原则：
    // - 已置顶 → 蓝色置顶按钮**始终可见**（一眼能看出"已置顶"，再点一下=取消置顶）
    // - 未置顶 → 悬停时才浮现置顶按钮（保持卡片干净）
    // - 删除按钮 → 只在悬停时显示（避免误触）

    @ViewBuilder
    private var topRightOverlay: some View {
        HStack(spacing: 4) {
            // 1. 置顶切换按钮
            //    - 已置顶：永远显示，蓝色高亮，点击=取消置顶
            //    - 未置顶：仅 hover 时浮现，半透明灰色，点击=置顶
            if item.isPinned {
                circularButton(
                    icon: "pin.fill",
                    bg: Palette.primaryHover,
                    iconColor: .white,
                    help: "已置顶 · 点击取消置顶",
                    rotateDegrees: -30,
                    action: onTogglePin
                )
            } else if isHovering {
                circularButton(
                    icon: "pin.fill",
                    bg: Color(NSColor.controlBackgroundColor).opacity(0.85),
                    iconColor: Palette.textSecondary,
                    help: "置顶（最多 20 条）",
                    rotateDegrees: -30,
                    action: onTogglePin
                )
            }

            // 2. 删除按钮 —— 只在 hover 时浮现
            if isHovering {
                circularButton(
                    icon: "trash.fill",
                    bg: Palette.error,
                    iconColor: .white,
                    help: "删除（5 秒内可撤销）",
                    rotateDegrees: 0,
                    action: onDelete
                )
            }
        }
        .padding(6)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// 通用的圆形小按钮（22×22 + 阴影）
    private func circularButton(
        icon: String,
        bg: Color,
        iconColor: Color,
        help: String,
        rotateDegrees: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .rotationEffect(.degrees(rotateDegrees))
                .frame(width: 22, height: 22)
                .background(Circle().fill(bg))
                .overlay(
                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 内容（按类型分发）

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text:  TextCardContent(item: item)
        case .rtf:   RTFCardContent(item: item)
        case .image: ImageCardContent(item: item)
        case .file:  FileCardContent(item: item)
        case .url:   URLCardContent(item: item)
        }
    }

    // MARK: - 底部条

    private var footerBar: some View {
        HStack(spacing: 6) {
            Text(TimeFormatter.relative(item.updatedAt))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)

            if let appName = item.sourceAppName, !appName.isEmpty {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)

                sourceAppIconView

                Text(appName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .frame(height: 16)
    }

    private var sourceAppIconView: some View {
        Group {
            if let nsImage = AppIconCache.shared.icon(forBundleId: item.sourceAppBundleId) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: 14, height: 14)
        .help(item.sourceAppName ?? "未知应用")
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private var contextMenu: some View {
        Button("复制", action: onCopy)
        Button(item.isPinned ? "取消置顶" : "置顶", action: onTogglePin)
        Divider()
        Button("显示完整内容…", action: onShowFullContent)
        Divider()
        Button("删除", role: .destructive, action: onDelete)
    }
}

// MARK: - Preview

#Preview("文字") {
    ClipboardCard(item: .text("Hello ClipBlue! 这是一段示例文字。", sourceAppName: "Safari", sourceAppBundleId: "com.apple.Safari"))
        .padding()
        .frame(width: 360)
}
