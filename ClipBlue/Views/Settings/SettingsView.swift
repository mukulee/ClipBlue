//
//  SettingsView.swift
//  ClipBlue
//
//  设置窗口主视图（M11）
//
//  规范依据：需求文档.md § 4.11 设置窗口
//
//  尺寸：480 × 560 px
//  含 4 个 Tab：通用 / 内容 / 数据 / 关于
//

import SwiftUI
import AppKit
import os

/// 设置窗口主视图
struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("通用", systemImage: "gearshape") }

            ContentTab(settings: settings)
                .tabItem { Label("内容", systemImage: "doc.text") }

            DataTab()
                .tabItem { Label("数据", systemImage: "externaldrive") }

            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 560)
        .padding()
    }
}

// MARK: - 通用 Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("启动行为") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                Toggle("新内容时菜单栏图标闪烁", isOn: $settings.menuBarIconBlink)
            }

            Section("保留时长") {
                Picker("自动清理超过此时间的记录", selection: $settings.retentionDays) {
                    ForEach(RetentionDays.allCases, id: \.self) { d in
                        Text(d.displayName).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                Text("置顶记录不受保留期限影响")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 内容 Tab

private struct ContentTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("图片") {
                HStack {
                    Text("图片大小上限")
                    Spacer()
                    Stepper(value: $settings.imageSizeLimitMB, in: 1...50) {
                        Text("\(settings.imageSizeLimitMB) MB")
                            .monospacedDigit()
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                }
                Text("超过此大小的图片不会被记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("记录类型") {
                Toggle("记录富文本格式（保留颜色、加粗等）", isOn: $settings.recordRTF)
                Toggle("记录文件路径（从 Finder 复制的文件）", isOn: $settings.recordFile)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 数据 Tab

private struct DataTab: View {

    @State private var normalCount: Int = 0
    @State private var pinnedCount: Int = 0
    @State private var totalBytes: Int64 = 0
    @State private var isLoading: Bool = true

    @State private var showClearAlert: Bool = false
    @State private var includePinned: Bool = false

    var body: some View {
        Form {
            Section("当前数据") {
                LabeledContent("普通记录", value: "\(normalCount) 条")
                LabeledContent("置顶记录", value: "\(pinnedCount) 条")
                LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
            }

            Section("操作") {
                Button("打开存储文件夹") {
                    NSWorkspace.shared.open(StorageService.shared.supportDirectoryURL)
                }

                Button("全部清空…", role: .destructive) {
                    includePinned = false
                    showClearAlert = true
                }
            }

            Section {
                Text("数据存储在 ~/Library/Application Support/ClipBlue/")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refreshStats() }
        .alert("确定要清空所有历史记录吗？", isPresented: $showClearAlert) {
            Toggle("包含置顶记录一起清空", isOn: $includePinned)
            Button("取消", role: .cancel) {}
            Button("确认清空", role: .destructive) {
                Task { await clearAll(includesPinned: includePinned) }
            }
        } message: {
            Text("此操作不可撤销，将彻底删除数据库行 + 硬盘文件")
        }
    }

    private func refreshStats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let all = try await StorageService.shared.fetchAll()
            normalCount = all.filter { !$0.isPinned }.count
            pinnedCount = all.filter { $0.isPinned }.count
            // 占用空间：数据库 + images/ + rtfs/
            // 注意：在 Task.detached nonisolated 上下文中调用 static 方法
            // 必须显式带类型名 DataTab.computeDirectorySize(...)
            totalBytes = await Task.detached(priority: .utility) {
                DataTab.computeDirectorySize(StorageService.shared.supportDirectoryURL)
            }.value
        } catch {
            Log.ui.error("加载统计失败：\(error.localizedDescription)")
        }
    }

    private func clearAll(includesPinned: Bool) async {
        do {
            // 先把所有图片/RTF 关联文件删除
            let all = try await StorageService.shared.fetchAll()
            let toDelete = includesPinned ? all : all.filter { !$0.isPinned }
            _ = try await StorageService.shared.deleteItemsWithFiles(toDelete)

            // 通知 UI 刷新
            NotificationCenter.default.post(name: ClipboardMonitor.didInsertItemNotification, object: nil)
            await refreshStats()
            Log.ui.info("🧹 全部清空完成：删除 \(toDelete.count) 条")
        } catch {
            Log.ui.error("全部清空失败：\(error.localizedDescription)")
        }
    }

    /// 递归计算目录占用字节数
    private nonisolated static func computeDirectorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }
}

// MARK: - 关于 Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 64))
                .foregroundStyle(Palette.primary)

            VStack(spacing: 6) {
                Text("ClipBlue")
                    .font(.system(size: 24, weight: .bold))
                Text("v1.0.0 (Build 1)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Mac 端剪贴板历史记录工具")
                    .font(.system(size: 13))
                Text("作者：李凝宇")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                Label("100% 本地存储", systemImage: "lock.shield.fill")
                    .foregroundStyle(Palette.success)
                Label("无任何网络请求", systemImage: "wifi.slash")
                    .foregroundStyle(Palette.success)
                Label("跳过密码管理器内容", systemImage: "key.slash.fill")
                    .foregroundStyle(Palette.success)
            }
            .font(.system(size: 12))

            Spacer()

            Text("© 2026 ClipBlue · 隐私优先")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
