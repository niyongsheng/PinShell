import AppKit

// 菜单栏图标生成：SVG logo → 黑色 template PNG（menu bar 自动适配深浅色）
// 用法: swift make_menubar_icon.swift <logo.svg> <out_dir>
// 输出: MenuBarIcon.png (20pt) / MenuBarIcon@2x.png (40pt)，需放入 Resources/ 并打进 bundle

let args = CommandLine.arguments
guard args.count >= 3,
      let svg = NSImage(contentsOfFile: args[1]) else {
    print("usage: make_menubar_icon.swift <logo.svg> <out_dir>")
    exit(1)
}

let outDir = args[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 菜单栏 template 图标：20pt 基准（statusItem.squareLength = 22pt）
let sizes: [(String, Int)] = [
    ("MenuBarIcon", 20), ("MenuBarIcon@2x", 40),
]

// 先渲染 256px master，再两级缩放到目标尺寸：
// 细针尖直接光栅化到 20px 会因 coverage 不足而消失
let masterPx = 256
let masterRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: masterPx, pixelsHigh: masterPx,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
masterRep.size = NSSize(width: masterPx, height: masterPx)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: masterRep)
NSGraphicsContext.current?.imageInterpolation = .high

let masterScale = CGFloat(masterPx) * 0.9 / max(svg.size.width, svg.size.height)
let masterDrawSize = NSSize(width: svg.size.width * masterScale, height: svg.size.height * masterScale)
let masterOrigin = NSPoint(x: (CGFloat(masterPx) - masterDrawSize.width) / 2,
                           y: (CGFloat(masterPx) - masterDrawSize.height) / 2)
svg.draw(in: NSRect(origin: masterOrigin, size: masterDrawSize))
NSGraphicsContext.restoreGraphicsState()

let masterImage = NSImage(size: NSSize(width: masterPx, height: masterPx))
masterImage.addRepresentation(masterRep)

for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    masterImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px))

    NSGraphicsContext.restoreGraphicsState()

    // 像素级去色：保留 alpha、RGB 置 0（template 图标必须是黑 + alpha）
    let data = rep.bitmapData!
    let bpr = rep.bytesPerRow
    for y in 0..<px {
        for x in 0..<px {
            let i = y * bpr + x * 4
            if data[i + 3] > 0 {
                data[i] = 0
                data[i + 1] = 0
                data[i + 2] = 0
            }
        }
    }

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("menubar icon generated: \(outDir)")
