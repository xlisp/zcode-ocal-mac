import AppKit
import AVFoundation

/// 摄像头设置面板（对应原版的「摄像头设置」DirectShow 属性页）
/// 提供格式/曝光/对焦/白平衡/镜像等 AVFoundation 可控项，按设备实际支持情况启用
final class CameraSettingsController: NSWindowController, NSWindowDelegate {

    private let device: AVCaptureDevice
    private let service: CameraService

    private let stack = NSStackView()
    private var exposureAuto: NSButton?
    private var exposureSlider: NSSlider?
    private var exposureLabel: NSTextField?
    private var focusAuto: NSButton?
    private var focusSlider: NSSlider?
    private var wbAuto: NSButton?
    private var wbSlider: NSSlider?
    private var wbLabel: NSTextField?
    private var mirrorCheck: NSButton?
    private var formatPopup: NSPopUpButton?

    init(device: AVCaptureDevice, service: CameraService) {
        self.device = device
        self.service = service
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "摄像头设置 — \(CameraService.displayName(of: device))"
        super.init(window: window)
        window.delegate = self
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
    }

    // MARK: - UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // 格式（分辨率/帧率）
        let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPopup.controlSize = .small
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        let formats = device.formats.sorted(by: {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return a.width * a.height > b.width * b.height
        })
        for format in formats {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let fps = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            formatPopup.addItem(withTitle: "\(d.width)×\(d.height)  @\(Int(fps.rounded()))fps")
            formatPopup.lastItem?.representedObject = format
            if format == device.activeFormat { formatPopup.select(formatPopup.lastItem!) }
        }
        self.formatPopup = formatPopup
        addRow(label: "格式", views: [formatPopup])
        if formats.isEmpty {
            formatPopup.isEnabled = false
        }

        // 曝光
        if device.isExposureModeSupported(.custom) || device.isExposureModeSupported(.autoExpose) || device.isExposureModeSupported(.continuousAuto) {
            let auto = NSButton(checkboxWithTitle: "自动曝光", target: self, action: #selector(exposureAutoChanged(_:)))
            auto.controlSize = .small
            let slider = NSSlider()
            slider.minValue = 0
            slider.maxValue = 1000
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(exposureSliderChanged(_:))
            let label = NSTextField(labelWithString: "-- ms")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            exposureAuto = auto
            exposureSlider = slider
            exposureLabel = label
            let row = NSStackView(views: [slider, label])
            row.orientation = .horizontal
            row.spacing = 6
            addRow(label: "曝光", views: [auto])
            addRow(label: "", views: [row])
        }

        // 对焦
        if device.isFocusModeSupported(.locked) || device.isFocusModeSupported(.continuousAuto) {
            let auto = NSButton(checkboxWithTitle: "自动对焦", target: self, action: #selector(focusAutoChanged(_:)))
            auto.controlSize = .small
            let slider = NSSlider()
            slider.minValue = 0
            slider.maxValue = 100
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(focusSliderChanged(_:))
            focusAuto = auto
            focusSlider = slider
            addRow(label: "对焦", views: [auto])
            let row = NSStackView(views: [slider])
            row.orientation = .horizontal
            row.spacing = 6
            addRow(label: "", views: [row])
        }

        // 白平衡
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) || device.isWhiteBalanceModeSupported(.locked) {
            let auto = NSButton(checkboxWithTitle: "自动白平衡", target: self, action: #selector(wbAutoChanged(_:)))
            auto.controlSize = .small
            let slider = NSSlider()
            slider.minValue = 2800
            slider.maxValue = 8500
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(wbSliderChanged(_:))
            let label = NSTextField(labelWithString: "-- K")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            wbAuto = auto
            wbSlider = slider
            wbLabel = label
            addRow(label: "白平衡", views: [auto])
            let row = NSStackView(views: [slider, label])
            row.orientation = .horizontal
            row.spacing = 6
            addRow(label: "", views: [row])
        }

        // 镜像
        let mirror = NSButton(checkboxWithTitle: "画面左右镜像", target: self, action: #selector(mirrorChanged(_:)))
        mirror.controlSize = .small
        mirrorCheck = mirror
        addRow(label: "镜像", views: [mirror])
    }

    private func addRow(label: String, views: [NSView]) {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        if !label.isEmpty {
            let l = NSTextField(labelWithString: label)
            l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            l.setContentHuggingPriority(.required, for: .horizontal)
            row.insertArrangedSubview(l, at: 0)
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        }
        stack.addArrangedSubview(row)
        row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
    }

    /// 打开时同步当前设备状态
    private func refresh() {
        if let exposureAuto = exposureAuto {
            let isAuto = device.exposureMode == .continuousAuto || device.exposureMode == .autoExpose
            exposureAuto.state = isAuto ? .on : .off
            exposureSlider?.isEnabled = !isAuto
            if !isAuto { syncExposureUI() }
        }
        if let focusAuto = focusAuto {
            let isAuto = device.focusMode == .continuousAuto
            focusAuto.state = isAuto ? .on : .off
            focusSlider?.isEnabled = !isAuto
            if !isAuto {
                focusSlider?.doubleValue = Double(device.lensPosition) * 100
            }
        }
        if let wbAuto = wbAuto {
            let isAuto = device.whiteBalanceMode == .continuousAutoWhiteBalance
            wbAuto.state = isAuto ? .on : .off
            wbSlider?.isEnabled = !isAuto
        }
        if let mirror = mirrorCheck {
            let supported = service.videoConnection?.isVideoMirroringSupported ?? false
            mirror.isEnabled = supported
            mirror.state = (service.videoConnection?.isVideoMirrored ?? false) ? .on : .off
        }
    }

    private func syncExposureUI() {
        let d = device.exposureDuration
        let ms = d.isValid ? d.seconds * 1000 : 0
        exposureLabel?.stringValue = ms >= 100 ? String(format: "%.0f ms", ms) : String(format: "%.2f ms", ms)
        // 对数刻度滑杆
        let minD = device.minExposureDuration.seconds
        let maxD = device.maxExposureDuration.seconds
        if maxD > minD, minD > 0, ms > 0 {
            let t = log(ms / 1000 / minD) / log(maxD / minD)
            exposureSlider?.doubleValue = max(0, min(1, t)) * 1000
        }
    }

    // MARK: - 动作

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let format = sender.selectedItem?.representedObject as? AVCaptureDevice.Format else { return }
        CameraService.setFormat(format, on: device)
    }

    @objc private func exposureAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if auto {
                if device.isExposureModeSupported(.continuousAuto) { device.exposureMode = .continuousAuto }
                else if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
            } else {
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: device.exposureDuration)
                } else if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func exposureSliderChanged(_ sender: NSSlider) {
        let minD = device.minExposureDuration.seconds
        let maxD = device.maxExposureDuration.seconds
        guard maxD > minD, minD > 0 else { return }
        let t = sender.doubleValue / 1000.0
        let seconds = minD * pow(maxD / minD, t)
        let duration = CMTime(seconds: seconds, preferredTimescale: 100000)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(duration: duration)
            } else if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                device.activeVideoMaxFrameDuration = CMTime(seconds: max(seconds, 1.0 / 61.0), preferredTimescale: 600)
            }
        } catch { showAlert(error) }
        syncExposureUI()
    }

    @objc private func focusAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if auto {
                if device.isFocusModeSupported(.continuousAuto) { device.focusMode = .continuousAuto }
            } else {
                if device.isFocusModeSupported(.locked) {
                    device.setFocusModeLocked(lensPosition: Float(focusSlider?.doubleValue ?? 50) / 100)
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func focusSliderChanged(_ sender: NSSlider) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: Float(sender.doubleValue) / 100)
            }
        } catch { showAlert(error) }
    }

    @objc private func wbAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if auto {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } else {
                if device.isWhiteBalanceModeSupported(.locked) {
                    wbSliderChanged(wbSlider ?? NSSlider())
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func wbSliderChanged(_ sender: NSSlider) {
        guard device.isWhiteBalanceModeSupported(.locked) else { return }
        let temperature = Float(sender.doubleValue)
        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
        let gains = device.deviceWhiteBalanceGains(for: values)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setWhiteBalanceModeLocked(with: gains)
        } catch { showAlert(error) }
        wbLabel?.stringValue = "\(Int(temperature)) K"
    }

    @objc private func mirrorChanged(_ sender: NSButton) {
        service.videoConnection?.isVideoMirrored = sender.state == .on
    }

    private func showAlert(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
