import AppKit
import Foundation

private let repoRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() } // script → scripts → website → repo
    return url
}()

private let outputDirectory = repoRoot
    .appendingPathComponent("website/src/assets", isDirectory: true)

private let parchment = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
private let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
private let muted = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1)
private let actionBlue = NSColor(srgbRed: 0, green: 0.4, blue: 0.8, alpha: 1)

private func loadIcon() -> NSImage? {
    let icns = repoRoot.appendingPathComponent("Resources/PinShell.icns")
    if let image = NSImage(contentsOf: icns) { return image }
    let svg = repoRoot.appendingPathComponent("Resources/logo.svg")
    return NSImage(contentsOf: svg)
}

private func bitmap(width: Int, height: Int, draw: (NSSize) -> Void) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "PinShellSocial", code: 1)
    }
    rep.size = NSSize(width: width, height: height)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "PinShellSocial", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw(NSSize(width: width, height: height))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PinShellSocial", code: 3)
    }
    return data
}

private func drawRoundedIcon(size: CGFloat, iconInset: CGFloat) -> (NSSize) -> Void {
    { canvas in
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.225
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        if let icon = loadIcon() {
            let inset = iconInset
            let iconRect = rect.insetBy(dx: inset, dy: inset)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        _ = canvas
    }
}

private func drawOG(language: String) -> (NSSize) -> Void {
    { size in
        parchment.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Fine paper grid
        NSColor(calibratedWhite: 0.1, alpha: 0.035).setStroke()
        let grid = NSBezierPath()
        var x: CGFloat = 0
        while x <= size.width {
            grid.move(to: NSPoint(x: x, y: 0))
            grid.line(to: NSPoint(x: x, y: size.height))
            x += 40
        }
        var y: CGFloat = 0
        while y <= size.height {
            grid.move(to: NSPoint(x: 0, y: y))
            grid.line(to: NSPoint(x: size.width, y: y))
            y += 40
        }
        grid.lineWidth = 1
        grid.stroke()

        // Icon
        if let icon = loadIcon() {
            icon.draw(in: NSRect(x: 80, y: 456, width: 104, height: 104),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }

        let isZH = language == "zh"
        let wordmark = NSAttributedString(
            string: "PinShell",
            attributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: ink,
                .kern: -0.5,
            ])
        wordmark.draw(at: NSPoint(x: 208, y: 506))

        let kicker = NSAttributedString(
            string: isZH ? "为 AI 打造的实时桌面窗口" : "A REAL-TIME DESKTOP WINDOW FOR AI",
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: actionBlue,
                .kern: 1.6,
            ])
        kicker.draw(at: NSPoint(x: 80, y: 382))

        let titleText = isZH
            ? "把 Agent 的界面\n放到桌面上。"
            : "Give the agent\na window on the desktop."
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 0
        let title = NSAttributedString(
            string: titleText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 82, weight: .semibold),
                .foregroundColor: ink,
                .kern: -3.4,
                .paragraphStyle: paragraph,
            ])
        title.draw(in: NSRect(x: 80, y: 148, width: 1040, height: 232))

        let subtitleText = isZH
            ? "用 HTML 即时绘制、播放与交互。模板在线安装，独立更新。"
            : "Live HTML for drawing, playback, and interaction. Templates install and update independently."
        let subtitle = NSAttributedString(
            string: subtitleText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: muted,
                .kern: -0.4,
            ])
        subtitle.draw(at: NSPoint(x: 82, y: 92))

        let footer = NSAttributedString(
            string: "macOS 13+  ·  Apple Silicon + Intel  ·  Apache 2.0",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: muted,
            ])
        footer.draw(at: NSPoint(x: 82, y: 48))

        let red = NSColor(srgbRed: 0.992, green: 0.208, blue: 0.196, alpha: 1)
        red.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1090, y: 500, width: 12, height: 12)).fill()
    }
}

do {
    try FileManager.default.createDirectory(
        at: outputDirectory, withIntermediateDirectories: true)

    let assets: [(String, Int, Int, (NSSize) -> Void)] = [
        ("favicon-32.png", 32, 32, drawRoundedIcon(size: 32, iconInset: 6)),
        ("apple-touch-icon.png", 180, 180, drawRoundedIcon(size: 180, iconInset: 33)),
        ("icon-512.png", 512, 512, drawRoundedIcon(size: 512, iconInset: 95)),
        ("og-zh.png", 1200, 630, drawOG(language: "zh")),
        ("og-en.png", 1200, 630, drawOG(language: "en")),
    ]
    for (name, width, height, draw) in assets {
        let data = try bitmap(width: width, height: height, draw: draw)
        try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
        print("wrote \(name)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
