//
//  PasteboardWriter.swift
//  ClipBlue
//
//  把 ClipboardItem 写回系统剪贴板（M5 单击复制 / 双击复制 / 右键复制 共用）
//
//  关键点：
//  - 写入前先 clearContents() 清空，避免与旧内容混合
//  - 写入时附带 `clipBlueOwnedType` 标记，这样 ClipboardMonitor 的轮询能识别
//    "这是 ClipBlue 自己写的" 并跳过，不会被重新记录一遍
//

import AppKit
import Foundation

/// 写入剪贴板的工具
enum PasteboardWriter {

    /// 将一条历史条目写回系统剪贴板
    /// - Parameters:
    ///   - item: 待复制的剪贴板条目
    ///   - pasteboard: 目标剪贴板（默认系统 general）
    /// - Returns: 是否成功
    @discardableResult
    static func write(_ item: ClipboardItem, pasteboard: NSPasteboard = .general) -> Bool {
        // 1. 先清空（必须，否则旧 declareTypes 残留）
        pasteboard.clearContents()

        // 2. 按类型写入；最后统一附加 clipBlueOwnedType 标记
        let success: Bool
        switch item.type {
        case .text:
            success = writeText(item, to: pasteboard)
        case .url:
            success = writeURL(item, to: pasteboard)
        case .rtf:
            success = writeRTF(item, to: pasteboard)
        case .image:
            success = writeImage(item, to: pasteboard)
        case .file:
            success = writeFile(item, to: pasteboard)
        }

        // 3. 打 ClipBlue 自身标记（让 Monitor 识别后跳过）
        if success {
            pasteboard.setData(Data([0x01]), forType: .clipBlueOwnedType)
        }
        return success
    }

    // MARK: - Type Writers

    private static func writeText(_ item: ClipboardItem, to pb: NSPasteboard) -> Bool {
        guard let text = item.contentText else { return false }
        return pb.setString(text, forType: .string)
    }

    private static func writeURL(_ item: ClipboardItem, to pb: NSPasteboard) -> Bool {
        guard let raw = item.contentText, let url = URL(string: raw) else { return false }
        // 同时写 URL 和纯文本，最大化兼容性（聊天 App / 浏览器都能识别）
        var ok = pb.setString(url.absoluteString, forType: .URL)
        ok = pb.setString(url.absoluteString, forType: .string) && ok
        return ok
    }

    private static func writeRTF(_ item: ClipboardItem, to pb: NSPasteboard) -> Bool {
        guard let fileName = item.contentFilePath,
              let data = StorageService.shared.loadRTF(fileName: fileName) else {
            // 富文本数据丢失，回退到纯文本
            if let text = item.contentText {
                return pb.setString(text, forType: .string)
            }
            return false
        }
        var ok = pb.setData(data, forType: .rtf)
        // 同时写纯文本兜底（不支持 RTF 的 App 仍能粘出文字）
        if let text = item.contentText {
            ok = pb.setString(text, forType: .string) && ok
        }
        return ok
    }

    private static func writeImage(_ item: ClipboardItem, to pb: NSPasteboard) -> Bool {
        guard let fileName = item.contentFilePath,
              let data = StorageService.shared.loadImage(fileName: fileName) else {
            return false
        }
        // 写为 PNG（也可附带 .tiff 以兼容老 App）
        var ok = pb.setData(data, forType: .png)
        if let nsImage = NSImage(data: data),
           let tiff = nsImage.tiffRepresentation {
            ok = pb.setData(tiff, forType: .tiff) && ok
        }
        return ok
    }

    private static func writeFile(_ item: ClipboardItem, to pb: NSPasteboard) -> Bool {
        guard let path = item.contentText else { return false }
        let url = URL(fileURLWithPath: path)
        // .fileURL 是字符串形式
        return pb.setString(url.absoluteString, forType: .fileURL)
    }
}
