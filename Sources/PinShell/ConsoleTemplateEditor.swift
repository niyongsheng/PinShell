import AppKit
import PinShellCore

/// 模板编辑弹窗：修改 HTML 中的 title/description 与 pinshell:* 参数。
/// 右侧窗口预览会随尺寸、位置、圆角、透明度实时变化。
final class TemplateEditorSheetController: NSWindowController, NSTextFieldDelegate {
    /// 返回 .success 时关闭弹窗；.failure 时在弹窗内展示错误。
    var onSave: ((HTMLTemplateEdit) -> Result<Void, Error>)?
    /// 弹窗关闭（保存成功/取消）后回调，便于外部释放。
    var onDismiss: (() -> Void)?

    private let item: TemplateItem

    private let titleField = NSTextField(string: "")
    private let subtitleField = NSTextField(string: "")
    private let sizePresetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let xField = NSTextField(string: "")
    private let yField = NSTextField(string: "")
    private let opacitySlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "100%")
    private let radiusSlider = NSSlider(value: 0, minValue: 0, maxValue: 80, target: nil, action: nil)
    private let radiusValueLabel = NSTextField(labelWithString: "0")
    private let passthroughSwitch = NSSwitch()
    private let orderField = NSTextField(string: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let previewView = EditorFramePreviewView()
    private let previewInfoLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    private var hasChanges = false
    private var isPopulating = false

    private static let anchors: [WindowAnchor] = WindowAnchor.allCases
    private static let sizePresets: [WindowSize] = [
        WindowSize(width: 200, height: 56),
        WindowSize(width: 240, height: 80),
        WindowSize(width: 280, height: 320),
        WindowSize(width: 300, height: 360),
        WindowSize(width: 320, height: 200),
        WindowSize(width: 420, height: 480),
    ]

    init(item: TemplateItem) {
        self.item = item
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = NSLocalizedString("console.editor.title", comment: "")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        populate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(in parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        parent.beginSheet(window)
    }

    // MARK: - 装配

    private func build() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let header = buildHeader()
        let form = buildForm()
        let preview = buildPreviewCard()

        let content = NSStackView(views: [form, preview])
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 18
        content.distribution = .fill
        preview.widthAnchor.constraint(equalToConstant: 206).isActive = true
        form.setContentHuggingPriority(.defaultLow, for: .horizontal)
        form.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        let restore = NSButton(title: NSLocalizedString("console.editor.restore", comment: ""),
                               target: self, action: #selector(restoreForm))
        restore.bezelStyle = .rounded
        restore.font = .systemFont(ofSize: 12)
        restore.image = NSImage(systemSymbolName: "arrow.uturn.backward",
                                accessibilityDescription: nil)
        restore.imagePosition = .imageLeading
        restore.toolTip = NSLocalizedString("console.editor.restoreHint", comment: "")

        let cancel = NSButton(title: NSLocalizedString("console.editor.cancel", comment: ""),
                              target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        saveButton.title = NSLocalizedString("console.editor.save", comment: "")
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.font = .systemFont(ofSize: 12, weight: .medium)
        saveButton.keyEquivalent = "\r"
        saveButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        saveButton.imagePosition = .imageLeading

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [restore, spacer, cancel, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let flexible = NSView()
        flexible.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [header, content, errorLabel, flexible, buttons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),

            // 头部宽度显式对齐内容区，避免被 NSStackView 的内在宽度推到右侧
            header.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func buildHeader() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "slider.horizontal.3",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
        ])

        let title = NSTextField(labelWithString: NSLocalizedString("console.editor.title", comment: ""))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .left
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let isBuiltin = TemplateStore.isBuiltinTemplate(named: item.file)
        let kind = isBuiltin
            ? NSLocalizedString("console.editor.builtin", comment: "")
            : NSLocalizedString("console.editor.user", comment: "")
        let fileLabel = NSTextField(labelWithString: "\(item.file)  ·  \(kind)")
        fileLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.alignment = .left
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.maximumNumberOfLines = 1
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerText = NSStackView(views: [title, fileLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 3
        headerText.distribution = .fill
        headerText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(lessThanOrEqualTo: headerText.widthAnchor),
            fileLabel.widthAnchor.constraint(lessThanOrEqualTo: headerText.widthAnchor),
        ])

        // 用显式约束而不是横向 stack：保证文本区吃满剩余宽度，
        // 左侧标题不会因内在宽度被 stack 挤到右边。
        let header = NSView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        headerText.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)
        header.addSubview(headerText)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            icon.topAnchor.constraint(equalTo: header.topAnchor),

            headerText.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            headerText.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerText.topAnchor.constraint(equalTo: header.topAnchor),
            headerText.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        return header
    }

    private func buildForm() -> NSStackView {
        configureField(titleField)
        configureField(subtitleField)

        for field in [widthField, heightField] {
            configureField(field)
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }
        for field in [xField, yField] {
            configureField(field)
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 58).isActive = true
        }
        configureField(orderField)
        orderField.alignment = .right
        orderField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        orderField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        sizePresetPopup.target = self
        sizePresetPopup.action = #selector(sizePresetChanged)
        sizePresetPopup.controlSize = .regular
        sizePresetPopup.font = .systemFont(ofSize: 11.5)
        sizePresetPopup.addItem(withTitle: NSLocalizedString("console.editor.customSize", comment: ""))
        for size in Self.sizePresets {
            sizePresetPopup.addItem(withTitle: "\(NumberFormat.text(size.width)) × \(NumberFormat.text(size.height))")
        }
        sizePresetPopup.widthAnchor.constraint(equalToConstant: 103).isActive = true

        positionPopup.target = self
        positionPopup.action = #selector(positionChanged)
        positionPopup.controlSize = .regular
        positionPopup.font = .systemFont(ofSize: 12)
        for anchor in Self.anchors {
            positionPopup.addItem(withTitle: anchor.displayName)
        }
        positionPopup.addItem(withTitle: NSLocalizedString("console.editor.custom", comment: ""))
        positionPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        radiusSlider.isContinuous = true
        radiusSlider.target = self
        radiusSlider.action = #selector(radiusChanged)

        for label in [opacityValueLabel, radiusValueLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 42).isActive = true
        }

        passthroughSwitch.controlSize = .small
        passthroughSwitch.target = self
        passthroughSwitch.action = #selector(formChanged)

        let sizeRow = NSStackView(views: [sizePresetPopup, widthField, label("×"), heightField,
                                          secondaryLabel(NSLocalizedString("console.editor.points", comment: ""))])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 6
        sizeRow.alignment = .centerY

        let coordinateRow = NSStackView(views: [label("X"), xField, label("Y"), yField])
        coordinateRow.orientation = .horizontal
        coordinateRow.spacing = 6
        coordinateRow.alignment = .centerY

        let opacityRow = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8
        opacityRow.alignment = .centerY
        opacitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let radiusRow = NSStackView(views: [radiusSlider, radiusValueLabel])
        radiusRow.orientation = .horizontal
        radiusRow.spacing = 8
        radiusRow.alignment = .centerY
        radiusSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let passthroughRow = NSStackView(views: [passthroughSwitch,
                                                secondaryLabel(NSLocalizedString("console.editor.passthroughHint", comment: ""))])
        passthroughRow.orientation = .horizontal
        passthroughRow.spacing = 10
        passthroughRow.alignment = .centerY

        let orderRow = NSStackView(views: [orderField,
                                          secondaryLabel(NSLocalizedString("console.editor.orderHint", comment: ""))])
        orderRow.orientation = .horizontal
        orderRow.spacing = 10
        orderRow.alignment = .centerY

        let infoHeader = sectionHeader(NSLocalizedString("console.editor.section.info", comment: ""),
                                       symbol: "doc.text")
        let windowHeader = sectionHeader(NSLocalizedString("console.editor.section.window", comment: ""),
                                         symbol: "macwindow")

        let separator = NSBox()
        separator.boxType = .separator

        let titleRow = formRow(NSLocalizedString("console.editor.name", comment: ""), titleField)
        let subtitleRow = formRow(NSLocalizedString("console.editor.description", comment: ""), subtitleField)
        let rows: [NSView] = [
            infoHeader,
            titleRow,
            subtitleRow,
            separator,
            windowHeader,
            formRow(NSLocalizedString("console.editor.size", comment: ""), sizeRow, stretch: false),
            formRow(NSLocalizedString("console.editor.position", comment: ""), positionPopup, stretch: false),
            formRow(NSLocalizedString("console.editor.coordinates", comment: ""), coordinateRow, stretch: false),
            formRow(NSLocalizedString("console.editor.opacity", comment: ""), opacityRow),
            formRow(NSLocalizedString("console.editor.radius", comment: ""), radiusRow),
            formRow(NSLocalizedString("console.editor.passthrough", comment: ""), passthroughRow, stretch: false),
            formRow(NSLocalizedString("console.editor.order", comment: ""), orderRow, stretch: false),
        ]

        let form = NSStackView(views: rows)
        form.orientation = .vertical
        form.alignment = .width
        form.spacing = 8
        form.setCustomSpacing(12, after: subtitleRow)
        form.setCustomSpacing(12, after: separator)
        return form
    }

    private func buildPreviewCard() -> NSView {
        let card = GlassCard(cornerRadius: 14)

        let heading = sectionHeader(NSLocalizedString("console.editor.preview", comment: ""),
                                    symbol: "rectangle.3.group")
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        previewInfoLabel.font = .systemFont(ofSize: 10)
        previewInfoLabel.textColor = .secondaryLabelColor
        previewInfoLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [heading, previewView, previewInfoLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.contentView.bottomAnchor),
        ])
        return card
    }

    /// 分区标题：强制贴左，避免在拉伸的垂直 stack 里被挤到右侧。
    private func sectionHeader(_ text: String, symbol: String) -> NSView {
        let label = makeSectionLabel(text, symbol: symbol)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer])
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .centerY
        return row
    }

    /// 单行表单：固定宽度标签 + 控件。
    /// 控件统一从标签右侧起始；stretch 为 true 时填满剩余宽度。
    private func formRow(_ title: String, _ control: NSView, stretch: Bool = true) -> NSStackView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12)
        name.textColor = .secondaryLabelColor
        name.alignment = .left
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 82).isActive = true

        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false

        let controlContainer = NSView()
        controlContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controlContainer.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            control.topAnchor.constraint(equalTo: controlContainer.topAnchor),
            control.bottomAnchor.constraint(equalTo: controlContainer.bottomAnchor),
        ])
        if stretch {
            control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor).isActive = true
        }

        let row = NSStackView(views: [name, controlContainer])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func configureField(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 12)
        field.controlSize = .regular
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func populate() {
        isPopulating = true

        titleField.stringValue = item.name
        subtitleField.stringValue = item.description
        widthField.stringValue = NumberFormat.text(item.size.width)
        heightField.stringValue = NumberFormat.text(item.size.height)
        orderField.stringValue = item.order == Int.max ? "0" : String(item.order)

        switch item.spec.position {
        case .anchor(let anchor):
            if let index = Self.anchors.firstIndex(of: anchor) {
                positionPopup.selectItem(at: index)
            }
        case .absolute(let x, let y):
            positionPopup.selectItem(at: Self.anchors.count)
            xField.stringValue = NumberFormat.text(x)
            yField.stringValue = NumberFormat.text(y)
        case nil:
            positionPopup.selectItem(at: Self.anchors.firstIndex(of: .bottomRight) ?? 0)
        }
        syncSizePreset()
        updatePositionFieldsEnabled()

        let opacity = item.spec.opacity ?? 1
        opacitySlider.doubleValue = opacity
        opacityValueLabel.stringValue = "\(Int((opacity * 100).rounded()))%"

        radiusSlider.doubleValue = min(max(item.spec.radius ?? 0, 0), radiusSlider.maxValue)
        radiusValueLabel.stringValue = NumberFormat.text(radiusSlider.doubleValue)

        passthroughSwitch.state = (item.spec.passthrough ?? false) ? .on : .off

        isPopulating = false
        hasChanges = false
        errorLabel.isHidden = true
        updatePreview()
    }

    // MARK: - 动作

    @objc private func sizePresetChanged() {
        let index = sizePresetPopup.indexOfSelectedItem
        guard index > 0, index <= Self.sizePresets.count else {
            window?.makeFirstResponder(widthField)
            return
        }
        let size = Self.sizePresets[index - 1]
        widthField.stringValue = NumberFormat.text(size.width)
        heightField.stringValue = NumberFormat.text(size.height)
        markChanged()
    }

    @objc private func positionChanged() {
        updatePositionFieldsEnabled()
        markChanged()
    }

    @objc private func opacityChanged() {
        opacityValueLabel.stringValue = "\(Int((opacitySlider.doubleValue * 100).rounded()))%"
        markChanged()
    }

    @objc private func radiusChanged() {
        radiusValueLabel.stringValue = NumberFormat.text(radiusSlider.doubleValue)
        markChanged()
    }

    @objc private func formChanged() {
        markChanged()
    }

    @objc private func restoreForm() {
        populate()
    }

    @objc private func cancel() {
        closeSheet()
    }

    @objc private func save() {
        errorLabel.isHidden = true

        guard hasChanges else {
            closeSheet()
            return
        }

        guard let width = Double(widthField.stringValue),
              let height = Double(heightField.stringValue),
              width.isFinite, height.isFinite,
              width >= WindowSize.minimum.width,
              height >= WindowSize.minimum.height else {
            showError(NSLocalizedString("console.editor.invalidSize", comment: ""))
            return
        }

        let position: WindowPosition
        if positionPopup.indexOfSelectedItem < Self.anchors.count {
            position = .anchor(Self.anchors[positionPopup.indexOfSelectedItem])
        } else {
            guard let x = Double(xField.stringValue), let y = Double(yField.stringValue),
                  x.isFinite, y.isFinite else {
                showError(NSLocalizedString("console.editor.invalidPosition", comment: ""))
                return
            }
            position = .absolute(x: x, y: y)
        }

        guard let order = Int(orderField.stringValue) else {
            showError(NSLocalizedString("console.editor.invalidOrder", comment: ""))
            return
        }

        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showError(NSLocalizedString("console.editor.invalidTitle", comment: ""))
            return
        }

        let edit = HTMLTemplateEdit(
            title: title,
            subtitle: subtitleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            size: WindowSize(width: width, height: height),
            position: position,
            passthrough: passthroughSwitch.state == .on,
            opacity: opacitySlider.doubleValue,
            radius: radiusSlider.doubleValue,
            order: order
        )

        guard let onSave else { return }
        switch onSave(edit) {
        case .success:
            closeSheet()
        case .failure(let error):
            showError(error.localizedDescription)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isPopulating else { return }
        syncSizePreset()
        markChanged()
    }

    private func closeSheet() {
        if let window, let parent = window.sheetParent {
            parent.endSheet(window)
        }
        onDismiss?()
    }

    private func markChanged() {
        guard !isPopulating else { return }
        hasChanges = true
        errorLabel.isHidden = true
        updatePreview()
    }

    private func updatePositionFieldsEnabled() {
        let isCustom = positionPopup.indexOfSelectedItem == Self.anchors.count
        xField.isEnabled = isCustom
        yField.isEnabled = isCustom
    }

    private func syncSizePreset() {
        guard let width = Double(widthField.stringValue),
              let height = Double(heightField.stringValue) else {
            sizePresetPopup.selectItem(at: 0)
            return
        }
        if let index = Self.sizePresets.firstIndex(where: {
            $0.width == width && $0.height == height
        }) {
            sizePresetPopup.selectItem(at: index + 1)
        } else {
            sizePresetPopup.selectItem(at: 0)
        }
    }

    private func updatePreview() {
        let width = max(Double(widthField.stringValue) ?? item.size.width, 1)
        let height = max(Double(heightField.stringValue) ?? item.size.height, 1)
        let position = selectedPosition()

        previewView.windowSize = NSSize(width: width, height: height)
        previewView.position = position
        previewView.opacity = opacitySlider.doubleValue
        previewView.radius = radiusSlider.doubleValue

        let positionText = position?.displayName
            ?? NSLocalizedString("console.position.auto", comment: "")

        let opacity = Int((opacitySlider.doubleValue * 100).rounded())
        let radius = NumberFormat.text(radiusSlider.doubleValue)
        previewInfoLabel.stringValue =
            "\(NumberFormat.text(width)) × \(NumberFormat.text(height)) pt\n"
            + "\(positionText) · \(radius) pt · \(opacity)%"
    }

    private func selectedPosition() -> WindowPosition? {
        let index = positionPopup.indexOfSelectedItem
        if index >= 0, index < Self.anchors.count {
            return .anchor(Self.anchors[index])
        }
        guard let x = Double(xField.stringValue), let y = Double(yField.stringValue),
              x.isFinite, y.isFinite else {
            return nil
        }
        return .absolute(x: x, y: y)
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        NSSound.beep()
    }

    // MARK: - 辅助

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        return label
    }

}

// MARK: - 窗口预览

/// 屏幕示意图：按当前尺寸 / 位置 / 圆角 / 透明度画出窗口落点。
/// 绝对坐标按 1920×1080 的参考屏幕映射，仅作方向示意。
private final class EditorFramePreviewView: NSView {
    var windowSize = NSSize(width: CGFloat(WindowSize.fallback.width),
                            height: CGFloat(WindowSize.fallback.height)) {
        didSet { needsDisplay = true }
    }
    var position: WindowPosition? { didSet { needsDisplay = true } }
    var opacity: Double = 1 { didSet { needsDisplay = true } }
    var radius: Double = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let screen = bounds.insetBy(dx: 4, dy: 4)
        guard screen.width > 20, screen.height > 20 else { return }

        let screenPath = NSBezierPath(roundedRect: screen, xRadius: 10, yRadius: 10)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
        screenPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        screenPath.lineWidth = 1
        screenPath.stroke()

        let winWidth = max(windowSize.width, 1)
        let winHeight = max(windowSize.height, 1)
        let scale = min((screen.width * 0.60) / winWidth,
                        (screen.height * 0.60) / winHeight)
        let drawWidth = max(winWidth * scale, 8)
        let drawHeight = max(winHeight * scale, 6)
        let inset: CGFloat = 9
        let minX = screen.minX + inset
        let minY = screen.minY + inset
        let maxX = max(minX, screen.maxX - drawWidth - inset)
        let maxY = max(minY, screen.maxY - drawHeight - inset)

        var origin = NSPoint(x: (screen.midX - drawWidth / 2),
                             y: (screen.midY - drawHeight / 2))

        switch position {
        case .anchor(.topLeft)?:
            origin = NSPoint(x: minX, y: minY)
        case .anchor(.top)?:
            origin = NSPoint(x: (minX + maxX) / 2, y: minY)
        case .anchor(.topRight)?:
            origin = NSPoint(x: maxX, y: minY)
        case .anchor(.left)?:
            origin = NSPoint(x: minX, y: (minY + maxY) / 2)
        case .anchor(.center)?, nil:
            origin = NSPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        case .anchor(.right)?:
            origin = NSPoint(x: maxX, y: (minY + maxY) / 2)
        case .anchor(.bottomLeft)?:
            origin = NSPoint(x: minX, y: maxY)
        case .anchor(.bottom)?:
            origin = NSPoint(x: (minX + maxX) / 2, y: maxY)
        case .anchor(.bottomRight)?:
            origin = NSPoint(x: maxX, y: maxY)
        case .absolute(let x, let y)?:
            // 绝对坐标与 macOS 屏幕一致（原点左下）；预览视图翻转，需要翻转 y。
            let fx = CGFloat(min(max(x / 1920, 0), 1))
            let fy = CGFloat(min(max(y / 1080, 0), 1))
            origin = NSPoint(x: minX + fx * (maxX - minX),
                             y: minY + (1 - fy) * (maxY - minY))
        }

        let rect = NSRect(x: origin.x, y: origin.y, width: drawWidth, height: drawHeight)
        let corner = min(CGFloat(radius) * scale, min(drawWidth, drawHeight) / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

        let alpha = 0.14 + 0.42 * min(max(opacity, 0), 1)
        NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = "\(Int(windowSize.width))×\(Int(windowSize.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        if textSize.width + 10 <= rect.width, textSize.height + 2 <= rect.height {
            let point = NSPoint(x: rect.midX - textSize.width / 2,
                                y: rect.midY - textSize.height / 2)
            (text as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}
