import Foundation
import PinShellCore

private struct Options {
    var siteURL = "https://pinshell.looplooptech.com"
    var output: String?
    var check = false
    var appVersion: String?
    var root: String?
}

private func parseOptions() throws -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--site-url":
            guard let value = args.first else {
                throw BuilderError(message: "--site-url requires a value")
            }
            args.removeFirst()
            options.siteURL = value
        case "--output":
            guard let value = args.first else {
                throw BuilderError(message: "--output requires a value")
            }
            args.removeFirst()
            options.output = value
        case "--app-version":
            guard let value = args.first else {
                throw BuilderError(message: "--app-version requires a value")
            }
            args.removeFirst()
            options.appVersion = value
        case "--root":
            guard let value = args.first else {
                throw BuilderError(message: "--root requires a value")
            }
            args.removeFirst()
            options.root = value
        case "--check":
            options.check = true
        case "--help", "-h":
            print("""
            Usage: TemplateCatalogBuilder [--site-url URL] [--output DIR] [--check] [--app-version X.Y.Z] [--root DIR]
            """)
            exit(0)
        default:
            throw BuilderError(message: "unknown argument \(arg)")
        }
    }
    return options
}

private func resolveRemoteURL(_ raw: String) throws -> String {
    guard let url = URL(string: raw),
          let scheme = url.scheme?.lowercased(),
          (scheme == "https" || scheme == "http"),
          url.host != nil else {
        throw BuilderError(message: "invalid --site-url \(raw)")
    }
    if scheme == "http" {
        guard TemplateLibraryValidation.isAllowedRemoteURL(url) else {
            throw BuilderError(message: "--site-url HTTP is only allowed for loopback hosts")
        }
    }
    var value = raw
    while value.hasSuffix("/") { value.removeLast() }
    return value
}

private func resolvePath(_ raw: String) -> URL {
    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw).standardizedFileURL
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(raw)
        .standardizedFileURL
}

do {
    let options = try parseOptions()
    let siteURL = try resolveRemoteURL(options.siteURL)
    let paths = try RepoPaths.discover(explicitRoot: options.root)
    let site = try paths.loadSiteConfig()
    let appVersion: String
    if let override = options.appVersion {
        appVersion = override
    } else {
        appVersion = try paths.appVersion()
    }

    let output: URL
    let isTemporary: Bool
    if options.check {
        output = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShellSiteCheck-\(UUID().uuidString)",
                                    isDirectory: true)
        isTemporary = true
    } else {
        output = options.output.map(resolvePath) ?? paths.publicDir
        isTemporary = false
    }
    defer {
        if isTemporary {
            try? FileManager.default.removeItem(at: output)
        }
    }

    let catalog = try CatalogBuilder.build(
        paths: paths,
        site: site,
        appVersion: appVersion,
        output: output)
    try PageRenderer.render(
        paths: paths,
        site: site,
        catalog: catalog,
        appVersion: appVersion,
        siteURL: siteURL,
        output: output)
    let summary = try SiteValidator.validate(output: output)

    print("PinShell site: \(summary.templateCount) templates, "
          + "\(summary.pageCount) pages, \(summary.linkCount) internal links")
    print("Output: \(output.path)")
    print("Catalog: \(output.appendingPathComponent("library.json").path)")
} catch {
    let message = (error as? BuilderError)?.description ?? String(describing: error)
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}
