import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import AppKit

/// AVFoundation 取流封装：设备枚举、格式选择、帧回调
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "ocal.camera.frames")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var configured = false

    /// 每帧回调（主线程）：CGImage + 相机像素尺寸
    var onFrame: ((CGImage, CGSize) -> Void)?
    /// 运行状态变化（主线程）
    var onRunning: ((Bool, String?) -> Void)?

    var isRunning: Bool { session.isRunning }
    private(set) var currentDevice: AVCaptureDevice?

    /// 视频输出连接（镜像设置用）
    var videoConnection: AVCaptureConnection? {
        output.connection(with: .video)
    }

    // MARK: 设备枚举

    static func discoverDevices() -> [AVCaptureDevice] {
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external, .builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified)
            devices = session.devices
        } else {
            // macOS 13 及以前：外接相机通过 devices(for:) 枚举，deviceType 为 .unknown
            devices = AVCaptureDevice.devices(for: .video)
        }
        // 外接 UVC 工业相机优先
        return devices.sorted { a, b in
            let ea = isExternal(a), eb = isExternal(b)
            if ea != eb { return ea }
            return a.localizedName < b.localizedName
        }
    }

    private static func isExternal(_ device: AVCaptureDevice) -> Bool {
        if #available(macOS 14.0, *) { return device.deviceType == .external }
        return device.deviceType == .unknown || device.modelID.contains("UVC")
    }

    static func displayName(of device: AVCaptureDevice) -> String {
        let name = device.localizedName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return device.modelID.isEmpty ? device.uniqueID : device.modelID
    }

    // MARK: 启停

    /// 在后台线程配置并启动会话，完成后回调主线程
    func start(device: AVCaptureDevice, completion: ((String?) -> Void)? = nil) {
        currentDevice = device
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var errorText: String? = nil
            do {
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                if !self.configured {
                    for out in self.session.outputs { self.session.removeOutput(out) }
                    self.output.videoSettings =
                        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    self.output.alwaysDiscardsLateVideoFrames = true
                    self.output.setSampleBufferDelegate(self, queue: self.frameQueue)
                    self.session.addOutput(self.output)
                    self.configured = true
                }
                self.session.sessionPreset = .inputPriority
                let input = try AVCaptureDeviceInput(device: device)
                self.session.addInput(input)
                self.session.commitConfiguration()
                Self.selectBestFormat(for: device)
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
                errorText = "无法打开摄像头：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.onRunning?(self.session.isRunning, errorText)
                completion?(errorText)
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.onRunning?(self.session.isRunning, nil)
                completion?()
            }
        }
    }

    // MARK: 格式选择

    /// 选择分辨率最大的视频格式，帧率取该格式支持的最大值（上限 30fps）
    static func selectBestFormat(for device: AVCaptureDevice) {
        let formats = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width > 0 && dims.height > 0
        }
        guard let best = formats.max(by: { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return da.width * da.height < db.width * db.height
        }) else { return }
        setFormat(best, on: device)
    }

    static func setFormat(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let range = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                let fps = min(max(range.maxFrameRate, 1), 30)
                let duration = CMTime(value: 1, timescale: CMTimeScale((fps).rounded()))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
        } catch {
            NSLog("设置相机格式失败: \(error.localizedDescription)")
        }
    }

    // MARK: 取帧

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetPixelBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // 在采集线程完成转换，主线程只负责绘制
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(cgImage, CGSize(width: width, height: height))
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 帧丢弃属正常现象（处理跟不上时自动丢帧），无需处理
    }
}
