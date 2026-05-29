//
//  PasteboardHelpers.swift
//  ClipBlue
//
//  剪贴板内容类型识别 + 跳过规则
//
//  对应 Milestone：M3 剪贴板监听
//  规范依据：需求文档.md § 4.1
//

import AppKit
import Foundation

// MARK: - PasteboardType Extensions

extension NSPasteboard.PasteboardType {

    /// 密码管理器标记的"不要记录"类型
    /// 由 1Password 等密码管理器使用，详见 http://nspasteboard.org
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// 临时内容标记
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// ClipBlue 自身标记（避免自己复制的内容又被自己记录）
    static let clipBlueOwnedType = NSPasteboard.PasteboardType("com.liningyu.ClipBlue.owned")
}

// MARK: - PasteboardAnalyzer

/// 剪贴板内容分析器
///
/// 职责：
/// - 判断剪贴板内容是否应该跳过（密码 / 自身 / 空）
/// - 识别内容类型（text / rtf / image / file / url）
/// - 提取内容数据
enum PasteboardAnalyzer {

    // MARK: - Skip Rules

    /// 判断剪贴板内容是否应该跳过记录
    /// - Parameter pasteboard: 系统剪贴板
    /// - Returns: 跳过原因（nil 表示不跳过）
    static func skipReason(pasteboard: NSPasteboard) -> SkipReason? {
        let types = pasteboard.types ?? []

        // 1. 密码管理器内容
        if types.contains(.concealedType) {
            return .password
        }

        // 2. 临时内容
        if types.contains(.transientType) {
            return .transient
        }

        // 3. ClipBlue 自身复制
        if types.contains(.clipBlueOwnedType) {
            return .ownByClipBlue
        }

        // 4. 内容为空
        if pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
           pasteboard.data(forType: .png) == nil,
           pasteboard.data(forType: .tiff) == nil,
           pasteboard.data(forType: .rtf) == nil,
           pasteboard.propertyList(forType: .fileURL) == nil {
            return .empty
        }

        return nil
    }

    // MARK: - Type Detection

    /// 分析剪贴板内容并返回识别结果
    /// - Parameters:
    ///   - pasteboard: 系统剪贴板
    ///   - imageSizeLimit: 图片大小上限（字节）
    /// - Returns: 分析结果；不可识别的返回 nil
    static func analyze(
        pasteboard: NSPasteboard,
        imageSizeLimit: Int = 10 * 1024 * 1024
    ) -> AnalysisResult? {
        let types = pasteboard.types ?? []

        // 识别优先级：图片 > 文件 > 富文本 > URL > 纯文本
        //
        // 注：浏览器复制的链接通常同时含 .URL 和 .string，
        //     先识别为 URL 类型更直观

        // 1. 图片（PNG / TIFF）
        if types.contains(.png), let data = pasteboard.data(forType: .png) {
            guard data.count <= imageSizeLimit else {
                return .oversizeImage(byteSize: data.count, limit: imageSizeLimit)
            }
            return .image(data: data)
        }
        if types.contains(.tiff), let data = pasteboard.data(forType: .tiff) {
            guard data.count <= imageSizeLimit else {
                return .oversizeImage(byteSize: data.count, limit: imageSizeLimit)
            }
            return .image(data: data)
        }

        // 2. 文件路径
        if types.contains(.fileURL), let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString), url.isFileURL {
            return .file(url: url)
        }

        // 3. URL 链接（非文件）
        if types.contains(.URL), let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString), !url.isFileURL {
            return .url(url: url)
        }

        // 4. 富文本（保留格式）
        if types.contains(.rtf), let rtfData = pasteboard.data(forType: .rtf) {
            let plainText = pasteboard.string(forType: .string) ?? ""
            return .rtf(data: rtfData, plainText: plainText)
        }

        // 5. 纯文本
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }

        return nil
    }

    // MARK: - Source App Detection

    /// 获取当前剪贴板内容的来源 App
    ///
    /// 注意：剪贴板没有"来源"元数据，我们通过"当前前台 App"近似获取。
    /// 在 99% 的情况下都是准确的（用户复制后立刻切到 ClipBlue 的概率很低）。
    static func currentSourceApp() -> (name: String?, bundleId: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }

        // 如果前台是 ClipBlue 自己，忽略
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return (nil, nil)
        }

        return (app.localizedName, app.bundleIdentifier)
    }
}

// MARK: - Result Types

extension PasteboardAnalyzer {

    /// 跳过原因
    enum SkipReason: String, CustomStringConvertible {
        case password = "密码管理器内容"
        case transient = "临时内容（标记为不持久化）"
        case ownByClipBlue = "ClipBlue 自身复制"
        case empty = "空内容"

        var description: String { rawValue }
    }

    /// 分析结果
    enum AnalysisResult {
        case text(String)
        case rtf(data: Data, plainText: String)
        case image(data: Data)
        case file(url: URL)
        case url(url: URL)
        case oversizeImage(byteSize: Int, limit: Int)

        /// 内容字节大小（用于统计）
        nonisolated var byteSize: Int {
            switch self {
            case .text(let s): return s.utf8.count
            case .rtf(let d, _): return d.count
            case .image(let d): return d.count
            case .file(let url): return url.absoluteString.utf8.count
            case .url(let url): return url.absoluteString.utf8.count
            case .oversizeImage(let size, _): return size
            }
        }

        /// 简短描述（用于日志）
        nonisolated var debugDescription: String {
            switch self {
            case .text(let s):
                return "文字（\(s.prefix(30))…）"
            case .rtf(_, let plain):
                return "富文本（\(plain.prefix(30))…）"
            case .image(let d):
                return "图片（\(ByteCountFormatter.string(fromByteCount: Int64(d.count), countStyle: .file))）"
            case .file(let url):
                return "文件（\(url.lastPathComponent)）"
            case .url(let url):
                return "链接（\(url.absoluteString.prefix(60))）"
            case .oversizeImage(let size, let limit):
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                let limitStr = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
                return "图片过大（\(sizeStr) > \(limitStr)）"
            }
        }
    }
}
