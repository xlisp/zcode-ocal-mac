import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var videoView: VideoView!
    private var panel: ControlPanel!
    private var panelScroll: NSScrollView!

    private let cameraService = CameraService()
    private var saveEnabled = false  // 启动载入时不回写，仅用户改动后保存
    private var settings = Settings() {
        didSet {
            videoView.settings = settings
            if saveEnabled { ConfigStore.save(settings) }
        }
    }

    private var settingsWindowController: CameraSettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()

        // 初始设置：上次使用的档案，默认 4k
        let lastProfile = UserDefaults.standard.string(forKey: "lastProfile") ?? "4k"
        settings = ConfigStore.load(profile: lastProfile)
        panel.apply(settings)

        panel.setStoreHint(ConfigStore.isPortable
            ? "配置目录（便携）：\(ConfigStore.directory.path)"
            : "配置目录：\(ConfigStore.directory.path)")

        // 摄像头列表
        refreshDeviceList()

        cameraService.onFrame = { [weak self] image, size in
            guard let self = self else { return }
            if self.videoView.imageSize != size {
                // 分辨率变化 → 更新标签并自动切换档案
                self.videoView.imageSize = size
                self.panel.setResolution(size)
                let auto = ConfigStore.profile(forResolution: size)
                if auto != self.settings.profile {
                    var s = ConfigStore.load(profile: auto)
                    // 保留颜色（颜色与分辨率无关）
                    s.circle1.color = self.settings.circle1.color
                    s.circle2.color = self.settings.circle2.color
                    s.circle3.color = self.settings.circle3.color
                    s.cross.color = self.settings.cross.color
                    self.settings = s
                    self.panel.apply(s)
                    UserDefaults.standard.set(auto, forKey: "lastProfile")
                }
            }
            self.videoView.frameImage = image
        }

        cameraService.onRunning = { [weak self] running, error in
            guard let self = self else { return }
            self.panel.setRunning(running)
            if let error = error {
                self.showAlert(messageText: "摄像头", informativeText: error)
            }
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        saveEnabled = true

        // 调试：带 --autostart 参数启动时自动尝试开启摄像头
        if CommandLine.arguments.contains("--autostart") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCamera()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 窗口

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "OCAL — 准直仪校准 v1.32"
        window.minSize = NSSize(width: 940, height: 560)
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)

        let content = NSView()
        window.contentView = content

        videoView = VideoView(frame: .zero)
        panel = ControlPanel(frame: .zero)
        panelScroll = NSScrollView()
        panelScroll.documentView = panel
        panelScroll.hasVerticalScroller = true
        panelScroll.autohidesScrollers = true
        panelScroll.drawsBackground = true
        panelScroll.backgroundColor = NSColor.controlBackgroundColor
        panelScroll.borderType = .noBorder
        // documentView 需要显式初始尺寸：先按内容算高度，再跟随滚动视图宽度
        panel.setFrameOrigin(.zero)
        panel.setFrameSize(NSSize(width: 248, height: 0))
        let fittingHeight = panel.fittingSize.height
        panel.setFrameSize(NSSize(width: 248, height: max(fittingHeight, 100)))
        panel.autoresizingMask = [.width]

        for v: NSView in [panelScroll, videoView] {
            content.addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            // 左侧面板固定宽度
            panelScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            panelScroll.topAnchor.constraint(equalTo: content.topAnchor),
            panelScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panelScroll.widthAnchor.constraint(equalToConstant: 248),
            // 右侧视频区
            videoView.leadingAnchor.constraint(equalTo: panelScroll.trailingAnchor),
            videoView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: content.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        wirePanel()
    }

    private func wirePanel() {
        panel.onSettingsChanged = { [weak self] s in
            guard let self = self else { return }
            self.settings = s
        }
        panel.onToggleCamera = { [weak self] in self?.toggleCamera() }
        panel.onSelectDevice = { [weak self] device in
            guard let self = self else { return }
            UserDefaults.standard.set(device.uniqueID, forKey: "lastDeviceID")
            if self.cameraService.isRunning {
                self.cameraService.start(device: device)
            }
        }
        panel.onCameraSettings = { [weak self] in self?.openCameraSettings() }
        panel.onProfileSelected = { [weak self] name in
            guard let self = self else { return }
            var s = ConfigStore.load(profile: name)
            s.profile = name
            // 保留颜色
            s.circle1.color = self.settings.circle1.color
            s.circle2.color = self.settings.circle2.color
            s.circle3.color = self.settings.circle3.color
            s.cross.color = self.settings.cross.color
            self.settings = s
            self.panel.apply(s)
            UserDefaults.standard.set(name, forKey: "lastProfile")
        }
        panel.onSaveFocus = { [weak self] in
            guard let self = self else { return }
            guard self.videoView.frameImage != nil else {
                self.showAlert(messageText: "保存圆心", informativeText: "请先开启摄像头。")
                return
            }
            let size = self.videoView.imageSize
            let cx = size.width / 2 + CGFloat(self.settings.offset.horizontal)
            let cy = size.height / 2 + CGFloat(self.settings.offset.vertical)
            ConfigStore.saveFocus(CGPoint(x: cx, y: cy))
            self.showAlert(messageText: "保存圆心",
                           informativeText: String(format: "已写入 focus.txt：中心 = (%.2f, %.2f)", cx, cy))
        }
        panel.onLoadFocus = { [weak self] in
            guard let self = self else { return }
            guard self.videoView.frameImage != nil else {
                self.showAlert(messageText: "载入圆心", informativeText: "请先开启摄像头（需要知道当前分辨率）。")
                return
            }
            guard let p = ConfigStore.loadFocus() else {
                self.showAlert(messageText: "载入圆心", informativeText: "focus.txt 不存在或格式不对。")
                return
            }
            let size = self.videoView.imageSize
            var s = self.settings
            s.offset.horizontal = Int((p.x - size.width / 2).rounded())
            s.offset.vertical = Int((p.y - size.height / 2).rounded())
            s.offset.enabled = true
            self.settings = s
            self.panel.apply(s)
        }
    }

    // MARK: - 摄像头

    private func refreshDeviceList(selected: AVCaptureDevice? = nil) {
        let devices = CameraService.discoverDevices()
        let lastID = UserDefaults.standard.string(forKey: "lastDeviceID")
        var pick = selected
        if pick == nil { pick = devices.first(where: { $0.uniqueID == lastID }) }
        if pick == nil { pick = devices.first }
        panel.setDevices(devices, selected: pick)
    }

    private func toggleCamera() {
        if cameraService.isRunning {
            cameraService.stop()
        } else {
            startCamera()
        }
    }

    private func startCamera() {
        let start = { [weak self] in
            guard let self = self else { return }
            var device = self.panel.selectedDevice
            if device == nil {
                self.refreshDeviceList()
                device = self.panel.selectedDevice
            }
            guard let device = device else {
                self.showAlert(messageText: "开启摄像头",
                               informativeText: "未找到可用摄像头。若相机未识别，请检查连接。")
                return
            }
            self.cameraService.start(device: device)
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { start() }
                    else {
                        self.showAlert(messageText: "无法访问摄像头",
                                       informativeText: "请在 系统设置 → 隐私与安全性 → 摄像头 中允许 OCAL 访问。")
                    }
                }
            }
        default:
            showAlert(messageText: "无法访问摄像头",
                      informativeText: "请在 系统设置 → 隐私与安全性 → 摄像头 中允许 OCAL 访问。")
        }
    }

    private func openCameraSettings() {
        if let device = cameraService.currentDevice ?? panel.selectedDevice {
            settingsWindowController = CameraSettingsController(device: device, service: cameraService)
            settingsWindowController?.showWindow(nil)
        } else {
            showAlert(messageText: "摄像头设置", informativeText: "请先选择并开启摄像头。")
        }
    }

    // MARK: -

    private func showAlert(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
