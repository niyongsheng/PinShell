import WebKit

extension WKWebView {
    /// 透明三件套：必须 init 后、任何 load 之前设置
    /// （WebKit 对 load 之后再切 drawsBackground 不可靠 —— known bug）
    func makeTransparent() {
        setValue(false, forKey: "drawsBackground")   // macOS 上为私有属性，走 KVC
        underPageBackgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
    }

    /// 加载本地 HTML 并放行所在目录：相对引用的 css/js/图片自动加载
    func loadLocalHTMLFile(_ url: URL) {
        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
