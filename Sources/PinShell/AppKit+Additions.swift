import AppKit

extension URL {
    /// 路径存在且不是目录（普通文件）——CLI 校验与加载入口共用同一规则
    var isRegularFile: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}

extension NSColor {
    /// 品牌色：#FD3532（logo 品牌红），使用时按需调 alpha
    static let pinshellBrandRed = NSColor(calibratedRed: 253/255, green: 53/255, blue: 50/255, alpha: 1)
    /// 中性 muted 灰：深浅内容上都可读的描边/标记
    static let pinshellInkMuted = NSColor(calibratedWhite: 122/255, alpha: 1)
}
