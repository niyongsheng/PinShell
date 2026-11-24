import Darwin
import Foundation

/// 匿名使用统计（Aptabase）：默认开启，可在控制台「关于」页关闭。
/// 目前只在启动时上报一次 app_launch，不含文件名等任何用户内容。
final class Analytics {
    static let shared = Analytics()

    /// Aptabase 美国区应用密钥（A-US- 前缀对应 us.aptabase.com）。
    private static let appKey = "A-US-2677390542"
    private static let endpoint = URL(string: "https://us.aptabase.com/api/v0/events")!
    private static let sdkVersion = "pinshell-native@1.0.0"

    private let session: URLSession
    private let sessionId: String
    private var didTrackLaunch = false

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": "PinShell/\(Self.appVersion)"]
        session = URLSession(configuration: configuration)
        sessionId = Self.makeSessionId()
    }

    var isEnabled: Bool {
        get { AppState.analyticsEnabled }
        set { AppState.analyticsEnabled = newValue }
    }

    /// 每次启动只上报一次；开关关闭时静默跳过。
    func trackLaunchIfNeeded() {
        guard isEnabled, !didTrackLaunch else { return }
        didTrackLaunch = true
        track("app_launch")
    }

    // MARK: - 上报

    private func track(_ name: String) {
        let event: [String: Any] = [
            "timestamp": Self.timestampFormatter.string(from: Date()),
            "sessionId": sessionId,
            "eventName": name,
            "systemProps": Self.systemProps,
            "props": [:],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: [event]) else { return }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.appKey, forHTTPHeaderField: "App-Key")
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error {
                NSLog("PinShell analytics: %@", error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                NSLog("PinShell analytics: HTTP %d", http.statusCode)
                return
            }
            // 服务端可能以 200 + {"error": ...} 拒收事件（例如账户被锁定）。
            if let data,
               let body = String(data: data, encoding: .utf8),
               body.contains("\"error\"") {
                NSLog("PinShell analytics: %@", body)
            }
        }.resume()
    }

    // MARK: - 事件元数据

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static var systemProps: [String: Any] {
        [
            "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            "isDebug": isDebugBuild,
            "osName": "macOS",
            "osVersion": osVersion,
            "deviceModel": deviceModel,
            "appVersion": appVersion,
            "appBuildNumber": appBuildNumber,
            "sdkVersion": sdkVersion,
        ]
    }

    private static var appVersion: String {
        UpdateChecker.currentVersion
    }

    private static var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var deviceModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(cString: buffer)
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Aptabase 约定：epoch 秒 + 8 位随机数。
    private static func makeSessionId() -> String {
        let seconds = Int(Date().timeIntervalSince1970)
        let random = String(format: "%08d", Int.random(in: 0..<100_000_000))
        return "\(seconds)\(random)"
    }
}
