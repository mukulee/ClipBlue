//
//  RTFCardContent.swift
//  ClipBlue
//
//  富文本类卡片内容（M4）
//
//  规范依据：需求文档.md § 4.4.2
//   - 去掉格式后显示纯文本预览
//   - 右下角加 "Aa" 小标，表明带格式
//

import SwiftUI

/// 富文本类内容预览
///
/// M4 阶段：只显示纯文本预览 + Aa 角标。
/// 复制时仍按富文本输出，那是 M5 阶段的事。
struct RTFCardContent: View {

    let item: ClipboardItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(displayText)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            // "Aa" 富文本小标
            Text("Aa")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.primaryHover)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Palette.primaryLight)
                )
                .offset(x: 0, y: 4)
        }
    }

    private var displayText: String {
        item.contentText ?? item.contentSummary ?? ""
    }
}
