//
//  FullContentWindow.swift
//  ClipBlue
//
//  「显示完整内容」独立窗口（M5 右键菜单触发）
//
//  规范依据：需求文档.md § 4.4.5 右键菜单 → 显示完整内容
//

import AppKit
import SwiftUI

/// 弹出独立窗口完整展示一条剪贴板内容
@MainActor
enum FullContentWindow {

    /// 同时只允许打开一个完整内容窗口（再次调用替换）
    private static var currentController: NSWindowController?

    /// 打开窗口
    static func show(for item: ClipboardItem) {
        // 关闭之前的
        currentController?.close()

        let rootView = FullContentView(item: item)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "查看完整内容"
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("ClipBlue.FullContentWindow")

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        // 短暂激活到前台
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        currentController = controller
    }
}

// MARK: - 内容视图

private struct FullContentView: View {

    let item: ClipboardItem

    @State private var nsImageCache: NSImage?
    @State private var attributedRTF: NSAttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部：类型 + 来源 + 时间
            HStack(spacing: 8) {
                Text(typeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Palette.primaryHover)
                    )

                if let app = item.sourceAppName {
                    Text(app)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer()

                Text(TimeFormatter.relative(item.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }

            Divider()

            // 主体：按类型渲染
            mainContent
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 360)
        .task { await loadHeavyContent() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch item.type {
        case .text, .url, .file:
            ScrollView {
                Text(item.contentText ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .rtf:
            ScrollView {
                if let attr = attributedRTF {
                    RTFContentView(attributed: attr)
                } else {
                    Text(item.contentText ?? "(加载富文本中…)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                }
            }

        case .image:
            ScrollView([.horizontal, .vertical]) {
                if let nsImage = nsImageCache {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: 300, minHeight: 200)
                } else {
                    Text("(加载图片中…)")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var typeLabel: String {
        switch item.type {
        case .text:  return "TEXT"
        case .url:   return "URL"
        case .rtf:   return "RTF"
        case .image: return "IMAGE"
        case .file:  return "FILE"
        }
    }

    // MARK: - Heavy Loading

    private func loadHeavyContent() async {
        // 关键：Task.detached 闭包只读 `Data`（Sendable），
        // 跨 actor 边界后再在主线程构造 NSImage / NSAttributedString
        // （这两个类型在 macOS Sequoia 中显式标记为非 Sendable）
        if item.type == .image, let fileName = item.contentFilePath {
            let data: Data? = await Task.detached(priority: .userInitiated) {
                StorageService.shared.loadImage(fileName: fileName)
            }.value
            if let data {
                self.nsImageCache = NSImage(data: data)
            }
        } else if item.type == .rtf, let fileName = item.contentFilePath {
            let data: Data? = await Task.detached(priority: .userInitiated) {
                StorageService.shared.loadRTF(fileName: fileName)
            }.value
            if let data {
                self.attributedRTF = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            }
        }
    }
}

// MARK: - RTF 渲染（NSTextView 桥接，支持显示 RTF 样式）

private struct RTFContentView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textStorage?.setAttributedString(attributed)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(attributed)
        }
    }
}
