//
//  URLCardContent.swift
//  ClipBlue
//
//  URL 链接类卡片内容（M4）
//
//  规范依据：需求文档.md § 4.4.2
//   - 显示链接文本，自带 🔗 图标
//   - 长链接智能截断显示域名
//

import SwiftUI
import Foundation

/// URL 链接类内容预览
struct URLCardContent: View {

    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.primaryHover)
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                // 第一行：域名（突出显示）
                Text(displayHost)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // 第二行：完整链接（截断）
                Text(fullURL)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    // MARK: - Derived

    private var fullURL: String {
        item.contentText ?? item.contentSummary ?? ""
    }

    /// 提取显示用 host（取不到则回退到完整 URL）
    private var displayHost: String {
        guard let url = URL(string: fullURL), let host = url.host, !host.isEmpty else {
            return fullURL
        }
        return host
    }
}
