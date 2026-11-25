import Foundation
import PinShellCore

struct SiteValidationSummary {
    let templateCount: Int
    let pageCount: Int
    let linkCount: Int
}

enum SiteValidator {
    static func validate(output: URL) throws -> SiteValidationSummary {
        let fm = FileManager.default
        let outputURL = output.standardizedFileURL

        let libraryURL = output.appendingPathComponent("library.json")
        guard let libraryData = try? Data(contentsOf: libraryURL) else {
            throw BuilderError(message: "missing library.json")
        }
        let index: TemplateLibraryIndex
        do {
            index = try JSONDecoder().decode(TemplateLibraryIndex.self, from: libraryData)
            try TemplateLibraryValidation.validate(index, allowAbsolutePayloadURL: true)
        } catch {
            throw BuilderError(message: "invalid library.json: \(error)")
        }

        for template in index.templates {
            let payload = output.appendingPathComponent(template.payload.url)
            guard let data = try? Data(contentsOf: payload) else {
                throw BuilderError(message: "missing payload \(template.payload.url)")
            }
            do {
                try TemplatePayloadVerifier.verify(
                    data: data,
                    expectedBytes: template.payload.bytes,
                    expectedSHA256: template.payload.sha256)
            } catch {
                throw BuilderError(message: "\(template.id): \(error)")
            }
            for page in (template.pages ?? [:]).values {
                let pageURL = output.appendingPathComponent(page)
                let candidate = pageURL.hasDirectoryPath
                    ? pageURL.appendingPathComponent("index.html")
                    : pageURL
                guard fm.fileExists(atPath: candidate.path) else {
                    throw BuilderError(message: "\(template.id): missing page \(page)")
                }
            }
            if let bundleURL = template.payload.bundleURL {
                guard fm.fileExists(atPath: output.appendingPathComponent(bundleURL).path) else {
                    throw BuilderError(message: "\(template.id): missing bundle \(bundleURL)")
                }
            }
        }

        for required in ["sitemap.xml", "robots.txt", ".nojekyll", "CNAME",
                         "assets/og-zh.png", "assets/og-en.png",
                         "assets/favicon.svg", "assets/apple-touch-icon.png"] {
            guard fm.fileExists(atPath: output.appendingPathComponent(required).path) else {
                throw BuilderError(message: "missing generated asset \(required)")
            }
        }

        guard let enumerator = fm.enumerator(at: output,
                                             includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw BuilderError(message: "cannot enumerate \(output.path)")
        }

        var pageCount = 0
        var linkCount = 0
        let linkRegex = try NSRegularExpression(
            pattern: #"(?:href|src|data-src)\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive])

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name == "index.html" || name == "404.html" else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            pageCount += 1
            // 404 会被任意深层路径复用，因此其站内链接必须从站点根开始解析。
            let allowRootAbsolute = name == "404.html"
            let html = try String(contentsOf: url, encoding: .utf8)
            if html.contains("{{") {
                throw BuilderError(message: "unreplaced token in \(url.path)")
            }
            let ns = html as NSString
            for match in linkRegex.matches(in: html,
                                           range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let raw = ns.substring(with: match.range(at: 1))
                guard shouldCheckLink(raw) else { continue }
                linkCount += 1
                let pathOnly = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
                let clean = pathOnly.split(separator: "?", maxSplits: 1).first.map(String.init) ?? pathOnly
                guard !clean.isEmpty else { continue }
                let target: URL
                if clean.hasPrefix("/") {
                    guard allowRootAbsolute else {
                        throw BuilderError(message: "root-absolute link \(raw) in \(url.path)")
                    }
                    target = outputURL
                        .appendingPathComponent(String(clean.dropFirst()))
                        .standardizedFileURL
                } else {
                    guard !allowRootAbsolute else {
                        throw BuilderError(
                            message: "root-anchored page requires root-absolute links: \(raw) in \(url.path)")
                    }
                    target = url.deletingLastPathComponent()
                        .appendingPathComponent(clean)
                        .standardizedFileURL
                }
                guard target.path.hasPrefix(outputURL.path) else {
                    throw BuilderError(message: "link escapes site root: \(raw) in \(url.path)")
                }
                let candidate: URL
                if clean.hasSuffix("/") || fm.fileExists(atPath: target.path, isDirectory: nil)
                    && (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    candidate = target.appendingPathComponent("index.html")
                } else {
                    candidate = target
                }
                // 不带斜杠的目录链接：candidate 本身不存在，但 candidate/index.html 存在。
                if !fm.fileExists(atPath: candidate.path),
                   !fm.fileExists(atPath: candidate.appendingPathComponent("index.html").path) {
                    throw BuilderError(message: "broken internal link \(raw) in \(url.path)")
                }
            }
        }

        return SiteValidationSummary(
            templateCount: index.templates.count,
            pageCount: pageCount,
            linkCount: linkCount)
    }

    private static func shouldCheckLink(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.hasPrefix("#") { return false }
        for scheme in ["http://", "https://", "mailto:", "tel:", "data:",
                       "javascript:", "\(PinShellDeepLink.scheme):", "//"]
        where lower.hasPrefix(scheme) {
            return false
        }
        return true
    }
}
