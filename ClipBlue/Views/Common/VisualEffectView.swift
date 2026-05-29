//
//  VisualEffectView.swift
//  ClipBlue
//
//  毛玻璃效果（NSVisualEffectView → SwiftUI 桥接）
//
//  对应 Milestone：M4 主面板 UI
//  规范依据：需求文档.md § 6.5
//

import SwiftUI
import AppKit

/// 毛玻璃背景视图
///
/// 将 AppKit 的 `NSVisualEffectView` 桥接到 SwiftUI，
/// 用于主面板背景营造"毛玻璃透明"质感。
///
/// 用法：
/// ```swift
/// ZStack {
///     VisualEffectBackground(material: .popover)
///     // 你的内容
/// }
/// ```
struct VisualEffectBackground: NSViewRepresentable {

    /// 材质类型（实验后选最贴合 macOS 体验的）
    let material: NSVisualEffectView.Material

    /// 混合模式：`.behindWindow` 透出后方桌面/窗口；`.withinWindow` 仅模糊本窗口
    let blendingMode: NSVisualEffectView.BlendingMode

    /// 状态：`.active` 始终激活；`.followsWindowActiveState` 跟随窗口聚焦
    let state: NSVisualEffectView.State

    init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
