import Foundation

/// 跨层共用的原始值解析。
public enum ValueParsing {
    /// 兼容 true/false、1/0、yes/no、on/off（大小写与首尾空白不敏感）。
    public static func bool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return nil
        }
    }
}
