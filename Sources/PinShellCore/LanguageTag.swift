import Foundation

/// 轻量 BCP-47 语言标签工具。
///
/// 模板用 `lang="en"` 之类的标签声明翻译；应用用系统/应用语言去匹配。
/// 这里只做模板所需的最小匹配：精确匹配 → 主语言（`zh-Hans` 与 `zh-CN` 视为同一种）。
public enum LanguageTag {
    /// App UI 的语言偏好：应用自身支持的语言优先，再回落到系统语言。
    public static var preferredLanguages: [String] {
        var tags = Bundle.main.preferredLocalizations
        tags.append(contentsOf: Locale.preferredLanguages)
        return unique(tags)
    }

    /// 模板语言偏好：系统语言优先，App 支持的语言作为兜底。
    /// 这样模板可以先于 App UI 支持新语言。
    public static var templatePreferredLanguages: [String] {
        unique(Locale.preferredLanguages + Bundle.main.preferredLocalizations)
    }

    /// 应用当前 UI 语言（用于页面里的 `window.pinshell.language`）。
    public static var appLanguage: String {
        Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
    }

    /// "en_US" → "en-us"，去掉空段。
    public static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
            .joined(separator: "-")
    }

    /// 两个标签是否兼容：主语言一致，且显式脚本不冲突。
    /// `zh-Hans` / `zh-CN` 兼容；`zh-Hans` / `zh-Hant` 不兼容。
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = components(lhs), let b = components(rhs) else { return false }
        return compatible(a, b)
    }

    /// 按 preferred 顺序返回最合适的可用语言标签。
    /// 优先精确匹配，其次脚本/地区匹配；`zh-TW` 会优先匹配 `zh-Hant`。
    public static func bestMatch(available: [String], preferred: [String]) -> String? {
        let candidates = available.compactMap { tag -> (tag: String, components: Components)? in
            guard let parsed = components(tag) else { return nil }
            return (tag, parsed)
        }
        for wanted in preferred {
            guard let target = components(wanted) else { continue }
            var best: (tag: String, score: Int)?
            for candidate in candidates {
                let score = matchScore(candidate.components, target)
                guard score >= 0 else { continue }
                if best == nil || score > best!.score {
                    best = (candidate.tag, score)
                }
            }
            if let best { return best.tag }
        }
        return nil
    }

    private struct Components {
        var language: String
        var script: String?
        var region: String?
        var normalized: String
    }

    private static func components(_ tag: String) -> Components? {
        let normalized = normalize(tag)
        guard !normalized.isEmpty else { return nil }
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return nil }
        var script: String?
        var region: String?
        for part in parts.dropFirst() {
            if script == nil, part.count == 4, part.allSatisfy(\.isLetter) {
                script = part
            } else if region == nil,
                      (part.count == 2 && part.allSatisfy(\.isLetter))
                        || (part.count == 3 && part.allSatisfy(\.isNumber)) {
                region = part
            }
        }
        return Components(language: language, script: script,
                          region: region, normalized: normalized)
    }

    /// 中文地区隐含的脚本：TW/HK/MO → 繁体，CN/SG → 简体。
    private static func impliedScript(_ components: Components) -> String? {
        if components.language == "zh", components.script == nil {
            switch components.region {
            case "tw", "hk", "mo": return "hant"
            case "cn", "sg": return "hans"
            default: return nil
            }
        }
        return components.script
    }

    private static func compatible(_ lhs: Components, _ rhs: Components) -> Bool {
        guard lhs.language == rhs.language else { return false }
        if let a = impliedScript(lhs), let b = impliedScript(rhs), a != b {
            return false
        }
        return true
    }

    private static func matchScore(_ candidate: Components, _ target: Components) -> Int {
        guard compatible(candidate, target) else { return -1 }
        if candidate.normalized == target.normalized { return 1000 }
        var score = 10
        let candidateScript = impliedScript(candidate)
        let targetScript = impliedScript(target)
        if let a = candidateScript, let b = targetScript, a == b {
            score += 20
        }
        if let a = candidate.region, let b = target.region, a == b {
            score += 5
        }
        return score
    }

    /// 应用当前界面语言下的语言名称，例如 en → "English"，zh-Hans → "简体中文"。
    public static func displayName(for tag: String) -> String {
        Locale(identifier: appLanguage).localizedString(forIdentifier: tag) ?? tag
    }

    public static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags where !tag.isEmpty {
            let key = normalize(tag)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(tag)
        }
        return result
    }
}
