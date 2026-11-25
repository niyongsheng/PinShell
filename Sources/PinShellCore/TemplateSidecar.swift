import Foundation

/// 每个模板包内共享的运行时资源：App 播种、官网构建与校验共用同一清单。
public enum TemplateSidecar {
    public static let names = ["design-tokens.css", "pinshell-i18n.js"]
}
