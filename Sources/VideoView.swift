import AppKit

/// 视频显示 + 叠加绘制视图。
/// 叠加图形以「相机像素」为语义单位（与原版一致），按 显示视频宽度/相机像素宽度 等比缩放绘制，
/// 保证同一份 config 在不同窗口尺寸下对应的物理位置一致。
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

    override var acceptsFirstMouse: Bool { true }
    override var isFlipped: Bool { false }  // 使用 CG 的 y 向上坐标系

    /// 当前视频内容在视图中的显示矩形（aspect-fit）
    private func videoRect(in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        guard let image = frameImage else {
            drawPlaceholder(in: context)
            return
        }

        let rect = videoRect(in: bounds)
        guard rect.width > 0 else { return }

        // 视频（关闭平滑插值，保持像素锐利，便于校准观察）
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        context.interpolationQuality = .medium

        drawOverlays(context: context, videoRect: rect)
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

        // 相机像素 → 屏幕像素 缩放
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
}
