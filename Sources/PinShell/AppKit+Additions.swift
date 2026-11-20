import AppKit

extension URL {
    /// 路径存在且不是目录（普通文件）——CLI 校验与加载入口共用同一规则
    var isRegularFile: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}

extension NSAlert {
    /// accessory 应用弹模态框前必须先激活，否则窗口不出现（设计风险 R3）。
    @discardableResult
    func runAppModal() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}
