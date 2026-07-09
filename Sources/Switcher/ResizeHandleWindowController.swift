import AppKit

@MainActor
final class ResizeHandleWindowController {
    private let handleWidth: CGFloat = 6
    private var window: NSWindow?
    private var handleView: HandleView?

    func show(
        for pinnedFrame: CGRect,
        edge: SidebarEdge,
        onDeltaX: @MainActor @escaping (CGFloat) -> Void,
        onDragEnd: @MainActor @escaping () -> Void
    ) {
        let window = self.window ?? makeWindow()
        self.window = window

        let handleView = self.handleView ?? HandleView()
        self.handleView = handleView

        handleView.onDeltaX = onDeltaX
        handleView.onDragEnd = onDragEnd
        window.contentView = handleView

        updateFrame(for: pinnedFrame, edge: edge)
        window.orderFrontRegardless()
    }

    func updateFrame(for pinnedFrame: CGRect, edge: SidebarEdge) {
        guard let window else {
            return
        }

        let x: CGFloat
        switch edge {
        case .left:
            x = pinnedFrame.maxX - (handleWidth / 2)
        case .right:
            x = pinnedFrame.minX - (handleWidth / 2)
        }

        let handleFrame = CGRect(
            x: x,
            y: pinnedFrame.minY,
            width: handleWidth,
            height: pinnedFrame.height
        )

        window.setFrame(handleFrame, display: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = HandleWindow(
            contentRect: CGRect(x: 0, y: 0, width: handleWidth, height: 400),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.28)
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.stationary]
        return window
    }
}

private final class HandleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class HandleView: NSView {
    var onDeltaX: (@MainActor (CGFloat) -> Void)?
    var onDragEnd: (@MainActor () -> Void)?

    private var previousLocation: NSPoint?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        previousLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if let previousLocation {
            onDeltaX?(current.x - previousLocation.x)
        }
        previousLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        previousLocation = nil
        onDragEnd?()
    }
}
