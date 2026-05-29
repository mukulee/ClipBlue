//
//  FileCardContent.swift
//  ClipBlue
//
//  文件路径类卡片内容（M4）
//
//  规范依据：需求文档.md § 4.4.2
//   - 显示 📁 + 文件名 + 路径 + 文件类型图标
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers   // 为 UTType.data

/// 文件路径类内容预览
struct FileCardContent: View {

    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            // 文件类型图标（系统按扩展名/路径取）
            Image(nsImage: fileIcon)
                .resizable()
                .interpolation(.medium)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    // MARK: - Derived

    /// 完整路径（contentText 即为路径）
    private var fullPath: String {
        item.contentText ?? ""
    }

    /// 文件名（路径末段）
    private var fileName: String {
        if !fullPath.isEmpty {
            return (fullPath as NSString).lastPathComponent
        }
        return item.contentSummary ?? "未知文件"
    }

    /// 缩写显示的路径（把 home 替换为 ~）
    private var displayPath: String {
        let home = NSHomeDirectory()
        if fullPath.hasPrefix(home) {
            return "~" + fullPath.dropFirst(home.count)
        }
        return fullPath
    }

    /// 文件图标（按路径让系统决定）
    private var fileIcon: NSImage {
        // path 可能已不存在（文件被删除），但 NSWorkspace 仍能按扩展名给一个通用图标
        if !fullPath.isEmpty {
            return NSWorkspace.shared.icon(forFile: fullPath)
        }
        // 兜底：通用文件图标
        return NSWorkspace.shared.icon(for: .data)
    }
}
