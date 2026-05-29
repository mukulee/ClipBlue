//
//  TimeFormatter.swift
//  ClipBlue
//
//  时间格式化工具（相对时间显示）
//
//  对应 Milestone：M4 主面板 UI
//  规范依据：需求文档.md § 4.4.3 时间显示规则
//
//  | 时间差 | 显示 |
//  |---|---|
//  | 60 秒内 | 刚刚 |
//  | 1 小时内 | X 分钟前 |
//  | 24 小时内 | X 小时前 |
//  | 昨天 | 昨天 HH:mm |
//  | 7 天内 | 周X HH:mm |
//  | 更早 | MM-DD HH:mm |
//

import Foundation

/// 时间格式化工具
enum TimeFormatter {

    // MARK: - Private Formatters（懒加载、单例）

    /// 昨天 HH:mm
    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 周X HH:mm
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE HH:mm"   // 中文 EEEE = "星期X"，下方手工替换为"周X"
        return f
    }()

    /// MM-DD HH:mm
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    /// 用于"周X"的简写映射
    private static let weekdayShortMap: [String: String] = [
        "星期日": "周日",
        "星期一": "周一",
        "星期二": "周二",
        "星期三": "周三",
        "星期四": "周四",
        "星期五": "周五",
        "星期六": "周六"
    ]

    // MARK: - Public API

    /// 将日期格式化为人类友好的相对时间字符串
    /// - Parameters:
    ///   - date: 目标时间
    ///   - now: 当前时间（默认 Date()，单元测试可注入固定时间）
    /// - Returns: 形如 "3 分钟前" / "昨天 14:32" / "周三 09:01" 的字符串
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let diff = now.timeIntervalSince(date)

        // 1. 60 秒内
        if diff < 60 {
            return "刚刚"
        }

        // 2. 1 小时内
        if diff < 3600 {
            let minutes = Int(diff / 60)
            return "\(minutes) 分钟前"
        }

        // 3. 24 小时内
        if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours) 小时前"
        }

        let calendar = Calendar.current

        // 4. 昨天
        if calendar.isDateInYesterday(date) {
            return "昨天 \(hourMinuteFormatter.string(from: date))"
        }

        // 5. 7 天内（不含今天和昨天）
        if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day,
           daysAgo < 7 {
            let raw = weekdayFormatter.string(from: date)
            // 把 "星期X HH:mm" 替换成 "周X HH:mm"
            for (long, short) in weekdayShortMap {
                if raw.hasPrefix(long) {
                    return raw.replacingOccurrences(of: long, with: short)
                }
            }
            return raw
        }

        // 6. 更早
        return monthDayFormatter.string(from: date)
    }
}
