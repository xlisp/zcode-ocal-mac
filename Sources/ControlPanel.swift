import AppKit
import AVFoundation

/// 左侧控制面板：复刻原版 MFC 对话框的分组与控件
/// （摄像头 / 圈1 / 圈2 / 圈3 / 准星 / 圆心偏移）
final class ControlPanel: NSView {

    // MARK: 对外回调
    var onSettingsChanged: ((Settings) -> Void)?
    var onToggleCamera: (() -> Void)?
    var onSelectDevice: ((AVCaptureDevice) -> Void)?
    var onCameraSettings: (() -> Void)?
    var onProfileSelected: ((String) -> Void)?
    var onSaveFocus: (() -> Void)?
    var onLoadFocus: (() -> Void)?

    // MARK: 状态
    private(set) var settings = Settings()
    private var appliers: [(Settings) -> Void] = []
    private var suppressNotifications = false

    // 控件引用
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let toggleButton = NSButton(title: "开启摄像头", target: nil, action: nil)
    private let resolutionField = NSTextField(labelWithString: "分辨率 --*--")
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storeField = NSTextField(labelWithString: "")

    private let mainStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        apply(settings)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - 构建界面

    private func buildUI() {
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        mainStack.detachesHiddenViews = true
        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // ── 摄像头组 ──────────────────────────────
        addHeader("摄像头")

        devicePopup.target = self
        devicePopup.action = #selector(deviceChanged(_:))
        devicePopup.controlSize = .small
        addFullWidthRow(devicePopup)

        let buttonRow = NSStackView(views: [])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 6
        toggleButton.target = self
        toggleButton.action = #selector(toggleCamera(_:))
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .small
        let settingsButton = NSButton(title: "摄像头设置", target: self, action: #selector(openCameraSettings(_:)))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        buttonRow.addArrangedSubview(toggleButton)
        buttonRow.addArrangedSubview(settingsButton)
        addFullWidthRow(buttonRow)

        resolutionField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        addFullWidthRow(resolutionField)

        let profileRow = NSStackView(views: [makeSmallLabel("配置档案")])
        profileRow.orientation = .horizontal
        profileRow.spacing = 6
        for name in ["720", "1080", "1k", "4k"] {
            profilePopup.addItem(withTitle: name)
            profilePopup.lastItem?.representedObject = name
        }
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))
        profilePopup.controlSize = .small
        profileRow.addArrangedSubview(profilePopup)
        addFullWidthRow(profileRow)

        storeField.font = NSFont.systemFont(ofSize: 9)
        storeField.textColor = .secondaryLabelColor
        storeField.lineBreakMode = .byTruncatingMiddle
        addFullWidthRow(storeField)

        // ── 圈1 / 圈2 / 圈3 ──────────────────────────
        for (title, circle): (String, WritableKeyPath<Settings, CircleConfig>) in [
            ("圈1设置", \Settings.circle1),
            ("圈2设置", \Settings.circle2),
            ("圈3设置", \Settings.circle3),
        ] {
            addHeader(title)
            addCheckboxRow(label: "启    用",
                           get: { $0[keyPath: circle].enabled },
                           set: { s, v in s[keyPath: circle].enabled = v })
            addColorRow(label: "颜    色",
                        getColor: { $0[keyPath: circle].color },
                        setColor: { s, c in s[keyPath: circle].color = c })
            addSliderRow(label: "半    径", min: 0, max: 4000,
                         get: { $0[keyPath: circle].radius },
                         set: { s, v in s[keyPath: circle].radius = v })
            addSliderRow(label: "粗    细", min: 1, max: 40,
                         get: { $0[keyPath: circle].thickness },
                         set: { s, v in s[keyPath: circle].thickness = v })
        }

        // ── 准星设置 ──────────────────────────────
        addHeader("准星设置")
        addCheckboxRow(label: "启    用",
                       get: { $0.cross.enabled }, set: { s, v in s.cross.enabled = v })
        addColorRow(label: "颜    色",
                    getColor: { $0.cross.color }, setColor: { s, c in s.cross.color = c })
        addSliderRow(label: "长    度", min: 0, max: 4000,
                     get: { $0.cross.length }, set: { s, v in s.cross.length = v })
        addSliderRow(label: "粗    细", min: 1, max: 40,
                     get: { $0.cross.thickness }, set: { s, v in s.cross.thickness = v })
        addSliderRow(label: "角    度", min: 0, max: 360,
                     get: { $0.cross.angle }, set: { s, v in s.cross.angle = v })

        // ── 圆心偏移 ──────────────────────────────
        addHeader("圆心偏移")
        addCheckboxRow(label: "启用圆心偏移",
                       get: { $0.offset.enabled }, set: { s, v in s.offset.enabled = v })
        addSliderRow(label: "上    下", min: -100, max: 100,
                     get: { $0.offset.vertical }, set: { s, v in s.offset.vertical = v })
        addSliderRow(label: "左    右", min: -100, max: 100,
                     get: { $0.offset.horizontal }, set: { s, v in s.offset.horizontal = v })

        let focusRow = NSStackView(views: [])
        focusRow.orientation = .horizontal
        focusRow.distribution = .fillEqually
        focusRow.spacing = 6
        for b in [NSButton(title: "保存圆心", target: self, action: #selector(saveFocusAction(_:))),
                  NSButton(title: "载入圆心", target: self, action: #selector(loadFocusAction(_:)))] {
            b.bezelStyle = .rounded
            b.controlSize = .small
            focusRow.addArrangedSubview(b)
        }
        addFullWidthRow(focusRow)
    }

    // MARK: 控件工厂

    private func addHeader(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -24).isActive = true
        addFullWidthRow(label)
        mainStack.addArrangedSubview(rule)
    }

    /// 整行控件（横向撑满面板宽度）
    private func addFullWidthRow(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
    }

    private func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
        mainStack.addArrangedSubview(row)
        return row
    }

    private func makeSmallLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 11)
        f.setContentHuggingPriority(.required, for: .horizontal)
        f.setContentCompressionResistancePriority(.required, for: .horizontal)
        return f
    }

    private func makeValueField(min: Int, max: Int) -> NSTextField {
        let field = NSTextField()
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .center
        field.controlSize = .small
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: min)
        formatter.maximum = NSNumber(value: max)
        field.formatter = formatter
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }

    // MARK: 复合行

    /// 复选框行
    private func addCheckboxRow(label: String,
                                get: @escaping (Settings) -> Bool,
                                set: @escaping (inout Settings, Bool) -> Void) {
        let button = NSButton(checkboxWithTitle: label, target: self, action: #selector(checkboxFired(_:)))
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        objcSetSetter(button, SetterBox { s, v in set(&s, v != 0) })
        addFullWidthRow(button)
        appliers.append { [weak button] s in
            button?.state = get(s) ? .on : .off
        }
    }

    /// 滑杆行：标签 + 滑杆 + 数值框（可手输精确值）
    private func addSliderRow(label: String, min: Int, max: Int,
                              get: @escaping (Settings) -> Int,
                              set: @escaping (inout Settings, Int) -> Void) {
        let slider = NSSlider()
        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderFired(_:))

        let field = makeValueField(min: min, max: max)
        field.target = self
        field.action = #selector(valueFieldFired(_:))

        objcSetSetter(slider, SetterBox { s, v in set(&s, v) })
        objcSetSetter(field, SetterBox { s, v in set(&s, v) })
        objcSetLinked(slider, field)
        objcSetLinked(field, slider)

        _ = makeRow([makeSmallLabel(label), slider, field])
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        appliers.append { [weak slider, weak field] s in
            let v = Double(get(s))
            slider?.doubleValue = v
            field?.integerValue = Int(v)
        }
    }

    /// 颜色行
    private func addColorRow(label: String,
                             getColor: @escaping (Settings) -> NSColor,
                             setColor: @escaping (inout Settings, NSColor) -> Void) {
        let well = NSColorWell()
        well.controlSize = .small
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.target = self
        well.action = #selector(colorFired(_:))
        objcSetColorBinder(well, ColorBinderBox(
            { s in getColor(s) },
            { s, c in setColor(&s, c) }))
        _ = makeRow([makeSmallLabel(label), well])
        appliers.append { [weak well] s in
            well?.color = getColor(s)
        }
    }

    // MARK: - 动作

    @objc private func toggleCamera(_ sender: NSButton) { onToggleCamera?() }

    @objc private func openCameraSettings(_ sender: NSButton) { onCameraSettings?() }

    @objc private func deviceChanged(_ sender: NSPopUpButton) {
        guard let device = sender.selectedItem?.representedObject as? AVCaptureDevice else { return }
        onSelectDevice?(device)
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard let name = sender.selectedItem?.representedObject as? String else { return }
        onProfileSelected?(name)
    }

    @objc private func saveFocusAction(_ sender: NSButton) { onSaveFocus?() }

    @objc private func loadFocusAction(_ sender: NSButton) { onLoadFocus?() }

    @objc private func checkboxFired(_ sender: NSButton) {
        guard let setter = objcGetSetter(sender) else { return }
        setter(&settings, sender.state == .on ? 1 : 0)
        notifyChanged()
    }

    @objc private func sliderFired(_ sender: NSSlider) {
        guard let setter = objcGetSetter(sender) else { return }
        let v = Int(sender.doubleValue.rounded())
        setter(&settings, v)
        if let linked = objcGetLinked(sender) as? NSTextField { linked.integerValue = v }
        notifyChanged()
    }

    @objc private func valueFieldFired(_ sender: NSTextField) {
        guard let setter = objcGetSetter(sender) else { return }
        let fmt = sender.formatter as? NumberFormatter
        var v = sender.integerValue
        if let lo = fmt?.minimum?.intValue { v = max(v, lo) }
        if let hi = fmt?.maximum?.intValue { v = min(v, hi) }
        sender.integerValue = v
        setter(&settings, v)
        if let linked = objcGetLinked(sender) as? NSSlider { linked.doubleValue = Double(v) }
        notifyChanged()
    }

    @objc private func colorFired(_ sender: NSColorWell) {
        guard let binder = objcGetColorBinder(sender) else { return }
        binder.setter(&settings, sender.color)
        notifyChanged()
    }

    private func notifyChanged() {
        guard !suppressNotifications else { return }
        onSettingsChanged?(settings)
    }

    // MARK: - 外部刷新

    /// 用新的 Settings 刷新全部控件（不发通知）
    func apply(_ s: Settings) {
        suppressNotifications = true
        settings = s
        if let item = profilePopup.itemArray.first(where: { ($0.representedObject as? String) == s.profile }) {
            profilePopup.select(item)
        }
        appliers.forEach { $0(s) }
        suppressNotifications = false
    }

    func setDevices(_ list: [AVCaptureDevice], selected: AVCaptureDevice?) {
        devicePopup.removeAllItems()
        for device in list {
            devicePopup.addItem(withTitle: CameraService.displayName(of: device))
            devicePopup.lastItem?.representedObject = device
        }
        if let selected = selected,
           let item = devicePopup.itemArray.first(where: { ($0.representedObject as? AVCaptureDevice)?.uniqueID == selected.uniqueID }) {
            devicePopup.select(item)
        }
    }

    var selectedDevice: AVCaptureDevice? {
        devicePopup.selectedItem?.representedObject as? AVCaptureDevice
    }

    func setRunning(_ running: Bool) {
        toggleButton.title = running ? "关闭摄像头" : "开启摄像头"
    }

    func setResolution(_ size: CGSize) {
        resolutionField.stringValue = "分辨率 \(Int(size.width))*\(Int(size.height))"
    }

    func setStoreHint(_ text: String) {
        storeField.stringValue = text
    }
}

// MARK: - 控件与闭包绑定（借助关联对象）

private enum Keys {
    nonisolated(unsafe) static var setter = 0
    nonisolated(unsafe) static var linked = 0
    nonisolated(unsafe) static var colorBinder = 0
}

private final class SetterBox { let f: (inout Settings, Int) -> Void; init(_ f: @escaping (inout Settings, Int) -> Void) { self.f = f } }
private final class ColorBinderBox {
    let setter: (inout Settings, NSColor) -> Void
    init(_ getter: (Settings) -> NSColor, _ setter: @escaping (inout Settings, NSColor) -> Void) {
        self.setter = setter
    }
}

private func objcSetSetter(_ o: AnyObject, _ b: SetterBox) { objc_setAssociatedObject(o, &Keys.setter, b, .OBJC_ASSOCIATION_RETAIN) }
private func objcGetSetter(_ o: AnyObject) -> SetterBox? { objc_getAssociatedObject(o, &Keys.setter) as? SetterBox }
private func objcSetLinked(_ o: AnyObject, _ linked: AnyObject) { objc_setAssociatedObject(o, &Keys.linked, linked, .OBJC_ASSOCIATION_RETAIN) }
private func objcGetLinked(_ o: AnyObject) -> AnyObject? { objc_getAssociatedObject(o, &Keys.linked) }
private func objcSetColorBinder(_ o: AnyObject, _ b: ColorBinderBox) { objc_setAssociatedObject(o, &Keys.colorBinder, b, .OBJC_ASSOCIATION_RETAIN) }
private func objcGetColorBinder(_ o: AnyObject) -> ColorBinderBox? { objc_getAssociatedObject(o, &Keys.colorBinder) as? ColorBinderBox }
