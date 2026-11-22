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

    /// 加载本地 HTML 并放行所在目录：相对引用的 css/js/图片自动加载。
    ///
    /// WebKit 会把 file:// 的子资源（pinshell-i18n.js、design-tokens.css 等）
    /// 长期留在内存/磁盘缓存里，重新 loadFileURL 不会重新校验，导致改过的
    /// 模板辅助文件仍执行旧内容。每次加载前清掉这两类缓存，保证模板热更新可靠。
    func loadLocalHTMLFile(_ url: URL) {
        let store = configuration.websiteDataStore
        let cacheTypes: Set<String> = [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache]
        store.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
    }
}
