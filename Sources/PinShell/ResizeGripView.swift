import AppKit

/// 右下角缩放手柄：仅编辑模式可见（穿透开启时由控制器隐藏）。
/// 平时完全不可见（不打扰画面），鼠标悬停时浮现斜线标记；
/// 拖动调整窗口大小，最小 80×40。
final class ResizeGripView: NSView {
    private static let minWidth: CGFloat = 80
    private static let minHeight: CGFloat = 40

    private var startFrame: NSRect = .zero
    private var startPoint: NSPoint = .zero
    private var hovered = false   // 悬停时显示标记

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let p = event.locationInWindow
        let dx = p.x - startPoint.x               // 右拖变宽
        let dy = p.y - startPoint.y               // AppKit y 向上：上拖变高
        let w = max(Self.minWidth, startFrame.width + dx)
        let h = max(Self.minHeight, startFrame.height + dy)
        // display: false —— 连续拖动由系统合并重绘，避免每帧强制全窗口刷新
        window.setFrame(NSRect(origin: startFrame.origin,
                               size: NSSize(width: w, height: h)),
                        display: false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovered else { return }
        // 经典角落小三角：两直角边贴底边/右边，ink-muted-48 灰系在深浅内容上都可读
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: bounds.maxX - 9, y: bounds.minY + 1))
        tri.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + 1))
        tri.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + 9))
        tri.close()
        NSColor.pinshellInkMuted.withAlphaComponent(0.35).setFill()
        tri.fill()
        NSColor.pinshellInkMuted.withAlphaComponent(0.9).setStroke()
        tri.lineWidth = 1
        tri.stroke()
    }

    /// 系统已无对角缩放光标，用 SF Symbol 渲染（双头对角箭头，热点在中心）
    private static let resizeCursor: NSCursor = {
        let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                             accessibilityDescription: "resize")
        let image = symbol ?? NSImage(size: NSSize(width: 16, height: 16))
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2,
                                                       y: image.size.height / 2))
    }()
}

private extension NSColor {
    /// 缩放手柄标记用灰：深浅内容上都可读。
    static let pinshellInkMuted = NSColor(calibratedWhite: 122 / 255, alpha: 1)
}
