import AppKit
import AVFoundation
import CoreMedia

/// 摄像头设置面板（对应原版的「摄像头设置」DirectShow 属性页）
///
/// 说明：macOS 的 AVFoundation 不提供 iOS 那套手动曝光时长/镜片位置/白平衡增益接口，
/// 这里只提供系统真实可控的项：格式（分辨率/帧率）、曝光模式、帧时长（UVC 相机的实际手动曝光手段）、
/// 对焦模式、白平衡模式（锁定当前值）、镜像。按设备实际支持情况启用。
final class CameraSettingsController: NSWindowController, NSWindowDelegate {

    private let device: AVCaptureDevice
    private let service: CameraService

    private let stack = NSStackView()
    private var formatPopup: NSPopUpButton?
    private var exposureAuto: NSButton?
    private var shutterSlider: NSSlider?
    private var shutterLabel: NSTextField?
    private var focusAuto: NSButton?
    private var wbAuto: NSButton?
    private var mirrorCheck: NSButton?

    init(device: AVCaptureDevice, service: CameraService) {
        self.device = device
        self.service = service
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 380),
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
            if a.width * a.height != b.width * b.height {
                return a.width * a.height > b.width * b.height
            }
            let fa = $0.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            let fb = $1.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            return fa > fb
        })
        for format in formats {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let fps = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            formatPopup.addItem(withTitle: "\(d.width)×\(d.height)  @\(Int(fps.rounded()))fps")
            formatPopup.lastItem?.representedObject = format
            if format == device.activeFormat { formatPopup.select(formatPopup.lastItem!) }
        }
        self.formatPopup = formatPopup
        addRow(label: "格式", view: formatPopup)
        if formats.isEmpty { formatPopup.isEnabled = false }

        // 曝光
        if device.isExposureModeSupported(.autoExpose) || device.isExposureModeSupported(.continuousAutoExposure)
            || device.isExposureModeSupported(.locked) || device.isExposureModeSupported(.custom) {
            let auto = NSButton(checkboxWithTitle: "自动曝光", target: self, action: #selector(exposureAutoChanged(_:)))
            auto.controlSize = .small
            exposureAuto = auto
            addRow(label: "曝光", view: auto)

            let slider = NSSlider()
            slider.minValue = 0
            slider.maxValue = 1000
            slider.isContinuous = false  // 手动曝光时才起效，拖完再设置
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(shutterSliderChanged(_:))
            let label = NSTextField(labelWithString: "-- ms")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            shutterSlider = slider
            shutterLabel = label
            let hint = NSTextField(labelWithString: "手动模式：帧时长（快门），拖动后应用")
            hint.font = NSFont.systemFont(ofSize: 9)
            hint.textColor = .secondaryLabelColor
            let row = NSStackView(views: [slider, label])
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .centerY
            addRow(label: "", view: row)
            addRow(label: "", view: hint)
        }

        // 对焦
        if device.isFocusModeSupported(.continuousAutoFocus) || device.isFocusModeSupported(.locked) {
            let auto = NSButton(checkboxWithTitle: "自动对焦", target: self, action: #selector(focusAutoChanged(_:)))
            auto.controlSize = .small
            focusAuto = auto
            addRow(label: "对焦", view: auto)
        }

        // 白平衡
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) || device.isWhiteBalanceModeSupported(.locked) {
            let auto = NSButton(checkboxWithTitle: "自动白平衡（取消勾选=锁定当前值）", target: self, action: #selector(wbAutoChanged(_:)))
            auto.controlSize = .small
            wbAuto = auto
            addRow(label: "白平衡", view: auto)
        }

        // 镜像
        let mirror = NSButton(checkboxWithTitle: "画面左右镜像", target: self, action: #selector(mirrorChanged(_:)))
        mirror.controlSize = .small
        mirrorCheck = mirror
        addRow(label: "镜像", view: mirror)
    }

    private func addRow(label: String, view: NSView) {
        let row = NSStackView(views: [])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        if !label.isEmpty {
            let l = NSTextField(labelWithString: label)
            l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            l.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(l)
        }
        row.addArrangedSubview(view)
        stack.addArrangedSubview(row)
        row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
    }

    /// 打开时同步当前设备状态
    private func refresh() {
        if let exposureAuto = exposureAuto {
            let isAuto = device.exposureMode == .autoExpose || device.exposureMode == .continuousAutoExposure
            exposureAuto.state = isAuto ? .on : .off
            shutterSlider?.isEnabled = !isAuto
            if !isAuto { syncShutterUI() }
        }
        if let focusAuto = focusAuto {
            focusAuto.state = (device.focusMode == .continuousAutoFocus || device.focusMode == .autoFocus) ? .on : .off
        }
        if let wbAuto = wbAuto {
            wbAuto.state = (device.whiteBalanceMode == .continuousAutoWhiteBalance) ? .on : .off
        }
        if let mirror = mirrorCheck {
            let supported = service.videoConnection?.isVideoMirroringSupported ?? false
            mirror.isEnabled = supported
            mirror.state = (service.videoConnection?.isVideoMirrored ?? false) ? .on : .off
        }
    }

    /// 帧时长滑杆（对数刻度：格式最短帧时长 ~ 最长帧时长）
    private var shutterRange: (minSeconds: Double, maxSeconds: Double) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        let minSec = ranges.map { $0.minFrameDuration.seconds }.min() ?? 0.033
        let maxSec = ranges.map { $0.maxFrameDuration.seconds }.max() ?? 1.0
        return (max(minSec, 0.001), max(maxSec, minSec))
    }

    private func syncShutterUI() {
        let d = device.activeVideoMaxFrameDuration
        guard d.isValid, d.seconds > 0 else {
            shutterLabel?.stringValue = "-- ms"
            return
        }
        let ms = d.seconds * 1000
        shutterLabel?.stringValue = ms >= 100 ? String(format: "%.0f ms", ms) : String(format: "%.1f ms", ms)
        let (lo, hi) = shutterRange
        if hi > lo {
            let t = log(d.seconds / lo) / log(hi / lo)
            shutterSlider?.doubleValue = max(0, min(1, t)) * 1000
        }
    }

    // MARK: - 动作

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let format = sender.selectedItem?.representedObject as? AVCaptureDevice.Format else { return }
        CameraService.setFormat(format, on: device)
        syncShutterUI()
    }

    @objc private func exposureAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            ObjCGuard.catching("exposureMode") {
                if auto {
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    else if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
                } else {
                    // 手动：custom（若支持，此时帧时长即曝光时长）否则锁定当前
                    if device.isExposureModeSupported(.custom) { device.exposureMode = .custom }
                    else if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func shutterSliderChanged(_ sender: NSSlider) {
        let (lo, hi) = shutterRange
        guard hi > lo else { return }
        let t = sender.doubleValue / 1000.0
        let seconds = lo * pow(hi / lo, t)
        let duration = CMTime(seconds: seconds, preferredTimescale: 100_000)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            ObjCGuard.catching("shutter") {
                if device.exposureMode != .custom, device.isExposureModeSupported(.custom) {
                    device.exposureMode = .custom
                }
                // 先 max 后 min，避免 min > max 瞬态
                device.activeVideoMaxFrameDuration = duration
                device.activeVideoMinFrameDuration = duration
            }
        } catch { showAlert(error) }
        syncShutterUI()
    }

    @objc private func focusAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            ObjCGuard.catching("focusMode") {
                if auto {
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                    else if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                } else {
                    // 锁定当前对焦位置（macOS 不提供镜头位置数值控制）
                    if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func wbAutoChanged(_ sender: NSButton) {
        let auto = sender.state == .on
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            ObjCGuard.catching("whiteBalanceMode") {
                if auto {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else {
                    if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                }
            }
        } catch { showAlert(error) }
        refresh()
    }

    @objc private func mirrorChanged(_ sender: NSButton) {
        service.videoConnection?.isVideoMirrored = sender.state == .on
    }

    private func showAlert(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
