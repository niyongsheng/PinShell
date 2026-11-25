import Foundation

/// 数值展示：整数不带小数点，其余按指定小数位格式化。
public enum NumberFormat {
    public static func text(_ value: Double, fractionDigits: Int = 1) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.\(fractionDigits)f", value)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// 文件大小：App 下载进度与官网模板库共用同一格式与单位。
    public static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }
}
