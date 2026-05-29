//
//  DragItemFactory.swift
//  ClipBlue
//
//  把 ClipboardItem 转换为 NSItemProvider，用于 SwiftUI .onDrag
//
//  对应 Milestone：M10 拖拽功能
//  规范依据：需求文档.md § 4.4.7
//
//  各类型拖拽载荷（payload）：
//  | 卡片类型 | NSItemProvider 类型                         |
//  |---------|---------------------------------------------|
//  | 纯文字   | public.utf8-plain-text                      |
//  | 富文本   | public.rtf + public.utf8-plain-text         |
//  | 图片     | public.png                                  |
//  | 文件路径 | public.file-url                             |
//  | URL 链接 | public.url + public.utf8-plain-text         |
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// 拖拽载荷工厂
enum DragItemFactory {

    /// 把一条 ClipboardItem 包装成可拖拽到其他 App 的 NSItemProvider
    static func makeItemProvider(for item: ClipboardItem) -> NSItemProvider {
        let provider = NSItemProvider()

        switch item.type {

        case .text:
            // 纯文字 → 一个 NSString 注册（系统自动识别为 utf8 plain text）
            if let text = item.contentText {
                provider.registerObject(text as NSString, visibility: .all)
            }

        case .url:
            // 链接 → 同时提供 NSURL 和纯文本，最大化兼容性
            if let raw = item.contentText {
                if let url = URL(string: raw) {
                    provider.registerObject(url as NSURL, visibility: .all)
                }
                provider.registerObject(raw as NSString, visibility: .all)
            }

        case .file:
            // 文件路径 → 用 NSURL（fileURL），拖到 Finder 会复制文件，拖到文本框会插入路径
            if let path = item.contentText {
                let url = URL(fileURLWithPath: path)
                provider.registerObject(url as NSURL, visibility: .all)
            }

        case .rtf:
            // 富文本 → RTF 数据 + 纯文本兜底
            if let fileName = item.contentFilePath,
               let data = StorageService.shared.loadRTF(fileName: fileName) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.rtf.identifier,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            if let plain = item.contentText {
                provider.registerObject(plain as NSString, visibility: .all)
            }

        case .image:
            // 图片 → PNG 数据
            if let fileName = item.contentFilePath,
               let data = StorageService.shared.loadImage(fileName: fileName) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.png.identifier,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
        }

        return provider
    }
}
