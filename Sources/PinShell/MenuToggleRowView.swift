import AppKit

/// 菜单内的开关行：原生 NSMenu 不提供开关控件，用自定义视图承载标题 + NSSwitch。
/// 点击开关或行内任意空白处都会切换；开关状态通过 `onChange` 回传。
final class MenuToggleRowView: NSView {
    /// 与原生菜单项标题的左边距对齐（行容器自带 1pt 内边距）。
    private static let leadingInset: CGFloat = 16
    private static let trailingInset: CGFloat = 14

    /// 开关状态变化回调（参数为目标状态）。
    var onChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()

    var title: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            setAccessibilityLabel(newValue)
            toggle.setAccessibilityLabel(newValue)
        }
    }

    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }

    var isRowEnabled: Bool = true {
        didSet {
            label.textColor = isRowEnabled ? .labelColor : .disabledControlTextColor
            toggle.isEnabled = isRowEnabled
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        autoresizingMask = [.width]

        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = #selector(toggleChanged)

        addSubview(label)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleChanged() {
        onChange?(toggle.state == .on)
    }

    /// 点击行内空白处也切换开关（与勾选菜单项一致）。
    override func mouseDown(with event: NSEvent) {
        guard isRowEnabled else { return }
        toggle.state = toggle.state == .on ? .off : .on
        toggleChanged()
    }

    /// 标签本身不处理点击，整行除开关外都归本视图，保证点标题也能切换。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let hit = super.hitTest(point)
        if hit === toggle || hit?.isDescendant(of: toggle) == true {
            return hit
        }
        return isRowEnabled ? self : nil
    }

    /// AppKit 会把菜单项视图放进与菜单等宽的容器里，跟随容器宽度让开关右侧对齐。
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        matchContainerWidth()
    }

    override func layout() {
        super.layout()
        matchContainerWidth()
    }

    private func matchContainerWidth() {
        guard let container = superview else { return }
        let width = container.bounds.width
        guard width > 0, abs(frame.width - width) > 0.5 else { return }
        frame.size.width = width
    }
}
