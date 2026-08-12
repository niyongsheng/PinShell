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
}
