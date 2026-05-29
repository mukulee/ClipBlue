//
//  UndoToast.swift
//  ClipBlue
//
//  顶部"已删除 · 撤销"提示条 + 全局轻提示 Toast（M5）
//
//  规范依据：需求文档.md § 4.7.1 + § 5.2
//

import SwiftUI

/// 删除撤销提示条（停留 5 秒，倒计时进度可视化）
///
/// 显示位置：主面板搜索栏正下方，覆盖一行高
struct UndoToast: View {

    /// 待撤销的删除（nil 时不显示）
    let pending: PendingDeletion?

    /// 用户点击撤销
    var onUndo: () -> Void

    var body: some View {
        if let pending {
            content(for: pending)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func content(for pending: PendingDeletion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)

            Text("已删除 1 条记录")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onUndo) {
                Text("撤销")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: [.command])
            .help("⌘+Z 撤销")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.85))
        )
    }
}

/// 轻提示 Toast（如「✓ 已复制」「⚠ 置顶已达上限」），显示在面板中央偏上
struct InlineToastView: View {

    let toast: ToastMessage?

    var body: some View {
        if let toast {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: toast.kind))
                    .font(.system(size: 13, weight: .bold))
                Text(toast.text)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color(for: toast.kind).opacity(0.92))
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private func iconName(for kind: ToastMessage.Kind) -> String {
        switch kind {
        case .success: return "checkmark"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark"
        }
    }

    private func color(for kind: ToastMessage.Kind) -> Color {
        switch kind {
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .error:   return Palette.error
        }
    }
}
