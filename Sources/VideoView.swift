import AppKit

/// 视频显示 + 叠加绘制视图。
/// 叠加图形以「相机像素」为语义单位（与原版一致），按 显示视频宽度/相机像素宽度 等比缩放绘制，
/// 保证同一份 config 在不同窗口尺寸下对应的物理位置一致。
///
/// 缩放（校准镜子小时放大观察）：
/// - ⌘+ / ⌘- 放大缩小，⌘0 复位（菜单命令，亦响应触控板手势）
/// - 触控板双指捏合缩放；缩放后可拖拽平移；双击复位
/// - 缩放锚点 = 当前叠加圆心，放大时十字准星保持在画面中央
final class VideoView: NSView {

    var frameImage: CGImage? {
        didSet { needsDisplay = true }
    }

    /// 相机输出像素尺寸（帧到达时更新）
    var imageSize: CGSize = CGSize(width: 3264, height: 2448) {
        didSet { needsDisplay = true }
    }

    var settings = Settings() {
        didSet { needsDisplay = true }
    }

    // MARK: 缩放与平移

    static let zoomRange: ClosedRange<CGFloat> = 1...12

    var zoom: CGFloat = 1 {
        didSet {
            let clamped = max(Self.zoomRange.lowerBound, min(Self.zoomRange.upperBound, zoom))
            if clamped != zoom { zoom = clamped; return }
            if zoom == Self.zoomRange.lowerBound { panOffset = .zero }
            NSLog("zoom = %.2f", zoom)
            needsDisplay = true
        }
    }

    var panOffset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    private var isDragging = false
    private var dragStart: CGPoint = .zero
    private var panStart: CGPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // 使用默认的 y 向上坐标系（与 CG 一致）

    // MARK: - 几何

    /// aspect-fit 后的视频矩形（未缩放）
    private func videoRect(in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    /// 当前叠加圆心在给定视频矩形中的位置（视图坐标）
    private func overlayCenter(in rect: NSRect) -> CGPoint {
        let scale = rect.width / CGFloat(max(imageSize.width, 1))
        return CGPoint(
            x: rect.midX + CGFloat(settings.offset.horizontal) * scale,
            y: rect.midY - CGFloat(settings.offset.vertical) * scale)
    }

    /// 实际显示矩形 = fit 矩形绕圆心缩放 + 平移
    private func displayRect(in bounds: NSRect) -> NSRect {
        let fit = videoRect(in: bounds)
        guard zoom != 1 || panOffset != .zero, fit.width > 0 else { return fit }
        let anchor = overlayCenter(in: fit)
        let w = fit.width * zoom
        let h = fit.height * zoom
        let x = anchor.x - (anchor.x - fit.origin.x) * zoom + panOffset.x
        let y = anchor.y - (anchor.y - fit.origin.y) * zoom + panOffset.y
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        guard let image = frameImage else {
            drawPlaceholder(in: context)
            return
        }

        let rect = displayRect(in: bounds)
        guard rect.width > 0 else { return }

        // 视频（关闭平滑插值，保持像素锐利，便于校准观察）
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        context.interpolationQuality = .medium

        drawOverlays(context: context, videoRect: rect)
        drawZoomHUD(context: context)
    }

    private func drawPlaceholder(in context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let text = "未开启摄像头 — 点击左侧「开启摄像头」"
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }

    private func drawOverlays(context: CGContext, videoRect: NSRect) {
        let s = settings
        guard s.offset.enabled || s.circle1.enabled || s.circle2.enabled || s.circle3.enabled || s.cross.enabled else { return }

        // 相机像素 → 屏幕像素 缩放（含缩放倍率）
        let scale = videoRect.width / CGFloat(max(imageSize.width, 1))

        // 圆心：视频中心 + 偏移（上下正值 = 向下 = 屏幕坐标 y 减小）
        let cx = videoRect.midX + CGFloat(s.offset.horizontal) * scale
        let cy = videoRect.midY - CGFloat(s.offset.vertical) * scale

        // 三个校准圆
        for circle in [s.circle1, s.circle2, s.circle3] where circle.enabled && circle.radius > 0 {
            let r = CGFloat(circle.radius) * scale
            let lineW = max(1.0, CGFloat(circle.thickness) * scale)
            context.setStrokeColor(circle.color.cgColor)
            context.setLineWidth(lineW)
            context.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }

        // 准星：两条过圆心的正交直线，整体旋转 angle 度（0° = 横平竖直）
        if s.cross.enabled && s.cross.length > 0 {
            let half = CGFloat(s.cross.length) / 2 * scale
            let lineW = max(1.0, CGFloat(s.cross.thickness) * scale)
            let theta = CGFloat(s.cross.angle) * .pi / 180
            let dx = half * cos(theta)
            let dy = half * sin(theta)
            let px = half * cos(theta + .pi / 2)
            let py = half * sin(theta + .pi / 2)

            context.setStrokeColor(s.cross.color.cgColor)
            context.setLineWidth(lineW)
            context.setLineCap(.butt)
            context.move(to: CGPoint(x: cx - dx, y: cy - dy))
            context.addLine(to: CGPoint(x: cx + dx, y: cy + dy))
            context.move(to: CGPoint(x: cx - px, y: cy - py))
            context.addLine(to: CGPoint(x: cx + px, y: cy + py))
            context.strokePath()
        }
    }

    private func drawZoomHUD(context: CGContext) {
        guard zoom != 1 || panOffset != .zero else { return }
        let text = String(format: "%d%%", Int((zoom * 100).rounded()))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
        ]
        let size = text.size(withAttributes: attributes)
        let pt = NSPoint(x: bounds.maxX - size.width - 10, y: bounds.maxY - size.height - 8)
        text.draw(at: pt, withAttributes: attributes)
    }

    // MARK: - 缩放命令（菜单/快捷键 ⌘+ ⌘- ⌘0）

    @objc func zoomIn(_ sender: Any?) {
        zoom *= 1.25
    }

    @objc func zoomOut(_ sender: Any?) {
        zoom /= 1.25
    }

    @objc func zoomReset(_ sender: Any?) {
        zoom = 1
        panOffset = .zero
    }

    // MARK: - 鼠标/触控板

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            // ⌘/⌥ + 滚轮缩放
            if event.scrollingDeltaY != 0 {
                zoom *= event.scrollingDeltaY > 0 ? 1.1 : 1 / 1.1
            }
        } else if zoom > 1 {
            // 已放大时滚轮平移（视图坐标 y 向上，滚轮向上 = 内容上移）
            panOffset.x += event.scrollingDeltaX
            panOffset.y += event.scrollingDeltaY
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom *= 1 + event.magnification
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            zoomReset(nil)
            return
        }
        isDragging = true
        dragStart = convert(event.locationInWindow, from: nil)
        panStart = panOffset
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        panOffset = CGPoint(x: panStart.x + (p.x - dragStart.x),
                            y: panStart.y + (p.y - dragStart.y))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
