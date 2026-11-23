import Foundation
import PinShellCore

struct SiteStrings {
    let backToGallery: String
    let downloadHTML: String
    let installApp: String
    let installHint: String
    let highlights: String
    let changelog: String
    let metadata: String
    let version: String
    let category: String
    let author: String
    let size: String
    let fileSize: String
    let languages: String
    let interactiveHint: String
    let noChangelog: String
    /// 计数文案模板，{n} 由 JS 在筛选时替换；Swift 侧用 templateCount 渲染初始值。
    let countOne: String
    let countOther: String

    func templateCount(_ count: Int) -> String {
        (count == 1 ? countOne : countOther)
            .replacingOccurrences(of: "{n}", with: "\(count)")
    }

    static func make(language: String) -> SiteStrings {
        if LanguageTag.matches(language, "en") {
            return SiteStrings(
                backToGallery: "All templates",
                downloadHTML: "Download bundle",
                installApp: "Install PinShell",
                installHint: "Open PinShell, press ⌘K, then choose Online Template Library to install and receive updates.",
                highlights: "Highlights",
                changelog: "Release notes",
                metadata: "Details",
                version: "Version",
                category: "Category",
                author: "Author",
                size: "Size",
                fileSize: "File size",
                languages: "Languages",
                interactiveHint: "Click and type inside the preview — the template responds live.",
                noChangelog: "No release notes yet.",
                countOne: "{n} template",
                countOther: "{n} templates")
        }
        return SiteStrings(
            backToGallery: "全部模板",
            downloadHTML: "下载模板包",
            installApp: "安装 PinShell",
            installHint: "打开 PinShell，按 ⌘K，在“在线模板库”中一键安装并接收更新。",
            highlights: "亮点",
            changelog: "更新日志",
            metadata: "详情",
            version: "版本",
            category: "分类",
            author: "作者",
            size: "尺寸",
            fileSize: "文件大小",
            languages: "语言",
            interactiveHint: "可直接在预览中点击、输入，模板会实时响应。",
            noChangelog: "暂无更新日志。",
            countOne: "{n} 个模板",
            countOther: "{n} 个模板")
    }
}

enum PageRenderer {
    static func render(paths: RepoPaths,
                       site: SiteConfig,
                       catalog: BuiltCatalog,
                       appVersion: String,
                       siteURL rawSiteURL: String,
                       output: URL) throws {
        let siteURL = rawSiteURL.hasSuffix("/")
            ? String(rawSiteURL.dropLast())
            : rawSiteURL
        let fm = FileManager.default
        let assets = output.appendingPathComponent("assets", isDirectory: true)
        let partials = paths.source.appendingPathComponent("partials", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)

        let cname = paths.root.appendingPathComponent("website/CNAME")
        if fm.fileExists(atPath: cname.path) {
            let destination = output.appendingPathComponent("CNAME")
            if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
            try fm.copyItem(at: cname, to: destination)
        }

        try copyDirectory(paths.source.appendingPathComponent("assets"), to: assets)
        let logo = assets.appendingPathComponent("logo.svg")
        if fm.fileExists(atPath: logo.path) { try? fm.removeItem(at: logo) }
        try fm.copyItem(at: paths.logo, to: logo)
        for name in ["design-tokens.css", "pinshell-i18n.js"] {
            let destination = assets.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
            try fm.copyItem(at: paths.sidecarURL(named: name), to: destination)
        }

        let languages = site.languages
        guard let zh = languages.first(where: { LanguageTag.matches($0.id, "zh-Hans") }),
              let en = languages.first(where: { LanguageTag.matches($0.id, "en") }) else {
            throw BuilderError(message: "site.json must define zh-Hans and en languages")
        }

        let homePaths = [zh.id: "index.html", en.id: "en/index.html"]
        let galleryPaths = [zh.id: "templates/index.html", en.id: "en/templates/index.html"]

        for language in languages {
            let isEN = LanguageTag.matches(language.id, "en")
            let strings = SiteStrings.make(language: language.id)
            let homeJSONLD = jsonLDTag(softwareApplicationJSON(
                site: site, appVersion: appVersion,
                canonical: absolute(siteURL, "")))
            let galleryJSONLD = jsonLDTag(itemListJSON(
                catalog: catalog, site: site,
                language: language.id, siteURL: siteURL))
            let homePath = homePaths[language.id] ?? (isEN ? "en/index.html" : "index.html")
            let galleryPath = galleryPaths[language.id]
                ?? (isEN ? "en/templates/index.html" : "templates/index.html")

            let homeTokens = commonTokens(
                language: language, pagePath: homePath, site: site, siteURL: siteURL,
                title: isEN ? "PinShell — A real-time desktop window built for AI"
                            : "PinShell — 为 AI 打造的实时桌面窗口",
                description: site.tagline[language.id] ?? "",
                langSwitchPath: otherHomePath(language.id, homePaths: homePaths, languages: languages),
                jsonLD: homeJSONLD)
            var homeExtra = homeTokens
            homeExtra["HERO_PANELS"] = (site.hero ?? site.featured)
                .prefix(3)
                .compactMap { id in catalog.templates.first { $0.entry.id == id } }
                .enumerated()
                .map { index, template in
                    heroPanel(template, index: index, language: language.id,
                              root: rootPrefix(for: homePath))
                }
                .joined()
            homeExtra["FEATURED_CARDS"] = catalog.templates
                .filter { site.featured.contains($0.entry.id) }
                .prefix(6)
                .map { template in
                    card(template, language: language.id,
                         detailHref: rootPrefix(for: homePath) + "templates/\(template.entry.id)/",
                         previewHref: rootPrefix(for: homePath)
                            + "templates/\(template.entry.id)/\(template.entry.version)/\(template.entry.file)?lang=\(language.id)",
                         category: categoryName(template.entry.category, site: site, language: language.id))
                }
                .joined()
            try renderPage(
                source: paths.source.appendingPathComponent(
                    isEN ? "pages/en/index.html" : "pages/zh/index.html"),
                destination: output.appendingPathComponent(homePath),
                partials: partials,
                tokens: homeExtra)

            let galleryTokens = commonTokens(
                language: language, pagePath: galleryPath, site: site, siteURL: siteURL,
                title: isEN ? "Template Library — PinShell" : "模板库 — PinShell",
                description: isEN
                    ? "Ten live HTML templates for your PinShell overlay: productivity, monitoring, focus, play, and companionship."
                    : "十款可运行的 HTML 模板：效率、监控、专注、娱乐与陪伴，让 PinShell 的窗口立刻有用。",
                langSwitchPath: otherGalleryPath(language.id, galleryPaths: galleryPaths, languages: languages),
                jsonLD: galleryJSONLD)
            var galleryExtra = galleryTokens
            galleryExtra["CATEGORY_FILTERS"] = categoryFilters(site: site, language: language.id)
            galleryExtra["TEMPLATE_CARDS"] = catalog.templates.map { template in
                card(template, language: language.id,
                     detailHref: "\(template.entry.id)/",
                     previewHref: rootPrefix(for: galleryPath)
                        + "templates/\(template.entry.id)/\(template.entry.version)/\(template.entry.file)?lang=\(language.id)",
                     category: categoryName(template.entry.category, site: site, language: language.id))
            }.joined()
            galleryExtra["TEMPLATE_COUNT"] = strings.templateCount(catalog.templates.count)
            galleryExtra["COUNT_ONE"] = strings.countOne
            galleryExtra["COUNT_OTHER"] = strings.countOther
            try renderPage(
                source: paths.source.appendingPathComponent(
                    isEN ? "pages/en/templates/index.html" : "pages/zh/templates/index.html"),
                destination: output.appendingPathComponent(galleryPath),
                partials: partials,
                tokens: galleryExtra)

            for template in catalog.templates {
                let detailPath = isEN
                    ? "en/templates/\(template.entry.id)/index.html"
                    : "templates/\(template.entry.id)/index.html"
                let otherDetailPath = isEN
                    ? "templates/\(template.entry.id)/index.html"
                    : "en/templates/\(template.entry.id)/index.html"
                let detailTokens = commonTokens(
                    language: language, pagePath: detailPath, site: site, siteURL: siteURL,
                    title: "\(template.entry.localizedName(preferredLanguages: [language.id])) — PinShell",
                    description: template.entry.localizedDescription(preferredLanguages: [language.id]),
                    langSwitchPath: relativeHref(from: detailPath, to: otherDetailPath),
                    jsonLD: jsonLDTag(templateJSON(template, language: language.id,
                                                   siteURL: siteURL, site: site)))
                var detailExtra = detailTokens
                let payloadPath = "templates/\(template.entry.id)/\(template.entry.version)/\(template.entry.file)"
                let bundlePath = template.entry.payload.bundleURL ?? payloadPath
                detailExtra["TEMPLATE_DETAIL"] = detailBody(
                    template, language: language.id, site: site, strings: strings,
                    payloadHref: relativeHref(from: detailPath, to: payloadPath),
                    bundleHref: relativeHref(from: detailPath, to: bundlePath),
                    backHref: relativeHref(from: detailPath, to: galleryPath),
                    installHref: relativeHref(from: detailPath,
                                              to: isEN ? "en/index.html" : "index.html") + "#install")
                try renderPage(
                    source: paths.source.appendingPathComponent(
                        isEN ? "pages/en/templates/detail.html" : "pages/zh/templates/detail.html"),
                    destination: output.appendingPathComponent(detailPath),
                    partials: partials,
                    tokens: detailExtra)
            }
        }

        // 404 —— 不参与索引；语言替代指向首页，避免出现不存在的 /en/404.html。
        // GitHub Pages 会保留原始出错路径，所以 404 的站内链接必须从站点根开始解析。
        var notFoundTokens = commonTokens(
            language: zh, pagePath: "404.html", site: site, siteURL: siteURL,
            title: "404 — PinShell", description: "Page not found.",
            langSwitchPath: "/en/index.html", jsonLD: "")
        notFoundTokens["ROBOTS"] = #"<meta name="robots" content="noindex">"#
        notFoundTokens["ROOT"] = "/"
        notFoundTokens["ALT_ZH"] = absolute(siteURL, "")
        notFoundTokens["ALT_EN"] = absolute(siteURL, "en/")
        try renderPage(source: paths.source.appendingPathComponent("pages/404.html"),
                       destination: output.appendingPathComponent("404.html"),
                       partials: partials,
                       tokens: notFoundTokens)

        try writeSitemap(catalog: catalog, site: site, siteURL: siteURL, output: output)
        try writeRobots(siteURL: siteURL, output: output)
        try Data().write(to: output.appendingPathComponent(".nojekyll"))
    }

    // MARK: - 页面

    private static func commonTokens(language: SiteLanguage,
                                     pagePath: String,
                                     site: SiteConfig,
                                     siteURL: String,
                                     title: String,
                                     description: String,
                                     langSwitchPath: String,
                                     jsonLD: String) -> [String: String] {
        let isEN = LanguageTag.matches(language.id, "en")
        let canonicalPath = canonicalPath(for: pagePath)
        let otherLanguage = isEN ? "zh-Hans" : "en"
        return [
            "LANG": language.htmlLang,
            "ROOT": rootPrefix(for: pagePath),
            "TITLE": title,
            "DESCRIPTION": description,
            "CANONICAL": absolute(siteURL, canonicalPath),
            "ALT_ZH": absolute(siteURL, isEN ? canonicalPath.replacingOccurrences(
                of: "^en/", with: "", options: .regularExpression) : canonicalPath),
            "ALT_EN": absolute(siteURL, isEN ? canonicalPath : "en/\(canonicalPath)"),
            "OG_LOCALE": isEN ? "en_US" : "zh_CN",
            "OG_IMAGE": absolute(siteURL, "assets/og-\(isEN ? "en" : "zh").png"),
            "ROBOTS": "",
            "JSON_LD": jsonLD,
            "SITE_NAME": site.name,
            "DOWNLOAD_URL": site.downloadURL,
            "GITHUB_URL": site.githubURL,
            "ISSUES_URL": site.issuesURL,
            "RELEASES_URL": site.releasesURL,
            "LANG_SWITCH_URL": langSwitchPath,
            "LANG_SWITCH_LABEL": otherLanguage == "en" ? "EN" : "中文",
            // 模板区下的页面在服务端直接标记当前导航项；404 等页面不标。
            "NAV_TEMPLATES_CURRENT": pagePath.contains("templates/")
                ? #" aria-current="page""# : "",
            "YEAR": String(Calendar.current.component(.year, from: Date())),
        ]
    }

    private static func renderPage(source: URL, destination: URL,
                                   partials: URL,
                                   tokens: [String: String]) throws {
        let html = try String(contentsOf: source, encoding: .utf8)
        let expanded = try expandIncludes(in: html, partials: partials, depth: 0)
        let rendered = try replaceTokens(in: expanded, tokens: tokens)
        if rendered.contains("{{") {
            throw BuilderError(message: "unreplaced token in \(destination.lastPathComponent)")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try rendered.write(to: destination, atomically: true, encoding: .utf8)
    }

    private static func expandIncludes(in html: String,
                                       partials: URL,
                                       depth: Int) throws -> String {
        guard depth < 6 else {
            throw BuilderError(message: "include depth exceeded")
        }
        let regex = try NSRegularExpression(
            pattern: #"<!--\s*include:\s*([A-Za-z0-9._-]+)\s*-->"#)
        let ns = html as NSString
        let matches = regex.matches(in: html,
                                    range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }
        var result = ""
        var cursor = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: cursor,
                                                 length: match.range.location - cursor))
            let name = ns.substring(with: match.range(at: 1))
            let partial = try String(
                contentsOf: partials.appendingPathComponent(name), encoding: .utf8)
            result += try expandIncludes(in: partial, partials: partials, depth: depth + 1)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func replaceTokens(in html: String,
                                      tokens: [String: String]) throws -> String {
        let regex = try NSRegularExpression(pattern: #"\{\{([A-Z0-9_]+)\}\}"#)
        let ns = html as NSString
        let matches = regex.matches(in: html,
                                    range: NSRange(location: 0, length: ns.length))
        var result = ""
        var cursor = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: cursor,
                                                 length: match.range.location - cursor))
            let key = ns.substring(with: match.range(at: 1))
            guard let value = tokens[key] else {
                throw BuilderError(message: "missing token \(key)")
            }
            result += value
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: - 碎片

    private static func categoryFilters(site: SiteConfig, language: String) -> String {
        let allTitle = LanguageTag.matches(language, "en") ? "All" : "全部"
        var html = #"<button class="chip is-active" type="button" aria-pressed="true" data-category-filter="all">\#(escapeHTML(allTitle))</button>"#
        for category in site.categories {
            let name = category.name(preferredLanguages: [language])
            html += "\n"
            html += #"<button class="chip" type="button" aria-pressed="false" data-category-filter="\#(escapeHTML(category.id))">\#(escapeHTML(name))</button>"#
        }
        return html
    }

    private static func card(_ template: BuiltTemplate,
                             language: String,
                             detailHref: String,
                             previewHref: String,
                             category: String) -> String {
        let entry = template.entry
        let name = entry.localizedName(preferredLanguages: [language])
        let description = entry.localizedDescription(preferredLanguages: [language])
        let width = entry.preview?.width ?? Int(template.metadata.size?.width ?? 0)
        let height = entry.preview?.height ?? Int(template.metadata.size?.height ?? 0)
        let author = entry.author?.name ?? ""
        let search = "\(name) \(description) \(category) \(author) \(entry.id) \((entry.tags ?? []).joined(separator: " "))"
            .lowercased()
        return """
        <a class="template-card" href="\(escapeAttribute(detailHref))" data-category="\(escapeAttribute(entry.category ?? ""))" data-search="\(escapeAttribute(search))">
          <div class="preview-stage" data-src="\(escapeAttribute(previewHref))" data-w="\(width)" data-h="\(height)">
            <div class="preview-poster"><span class="poster-mark"></span><strong>\(escapeHTML(name))</strong><small>\(width)×\(height)</small></div>
          </div>
          <div class="card-copy">
            <div class="card-meta"><span class="version">v\(escapeHTML(entry.version))</span><span>\(escapeHTML(category))</span><span>\(width)×\(height)</span></div>
            <h3>\(escapeHTML(name))</h3>
            <p>\(escapeHTML(description))</p>
          </div>
        </a>
        """
    }

    private static func heroPanel(_ template: BuiltTemplate,
                                  index: Int,
                                  language: String,
                                  root: String) -> String {
        let entry = template.entry
        let name = entry.localizedName(preferredLanguages: [language])
        let width = entry.preview?.width ?? 320
        let height = entry.preview?.height ?? 200
        let href = root + "templates/\(entry.id)/"
        let src = root + "templates/\(entry.id)/\(entry.version)/\(entry.file)?lang=\(language)"
        return """
        <a class="hero-window hero-window-\(index + 1)" href="\(escapeAttribute(href))" aria-label="\(escapeAttribute(name))">
          <div class="window-bar"><span></span><span></span><span></span></div>
          <div class="preview-stage" data-src="\(escapeAttribute(src))" data-w="\(width)" data-h="\(height)" data-eager="true">
            <div class="preview-poster"><span class="poster-mark"></span><strong>\(escapeHTML(name))</strong></div>
          </div>
        </a>
        """
    }

    private static func detailBody(_ template: BuiltTemplate,
                                   language: String,
                                   site: SiteConfig,
                                   strings: SiteStrings,
                                   payloadHref: String,
                                   bundleHref: String,
                                   backHref: String,
                                   installHref: String) -> String {
        let entry = template.entry
        let isEN = LanguageTag.matches(language, "en")
        let name = entry.localizedName(preferredLanguages: [language])
        let description = entry.localizedDescription(preferredLanguages: [language])
        let listing = entry.listing(preferredLanguages: [language])
        let tagline = listing?.tagline ?? description
        let category = categoryName(entry.category, site: site, language: language)
        let width = entry.preview?.width ?? 320
        let height = entry.preview?.height ?? 200
        let allLanguages = entry.languages?.keys.map { String($0) } ?? []
        var orderedLanguages: [String] = []
        for tag in [entry.defaultLanguage, entry.fallbackLanguage].compactMap({ $0 }) {
            if let match = allLanguages.first(where: { LanguageTag.matches($0, tag) }),
               !orderedLanguages.contains(match) {
                orderedLanguages.append(match)
            }
        }
        for tag in allLanguages.sorted() where !orderedLanguages.contains(tag) {
            orderedLanguages.append(tag)
        }
        let languages = orderedLanguages.joined(separator: " · ")

        var authorRow = ""
        if let author = entry.author {
            var value = escapeHTML(author.name)
            if let url = author.url {
                value = "<a href=\"\(escapeAttribute(url))\">\(value)</a>"
            }
            authorRow =
                "<div><dt>\(escapeHTML(strings.author))</dt><dd>\(value)</dd></div>"
        }

        var highlights = ""
        if let items = listing?.highlights, !items.isEmpty {
            highlights = """
            <section class="detail-block">
              <h2>\(escapeHTML(strings.highlights))</h2>
              <ul class="highlight-list">
                \(items.map { "<li>\(escapeHTML($0))</li>" }.joined(separator: "\n"))
              </ul>
            </section>
            """
        }

        let changelogRows = entry.changelogEntries.map { item in
            let notes = entry.changelogNotes(version: item.version,
                                             preferredLanguages: [language])
                ?? (isEN ? "No release notes." : "暂无说明。")
            return """
            <article class="release-row">
              <div class="release-meta"><strong>v\(escapeHTML(item.version))</strong><span>\(escapeHTML(item.entry.date ?? ""))</span></div>
              <p>\(escapeHTML(notes))</p>
            </article>
            """
        }.joined(separator: "\n")

        return """
        <article class="detail">
          <header class="detail-head">
            <a class="back-link" href="\(escapeAttribute(backHref))">← \(escapeHTML(strings.backToGallery))</a>
            <p class="eyebrow">v\(escapeHTML(entry.version)) · \(escapeHTML(category))</p>
            <h1>\(escapeHTML(name))</h1>
            <p class="lead">\(escapeHTML(description))</p>
            <p class="tagline">\(escapeHTML(tagline))</p>
            <div class="cta-row">
              <a class="button primary" href="\(escapeAttribute(bundleHref))" download>\(escapeHTML(strings.downloadHTML))</a>
              <a class="button secondary" href="\(escapeAttribute(installHref))">\(escapeHTML(strings.installApp))</a>
            </div>
            <p class="fine">\(escapeHTML(strings.installHint))</p>
          </header>
          <div class="detail-grid">
            <div class="stage-wrap">
              <div class="preview-stage detail-stage" data-src="\(escapeAttribute(payloadHref + "?lang=\(language)"))" data-w="\(width)" data-h="\(height)" data-interactive="true" style="--preview-aspect: \(width) / \(height)">
                <div class="preview-poster"><span class="poster-mark"></span><strong>\(escapeHTML(name))</strong><small>\(width)×\(height)</small></div>
              </div>
              <p class="stage-caption">\(escapeHTML(strings.interactiveHint))</p>
            </div>
            <aside class="detail-side">
              \(highlights)
              <section class="detail-block">
                <h2>\(escapeHTML(strings.metadata))</h2>
                <dl class="meta-list">
                  <div><dt>\(escapeHTML(strings.version))</dt><dd>v\(escapeHTML(entry.version))</dd></div>
                  <div><dt>\(escapeHTML(strings.category))</dt><dd>\(escapeHTML(category))</dd></div>
                  \(authorRow)
                  <div><dt>\(escapeHTML(strings.size))</dt><dd>\(width)×\(height)</dd></div>
                  <div><dt>\(escapeHTML(strings.fileSize))</dt><dd>\(formattedBytes(entry.payload.bytes))</dd></div>
                  <div><dt>\(escapeHTML(strings.languages))</dt><dd>\(escapeHTML(languages))</dd></div>
                </dl>
              </section>
            </aside>
          </div>
          <section class="detail-block changelog-block">
            <h2>\(escapeHTML(strings.changelog))</h2>
            \(changelogRows.isEmpty ? "<p>\(escapeHTML(strings.noChangelog))</p>" : changelogRows)
          </section>
        </article>
        """
    }

    // MARK: - JSON-LD / sitemap

    private static func softwareApplicationJSON(site: SiteConfig, appVersion: String,
                                                canonical: String) -> [String: Any] {
        [
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": site.name,
            "applicationCategory": "DeveloperApplication",
            "operatingSystem": "macOS 13+",
            "softwareVersion": appVersion,
            "description": site.tagline["en"] ?? "",
            "url": canonical,
            "downloadUrl": site.downloadURL,
            "offers": ["@type": "Offer", "price": "0", "priceCurrency": "USD"],
        ]
    }

    private static func itemListJSON(catalog: BuiltCatalog, site: SiteConfig,
                                     language: String, siteURL: String) -> [String: Any] {
        let items = catalog.templates.enumerated().map { index, template -> [String: Any] in
            [
                "@type": "ListItem",
                "position": index + 1,
                "name": template.entry.localizedName(preferredLanguages: [language]),
                "url": absolute(siteURL, "\(languagePrefix(language, site: site))templates/\(template.entry.id)/"),
            ]
        }
        return [
            "@context": "https://schema.org",
            "@type": "ItemList",
            "name": "PinShell Template Library",
            "itemListElement": items,
        ]
    }

    private static func templateJSON(_ template: BuiltTemplate, language: String,
                                     siteURL: String, site: SiteConfig) -> [String: Any] {
        var object: [String: Any] = [
            "@context": "https://schema.org",
            "@type": "SoftwareSourceCode",
            "name": template.entry.localizedName(preferredLanguages: [language]),
            "description": template.entry.localizedDescription(preferredLanguages: [language]),
            "codeSampleType": "full",
            "programmingLanguage": ["HTML", "CSS", "JavaScript"],
            "version": template.entry.version,
            "url": absolute(siteURL, "\(languagePrefix(language, site: site))templates/\(template.entry.id)/"),
        ]
        if let author = template.entry.author {
            var person: [String: Any] = ["@type": "Person", "name": author.name]
            if let url = author.url { person["url"] = url }
            object["author"] = person
        }
        return object
    }

    private static func jsonLDTag(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return "" }
        let safe = json.replacingOccurrences(of: "</", with: "<\\/")
        return #"<script type="application/ld+json">\#(safe)</script>"#
    }

    private static func writeSitemap(catalog: BuiltCatalog, site: SiteConfig,
                                     siteURL: String, output: URL) throws {
        var entries: [(String, String)] = [
            ("", "en/"),
            ("templates/", "en/templates/"),
        ]
        for template in catalog.templates {
            entries.append(("templates/\(template.entry.id)/",
                            "en/templates/\(template.entry.id)/"))
        }
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">"# + "\n"
        for (zhPath, enPath) in entries {
            for path in [zhPath, enPath] {
                xml += "  <url>\n"
                xml += "    <loc>\(escapeXML(absolute(siteURL, path)))</loc>\n"
                xml += #"    <xhtml:link rel="alternate" hreflang="zh-Hans" href="\#(escapeXML(absolute(siteURL, zhPath)))" />"# + "\n"
                xml += #"    <xhtml:link rel="alternate" hreflang="en" href="\#(escapeXML(absolute(siteURL, enPath)))" />"# + "\n"
                xml += #"    <xhtml:link rel="alternate" hreflang="x-default" href="\#(escapeXML(absolute(siteURL, zhPath)))" />"# + "\n"
                xml += "  </url>\n"
            }
        }
        xml += "</urlset>\n"
        try xml.write(to: output.appendingPathComponent("sitemap.xml"),
                      atomically: true, encoding: .utf8)
    }

    private static func writeRobots(siteURL: String, output: URL) throws {
        let text = "User-agent: *\nAllow: /\n\nSitemap: \(siteURL)/sitemap.xml\n"
        try text.write(to: output.appendingPathComponent("robots.txt"),
                       atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func categoryName(_ id: String?, site: SiteConfig,
                                     language: String) -> String {
        guard let id, let category = site.categories.first(where: { $0.id == id }) else {
            return id ?? ""
        }
        return category.name(preferredLanguages: [language])
    }

    private static func languagePrefix(_ language: String, site: SiteConfig) -> String {
        site.language(id: language)?.pathPrefix ?? ""
    }

    private static func rootPrefix(for path: String) -> String {
        let depth = max(0, path.split(separator: "/").count - 1)
        return String(repeating: "../", count: depth)
    }

    private static func canonicalPath(for path: String) -> String {
        guard path != "index.html" else { return "" }
        guard path.hasSuffix("index.html") else { return path }
        return String(path.dropLast("index.html".count))
    }

    private static func absolute(_ siteURL: String, _ path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.isEmpty ? "\(siteURL)/" : "\(siteURL)/\(trimmed)"
    }

    private static func otherHomePath(_ language: String,
                                      homePaths: [String: String],
                                      languages: [SiteLanguage]) -> String {
        let other = LanguageTag.matches(language, "en") ? "zh-Hans" : "en"
        guard let target = homePaths[other] else { return "" }
        let from = homePaths[language] ?? "index.html"
        return relativeHref(from: from, to: target)
    }

    private static func otherGalleryPath(_ language: String,
                                         galleryPaths: [String: String],
                                         languages: [SiteLanguage]) -> String {
        let other = LanguageTag.matches(language, "en") ? "zh-Hans" : "en"
        guard let target = galleryPaths[other] else { return "" }
        let from = galleryPaths[language] ?? "templates/index.html"
        return relativeHref(from: from, to: target)
    }

    private static func relativeHref(from: String, to: String) -> String {
        let fromDir = (from as NSString).deletingLastPathComponent
        let fromParts = fromDir.isEmpty ? [] : fromDir.split(separator: "/").map(String.init)
        let toParts = to.split(separator: "/").map(String.init)
        var common = 0
        while common < fromParts.count,
              common < toParts.count,
              fromParts[common] == toParts[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: fromParts.count - common)
        let rest = toParts.dropFirst(common)
        let parts = ups + rest
        return parts.isEmpty ? "./" : parts.joined(separator: "/")
    }

    private static func copyDirectory(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let items = try? fm.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try copyDirectory(item, to: target)
            } else {
                if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    /// 与 App 下载器保持一致，避免同一文件在站点与 App 显示不同大小。
    private static func formattedBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\n", with: "")
    }

    private static func escapeXML(_ value: String) -> String {
        escapeHTML(value)
    }
}
