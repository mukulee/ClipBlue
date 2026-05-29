//
//  ImageCardContent.swift
//  ClipBlue
//
//  图片类卡片内容（M4）
//
//  规范依据：需求文档.md § 4.4.2
//   - 等比缩放，最大高度 200px
//   - 圆角 8px
//   - 图片丢失时显示「[图片已丢失]」灰色占位
//

import SwiftUI
import AppKit

/// 图片类内容预览
struct ImageCardContent: View {

    let item: ClipboardItem

    /// 异步加载的图片（避免主线程读硬盘）
    @State private var nsImage: NSImage?
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if loadFailed {
                missingPlaceholder
            } else {
                // 加载中的占位（很短的瞬间）
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.10))
                    .frame(height: 60)
            }
        }
        .task(id: item.contentFilePath) {
            await loadImage()
        }
    }

    // MARK: - Subviews

    private var missingPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(Palette.textTertiary)
            Text("[图片已丢失]")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    // MARK: - Loading

    private func loadImage() async {
        let fileName = item.contentFilePath
        guard let fileName, !fileName.isEmpty else {
            self.loadFailed = true
            return
        }
        // 关键：Task.detached 闭包只返回 `Data`（Sendable），
        // 跨 actor 边界后再在主线程构造 NSImage
        // （NSImage 在 macOS Sequoia 中显式标记为非 Sendable）
        let data: Data? = await Task.detached(priority: .userInitiated) {
            StorageService.shared.loadImage(fileName: fileName)
        }.value

        if let data, let image = NSImage(data: data) {
            self.nsImage = image
            self.loadFailed = false
        } else {
            self.nsImage = nil
            self.loadFailed = true
        }
    }
}
