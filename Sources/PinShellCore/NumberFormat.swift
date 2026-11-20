import Foundation

/// 数值展示：整数不带小数点，其余按指定小数位格式化。
public enum NumberFormat {
    public static func text(_ value: Double, fractionDigits: Int = 1) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.\(fractionDigits)f", value)
    }
}
