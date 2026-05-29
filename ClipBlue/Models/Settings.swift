//
//  Settings.swift
//  ClipBlue
//
//  全局设置项（M11）
//
//  规范依据：需求文档.md § 4.11 设置窗口
//
//  存储方式：UserDefaults（macOS 标准位置）
//  访问方式：`AppSettings.shared` 单例 + @Published 属性
//

import Foundation
import Combine

/// 全局设置单例
///
/// 各处订阅方式：
/// ```swift
/// AppSettings.shared.$retentionDays.sink { newValue in ... }
/// ```
@MainActor
final class AppSettings: ObservableObject {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Storage Keys

    private enum Key {
        static let retentionDays = "ClipBlue.retentionDays"
        static let imageSizeLimitMB = "ClipBlue.imageSizeLimitMB"
        static let menuBarIconBlink = "ClipBlue.menuBarIconBlink"
        static let launchAtLogin = "ClipBlue.launchAtLogin"
        static let recordRTF = "ClipBlue.recordRTF"
        static let recordFile = "ClipBlue.recordFile"
    }

    // MARK: - Settings

    /// 保留天数（1 / 3 / 5 / 7），默认 3
    @Published var retentionDays: RetentionDays {
        didSet {
            UserDefaults.standard.set(retentionDays.rawValue, forKey: Key.retentionDays)
        }
    }

    /// 图片大小上限（MB），默认 10，范围 1~50
    @Published var imageSizeLimitMB: Int {
        didSet {
            // 限定范围 1~50
            let clamped = max(1, min(50, imageSizeLimitMB))
            if clamped != imageSizeLimitMB {
                imageSizeLimitMB = clamped
                return
            }
            UserDefaults.standard.set(imageSizeLimitMB, forKey: Key.imageSizeLimitMB)
        }
    }

    /// 菜单栏图标闪烁（默认开启）
    @Published var menuBarIconBlink: Bool {
        didSet { UserDefaults.standard.set(menuBarIconBlink, forKey: Key.menuBarIconBlink) }
    }

    /// 开机自动启动（默认开启）
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// 记录富文本格式（默认开启）
    @Published var recordRTF: Bool {
        didSet { UserDefaults.standard.set(recordRTF, forKey: Key.recordRTF) }
    }

    /// 记录文件路径（默认开启）
    @Published var recordFile: Bool {
        didSet { UserDefaults.standard.set(recordFile, forKey: Key.recordFile) }
    }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard

        // 读取保留天数（默认 3）
        let rawDays = ud.object(forKey: Key.retentionDays) as? Int ?? 3
        self.retentionDays = RetentionDays(rawValue: rawDays) ?? .default

        // 读取图片上限（默认 10）
        let imgMB = ud.object(forKey: Key.imageSizeLimitMB) as? Int ?? 10
        self.imageSizeLimitMB = max(1, min(50, imgMB))

        // 布尔默认值用 register 注册（避免 UserDefaults.bool 把"未设置"当 false）
        ud.register(defaults: [
            Key.menuBarIconBlink: true,
            Key.launchAtLogin: true,
            Key.recordRTF: true,
            Key.recordFile: true
        ])

        self.menuBarIconBlink = ud.bool(forKey: Key.menuBarIconBlink)
        self.launchAtLogin = ud.bool(forKey: Key.launchAtLogin)
        self.recordRTF = ud.bool(forKey: Key.recordRTF)
        self.recordFile = ud.bool(forKey: Key.recordFile)
    }

    // MARK: - 计算属性

    /// 图片字节上限（供 ClipboardMonitor 直接用）
    var imageSizeLimitBytes: Int {
        imageSizeLimitMB * 1024 * 1024
    }
}
