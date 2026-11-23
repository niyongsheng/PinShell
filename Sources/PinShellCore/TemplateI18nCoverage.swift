import Foundation

public enum TemplateI18nCoverageError: Error, Equatable, CustomStringConvertible {
    case incomplete([String])

    public var description: String {
        switch self {
        case .incomplete(let problems):
            return problems.joined(separator: "; ")
        }
    }
}

/// 校验模板 i18n block 的完整性；测试与网站构建器共用。
public enum TemplateI18nCoverage {
    public static func validate(html: String) throws {
        let problems = problems(in: html)
        if !problems.isEmpty {
            throw TemplateI18nCoverageError.incomplete(problems)
        }
    }

    public static func problems(in html: String) -> [String] {
        guard let block = TemplateI18n.extractBlock(from: html) else {
            return ["missing pinshell:i18n block"]
        }
        guard let json = block.json else {
            return ["invalid pinshell:i18n JSON"]
        }
        guard let defaultLanguage = json["default"] as? String else {
            return ["missing default language"]
        }
        guard let languages = json["languages"] as? [String: Any],
              !languages.isEmpty else {
            return ["missing languages"]
        }

        var problems: [String] = []
        if !languages.keys.contains(where: { LanguageTag.matches($0, defaultLanguage) }) {
            problems.append("default language \(defaultLanguage) is not declared")
        }
        if let fallback = json["fallback"] as? String,
           !languages.keys.contains(where: { LanguageTag.matches($0, fallback) }) {
            problems.append("fallback language \(fallback) is not declared")
        }

        for (tag, rawEntry) in languages {
            guard let entry = rawEntry as? [String: Any],
                  let meta = entry["meta"] as? [String: Any] else {
                problems.append("\(tag): missing meta")
                continue
            }
            if (meta["name"] as? String ?? "").isEmpty {
                problems.append("\(tag): empty name")
            }
            if (meta["description"] as? String ?? "").isEmpty {
                problems.append("\(tag): empty description")
            }
        }

        let requiredKeys = referencedKeys(in: html)
        for (tag, rawEntry) in languages
            where !LanguageTag.matches(tag, defaultLanguage) {
            let entry = rawEntry as? [String: Any] ?? [:]
            let ui = entry["ui"] as? [String: Any] ?? [:]
            let missing = requiredKeys.subtracting(ui.keys)
            if !missing.isEmpty {
                problems.append("\(tag): missing keys \(missing.sorted())")
            }
        }

        return problems.sorted()
    }

    public static func referencedKeys(in html: String) -> Set<String> {
        var keys = Set<String>()
        let patterns = [
            #"<[^>]+\bdata-i18n\s*=\s*"([^"]+)""#,
            #"<[^>]+\bdata-i18n-[a-z-]+\s*=\s*"([^"]+)""#,
            #"PS\.t\(\s*['"]([^'"]+)['"]"#,
            #"PS\.list\(\s*['"]([^'"]+)['"]"#,
            #"PS\.get\(\s*['"]([^'"]+)['"]"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                keys.insert(ns.substring(with: match.range(at: 1)))
            }
        }
        return keys
    }
}
