import AppKit

// 应用图标生成：SVG logo → macOS iconset（白底圆角 + 居中 logo）
// 用法: swift make_icon.swift <logo.svg> <out.iconset> [背景色hex, 默认 #FFFFFF]
// 随后: iconutil -c icns <out.iconset> -o <out.icns>

let args = CommandLine.arguments
guard args.count >= 3,
      let svg = NSImage(contentsOfFile: args[1]) else {
    print("usage: make_icon.swift <logo.svg> <out.iconset> [bgHex]")
    exit(1)
}

let bgHex = args.count >= 4 ? args[3] : "FFFFFF"
var bgR: CGFloat = 1, bgG: CGFloat = 1, bgB: CGFloat = 1
if bgHex.count == 6 {
    func comp(_ s: String) -> CGFloat {
        CGFloat(Int(s, radix: 16) ?? 255) / 255
    }
    bgR = comp(String(bgHex.prefix(2)))
    bgG = comp(String(bgHex.dropFirst(2).prefix(2)))
    bgB = comp(String(bgHex.dropFirst(4)))
}
let bgColor = NSColor(calibratedRed: bgR, green: bgG, blue: bgB, alpha: 1)

let outDir = args[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// macOS iconset 规格尺寸
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // 圆角底（squircle 近似 22.5%），四角透明
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: px, height: px),
                          xRadius: CGFloat(px) * 0.225,
                          yRadius: CGFloat(px) * 0.225)
    bgColor.setFill()
    bg.fill()

    // logo 居中，占 62%
    let scale = CGFloat(px) * 0.62 / max(svg.size.width, svg.size.height)
    let drawSize = NSSize(width: svg.size.width * scale, height: svg.size.height * scale)
    let origin = NSPoint(x: (CGFloat(px) - drawSize.width) / 2,
                         y: (CGFloat(px) - drawSize.height) / 2)
    svg.draw(in: NSRect(origin: origin, size: drawSize))

    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset generated: \(outDir)")
