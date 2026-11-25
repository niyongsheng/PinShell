import AppKit
import PinShellCore

/// 更新下载进度小面板：图标 + 标题 + 进度 + 取消。
/// 只在主线程使用。
final class UpdateProgressWindowController: NSObject {
    private let panel: NSPanel
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelButton = NSButton()
    private var cancelled = false

    /// 点击取消时回调（主线程）。
    var onCancel: (() -> Void)?

    init(version: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                        styleMask: [.titled],
                        backing: .buffered,
                        defer: false)
        super.init()
        panel.title = NSLocalizedString("update.windowTitle", comment: "")
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        build(version: version)
    }

    // MARK: - UI

    private func build(version: String) {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        let title = NSTextField(labelWithString: String(
            format: NSLocalizedString("update.downloadingTitle", comment: ""), version))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [title, statusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let top = NSStackView(views: [icon, textStack])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 12

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.title = NSLocalizedString("update.cancel", comment: "")
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let bottom = NSStackView(views: [progressBar, cancelButton])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 10

        let stack = NSStackView(views: [top, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            progressBar.heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    // MARK: - 生命周期

    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        progressBar.stopAnimation(nil)
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - 状态更新

    func update(received: Int64, total: Int64) {
        if total > 0 {
            progressBar.isIndeterminate = false
            progressBar.doubleValue = min(1, Double(received) / Double(total))
            statusLabel.stringValue =
                "\(NumberFormat.bytes(received)) / \(NumberFormat.bytes(total))"
        } else {
            makeIndeterminate()
            statusLabel.stringValue = NumberFormat.bytes(received)
        }
    }

    /// 下载完成后的校验/打开安装器阶段：不确定进度，禁用取消。
    func setPhase(_ text: String) {
        makeIndeterminate()
        cancelButton.isEnabled = false
        statusLabel.stringValue = text
    }

    // MARK: - 动作

    @objc private func cancelTapped() {
        guard !cancelled else { return }
        cancelled = true
        setPhase(NSLocalizedString("update.cancelling", comment: ""))
        onCancel?()
    }

    private func makeIndeterminate() {
        guard !progressBar.isIndeterminate else { return }
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
    }
}
