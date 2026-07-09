import AppKit
import SwiftUI

@MainActor
final class SidebarEdgeToggleWindowController {
    private let controlSize = CGSize(width: 28, height: 92)
    private var window: NSWindow?
    private var hostingView: NSHostingView<SidebarEdgeToggleView>?

    func show(
        sidebarRegion: CGRect,
        edge: SidebarEdge,
        collapsed: Bool,
        autoModeEnabled: Bool,
        onToggle: @escaping () -> Void,
        onToggleAutoMode: @escaping () -> Void
    ) {
        let window = self.window ?? makeWindow()
        self.window = window

        if hostingView == nil {
            let view = NSHostingView(
                rootView: SidebarEdgeToggleView(
                    edge: edge,
                    collapsed: collapsed,
                    autoModeEnabled: autoModeEnabled,
                    onToggle: onToggle,
                    onToggleAutoMode: onToggleAutoMode
                )
            )
            self.hostingView = view
            window.contentView = view
        } else {
            hostingView?.rootView = SidebarEdgeToggleView(
                edge: edge,
                collapsed: collapsed,
                autoModeEnabled: autoModeEnabled,
                onToggle: onToggle,
                onToggleAutoMode: onToggleAutoMode
            )
        }

        let frame = frameForControl(sidebarRegion: sidebarRegion, edge: edge)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = EdgeToggleWindow(
            contentRect: CGRect(origin: .zero, size: controlSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = false
        return window
    }

    private func frameForControl(sidebarRegion: CGRect, edge: SidebarEdge) -> CGRect {
        let boundaryX = edge == .left ? sidebarRegion.maxX : sidebarRegion.minX
        let x = boundaryX - (controlSize.width / 2)
        let y = sidebarRegion.midY - (controlSize.height / 2)

        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: y.rounded(.toNearestOrAwayFromZero),
            width: controlSize.width,
            height: controlSize.height
        )
    }
}

private final class EdgeToggleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SidebarEdgeToggleView: View {
    let edge: SidebarEdge
    let collapsed: Bool
    let autoModeEnabled: Bool
    let onToggle: () -> Void
    let onToggleAutoMode: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)

                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)

                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Pull out sidebar" : "Push in sidebar")
        .contextMenu {
            Button(autoModeEnabled ? "Disable Automatic Edge Hover" : "Enable Automatic Edge Hover") {
                onToggleAutoMode()
            }
        }
    }

    private var iconName: String {
        switch (edge, collapsed) {
        case (.left, true):
            return "chevron.right"
        case (.left, false):
            return "chevron.left"
        case (.right, true):
            return "chevron.left"
        case (.right, false):
            return "chevron.right"
        }
    }
}
