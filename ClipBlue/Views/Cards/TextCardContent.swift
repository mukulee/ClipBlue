//
//  TextCardContent.swift
//  ClipBlue
//
//  文字类卡片内容（M4）
//
//  规范依据：需求文档.md § 4.4.2
//   - 显示前 3 行
//   - 超出加 "…"
//   - 保留换行
//

import SwiftUI

/// 文字类内容预览
struct TextCardContent: View {
    let item: ClipboardItem

    var body: some View {
        Text(displayText)
            .font(.system(size: 13))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 取 contentText（首选）或 contentSummary 兜底
    private var displayText: String {
        item.contentText ?? item.contentSummary ?? ""
    }
}

#Preview {
    VStack {
        TextCardContent(item: .text("单行短文本"))
            .padding()
        TextCardContent(item: .text("""
        多行长文本：
        第二行内容
        第三行内容
        第四行（会被截断）
        第五行
        """))
            .padding()
    }
    .frame(width: 360)
}
