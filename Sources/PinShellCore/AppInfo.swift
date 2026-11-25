import Foundation

/// App 身份与安装位置的单一来源：更新、CLI、MCP 与打包脚本共用同一组事实。
/// 修改这些值时必须同步 Resources/Info.plist、Makefile 与 scripts/pkg-postinstall。
public enum PinShellAppInfo {
    public static let name = "PinShell"
    /// 与 Info.plist 的 CFBundleIdentifier 一致。
    public static let bundleIdentifier = "com.pinshell.app"
    /// 与 Makefile 的 pkgbuild --identifier 一致。
    public static let pkgIdentifier = "com.pinshell.app.pkg"
    /// pkg 的安装位置；Makefile 的 --install-location 与之对应。
    public static let installDirectory = "/Applications"
    public static let installerBundleIdentifier = "com.apple.installer"

    public static var executableURL: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: name)
    }

    public static var installedAppURL: URL {
        URL(fileURLWithPath: installDirectory).appendingPathComponent("\(name).app")
    }

    public static var installedExecutableURL: URL {
        installedAppURL.appendingPathComponent("Contents/MacOS/\(name)")
    }

    public static var receiptURL: URL {
        URL(fileURLWithPath: "/var/db/receipts/\(pkgIdentifier).plist")
    }
}
