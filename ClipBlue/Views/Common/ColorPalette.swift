//
//  ColorPalette.swift
//  ClipBlue
//
//  全局配色系统（M4）
//
//  规范依据：需求文档.md § 6.1 + docs/03-设计规范文档.md
//
//  所有 UI 颜色统一从这里取，方便后续主题/暗黑模式适配。
//

import SwiftUI

/// ClipBlue 全局配色系统
///
/// 用法：
/// ```swift
/// Rectangle().fill(Palette.cardBackground)
/// Text("标题").foregroundStyle(Palette.textPrimary)
/// ```
enum Palette {

    // MARK: - 主色（天空蓝）

    /// 主色：天空蓝 `#A8D8FF`
    /// 用于：置顶图标、选中态边框、品牌色
    static let primary = Color(red: 168/255, green: 216/255, blue: 255/255)

    /// 主色（hover 加深）：`#7BC0F5`
    /// 用于：按钮悬停态
    static let primaryHover = Color(red: 123/255, green: 192/255, blue: 245/255)

    /// 主色（浅）：`#E1F1FF`
    /// 用于：键盘选中卡片的背景色
    static let primaryLight = Color(red: 225/255, green: 241/255, blue: 255/255)

    // MARK: - 文字

    /// 文字主色（亮模式 `#1C1C1E`，暗模式白）
    /// 用 SwiftUI 系统 primary，自动适配深浅
    static let textPrimary = Color.primary

    /// 文字次色（亮模式 `#8E8E93`，暗模式半透明白）
    static let textSecondary = Color.secondary

    /// 文字浅色（占位符）
    static let textTertiary = Color(NSColor.tertiaryLabelColor)

    // MARK: - 卡片

    /// 卡片底色（半透明白 / 半透明深灰，自动适配）
    static let cardBackground = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(white: 0.20, alpha: 0.60)
            : NSColor(white: 1.00, alpha: 0.60)
    })

    /// 卡片悬停态底色（不透明度更高）
    static let cardBackgroundHover = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(white: 0.26, alpha: 0.85)
            : NSColor(white: 1.00, alpha: 0.85)
    })

    /// 键盘选中卡片的背景（淡蓝）
    static let cardBackgroundSelected = primaryLight.opacity(0.7)

    // MARK: - 分隔线

    /// 卡片间分隔线：`rgba(0,0,0,0.08)`
    static let divider = Color(NSColor.separatorColor)

    // MARK: - 反馈色

    /// 成功提示（绿）：`#34C759`
    static let success = Color(red: 52/255, green: 199/255, blue: 89/255)

    /// 警告提示（橙）：`#FF9500` — 撤销条
    static let warning = Color(red: 255/255, green: 149/255, blue: 0/255)

    /// 错误提示（红）：`#FF3B30`
    static let error = Color(red: 255/255, green: 59/255, blue: 48/255)
}
