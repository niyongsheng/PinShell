import AppKit

// Template 蒙版图标生成：SVG → 20pt / 40pt PNG（深色与选中态由 AppKit 染色）。
// 用法: swift make_template_icon.swift <logo.svg> <out_dir> <base_name> <scale> [--flatten]
// 输出: <base_name>.png (20pt) / <base_name>@2x.png (40pt)，放入 Resources/ 并打进 bundle。

let args = CommandLine.arguments
guard args.count >= 5,
      let svg = NSImage(contentsOfFile: args[1]),
      let scale = Double(args[4]), scale > 0 else {
    print("usage: make_template_icon.swift <logo.svg> <out_dir> <base_name> <scale> [--flatten]")
    exit(1)
}

let outDir = args[2]
let baseName = args[3]
let flatten = args.dropFirst(5).contains("--flatten")
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 先渲染 256px master，再高质量缩放到目标尺寸：细笔画直接光栅化到 20px 会断裂。
let masterPx = 256
let masterRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: masterPx, pixelsHigh: masterPx,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
masterRep.size = NSSize(width: masterPx, height: masterPx)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: masterRep)
NSGraphicsContext.current?.imageInterpolation = .high

let masterScale = CGFloat(masterPx) * CGFloat(scale) / max(svg.size.width, svg.size.height)
let masterDrawSize = NSSize(width: svg.size.width * masterScale, height: svg.size.height * masterScale)
let masterOrigin = NSPoint(x: (CGFloat(masterPx) - masterDrawSize.width) / 2,
                           y: (CGFloat(masterPx) - masterDrawSize.height) / 2)
svg.draw(in: NSRect(origin: masterOrigin, size: masterDrawSize))
NSGraphicsContext.restoreGraphicsState()

let masterImage = NSImage(size: NSSize(width: masterPx, height: masterPx))
masterImage.addRepresentation(masterRep)

let sizes: [(String, Int)] = [(baseName, 20), ("\(baseName)@2x", 40)]
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

    if flatten {
        // 像素级去色：保留 alpha、RGB 置 0（template 图标必须是黑 + alpha）。
        let data = rep.bitmapData!
        let bytesPerRow = rep.bytesPerRow
        for y in 0..<px {
            for x in 0..<px {
                let index = y * bytesPerRow + x * 4
                if data[index + 3] > 0 {
                    data[index] = 0
                    data[index + 1] = 0
                    data[index + 2] = 0
                }
            }
        }
    }

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("error: failed to encode \(name).png")
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    do {
        try png.write(to: url)
        print("wrote \(url.path)")
    } catch {
        print("error: could not write \(name).png: \(error.localizedDescription)")
        exit(1)
    }
}
