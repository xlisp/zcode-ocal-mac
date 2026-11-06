import AppKit

// MARK: - 叠加设置数据模型
// 与 Windows 版 OCAL1.32 的 config{720,1080,1k,4k}.txt 完全兼容：
//   前 11 个整数 = 圈1半径 圈1启用 圈2半径 圈2启用 圈3半径 圈3启用 准星长度 准星启用 角度 上下偏移 左右偏移
//   追加的 12 个整数 = 4 组 RGB 颜色（Mac 版增强，原版读取固定字段数不受影响）

struct CircleConfig {
    var enabled = true
    var color = NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1)
    var radius = 150
    var thickness = 2
}

struct CrossConfig {
    var enabled = true
    var color = NSColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 1)
    var length = 100
    var thickness = 2
    var angle = 0
}

struct OffsetConfig {
    var enabled = false
    var vertical = 0    // 上下（正 = 向下，图像坐标）
    var horizontal = 0  // 左右（正 = 向右）
}

struct Settings {
    var circle1 = CircleConfig()
    var circle2 = CircleConfig(color: NSColor(red: 0.0, green: 0.85, blue: 0.0, alpha: 1), radius: 100)
    var circle3 = CircleConfig(color: NSColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1), radius: 50)
    var cross = CrossConfig()
    var offset = OffsetConfig()
    var profile = "4k"
}

extension NSColor {
    /// 0-255 整数三元组
    var rgbInts: [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())]
    }

    static func fromRGBInts(_ ints: [Int]) -> NSColor {
        func v(_ i: Int) -> CGFloat { CGFloat(max(0, min(255, i))) / 255.0 }
        return NSColor(red: v(ints.count > 0 ? ints[0] : 0),
                       green: v(ints.count > 1 ? ints[1] : 0),
                       blue: v(ints.count > 2 ? ints[2] : 0),
                       alpha: 1)
    }
}

extension Settings {

    /// 解析原版/Mac 版配置行。兼容原版 11 个整数，也兼容追加颜色后的 23 个。
    static func parse(_ text: String, profile: String) -> Settings? {
        let tokens = text.split(whereSeparator: { c in c == " " || c == "\t" || c == "\n" || c == "\r" })
            .map(String.init)
        var ints = [Int]()
        for t in tokens {
            if let i = Int(t) { ints.append(i) }
            else if let d = Double(t) { ints.append(Int(d.rounded())) }  // 容错
            else { break }
        }
        guard ints.count >= 11 else { return nil }

        var s = Settings()
        s.profile = profile
        s.circle1.radius = max(0, ints[0])
        s.circle1.enabled = ints[1] != 0
        s.circle2.radius = max(0, ints[2])
        s.circle2.enabled = ints[3] != 0
        s.circle3.radius = max(0, ints[4])
        s.circle3.enabled = ints[5] != 0
        s.cross.length = max(0, ints[6])
        s.cross.enabled = ints[7] != 0
        s.cross.angle = ints[8]
        s.offset.vertical = ints[9]
        s.offset.horizontal = ints[10]
        // Mac 版追加的颜色（可能不存在）
        if ints.count >= 23 {
            s.circle1.color = NSColor.fromRGBInts(Array(ints[11...13]))
            s.circle2.color = NSColor.fromRGBInts(Array(ints[14...16]))
            s.circle3.color = NSColor.fromRGBInts(Array(ints[17...19]))
            s.cross.color = NSColor.fromRGBInts(Array(ints[20...22]))
        }
        return s
    }

    /// 序列化。前 11 个字段与原版格式一致，颜色追加在行尾。
    func serialized() -> String {
        var parts: [String] = []
        parts.append("\(circle1.radius) \(circle1.enabled ? 1 : 0)")
        parts.append("\(circle2.radius) \(circle2.enabled ? 1 : 0)")
        parts.append("\(circle3.radius) \(circle3.enabled ? 1 : 0)")
        parts.append("\(cross.length) \(cross.enabled ? 1 : 0)")
        parts.append("\(cross.angle)")
        parts.append("\(offset.vertical) \(offset.horizontal)")
        parts.append((circle1.color.rgbInts + circle2.color.rgbInts + circle3.color.rgbInts + cross.color.rgbInts)
            .map(String.init).joined(separator: " "))
        return parts.joined(separator: " ")
    }
}

// MARK: - 定心编码坐标（focus.txt）
// 每台设备唯一的圆心标定数据：坐标在记录分辨率下测量，换算到当前相机分辨率后
// 作为叠加圆心（偏移滑杆在其上做微调）。

struct FocusCalibration {
    var center: CGPoint       // 记录分辨率下的像素坐标
    var reference: CGSize?    // 记录时的相机分辨率（旧格式文件无此信息，为 nil）
}

extension FocusCalibration {

    /// 换算到当前相机分辨率下的圆心。
    /// 旧格式（无记录分辨率）：坐标若落在当前分辨率内则视为当前分辨率坐标；
    /// 否则按 4K 满幅（3264×2448，原版工具对应的相机）折算。
    func scaledCenter(forResolution size: CGSize) -> CGPoint {
        let ref: CGSize
        if let r = reference {
            ref = r
        } else if center.x >= 0, center.x <= size.width, center.y >= 0, center.y <= size.height {
            ref = size
        } else {
            ref = CGSize(width: 3264, height: 2448)
        }
        guard ref.width > 0, ref.height > 0 else { return center }
        return CGPoint(x: center.x * size.width / ref.width,
                       y: center.y * size.height / ref.height)
    }
}

// MARK: - 配置存取
// 优先「便携模式」：若 OCAL.app 同级目录存在 config*.txt（比如直接放进原版 ocal-win 目录），
// 则直接读写该目录，与原版「配置在 exe 旁」的行为一致；否则用 ~/Library/Application Support/OCAL/

enum ConfigStore {

    static var portableDirectory: URL? {
        guard let besideApp = Bundle.main.bundleURL.deletingLastPathComponent() as URL? else { return nil }
        let dir = besideApp.path
        let names = ["config720.txt", "config1080.txt", "config1k.txt", "config4k.txt", "focus.txt"]
        guard names.contains(where: { FileManager.default.isReadableFile(atPath: dir + "/" + $0) }) else { return nil }
        return besideApp
    }

    static var directory: URL {
        if let portable = portableDirectory { return portable }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("OCAL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var isPortable: Bool { portableDirectory != nil }

    static func configURL(profile: String) -> URL {
        directory.appendingPathComponent("config\(profile).txt")
    }

    static var focusURL: URL {
        directory.appendingPathComponent("focus.txt")
    }

    /// 读取指定档案；不存在则返回默认值（数值取原版默认风格）
    static func load(profile: String) -> Settings {
        let url = configURL(profile: profile)
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let s = Settings.parse(text, profile: profile) {
            return s
        }
        var s = Settings()
        s.profile = profile
        // 与原版 config1k.txt 的默认数值一致
        s.circle1.radius = 150
        s.circle2.radius = 100
        s.circle3.radius = 50
        s.cross.length = 100
        s.cross.angle = 0
        s.offset.vertical = 0
        s.offset.horizontal = 0
        return s
    }

    static func save(_ settings: Settings) {
        let url = configURL(profile: settings.profile)
        try? settings.serialized().write(to: url, atomically: true, encoding: .utf8)
    }

    /// focus.txt 格式（原版）：`0 0 <cx> <cy>`，cx/cy 为**定心编码坐标**——
    /// 每台设备唯一，在该设备相机满幅分辨率下标定（例：3264×2448 相机 → 1616.83, 1172.13）。
    /// Mac 版扩展格式在其后追加记录分辨率：`0 0 <cx> <cy> <refW> <refH>`（原版按固定字段数读取，兼容）。
    static func loadFocus() -> FocusCalibration? {
        guard let text = try? String(contentsOf: focusURL, encoding: .utf8) else { return nil }
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        guard tokens.count >= 4,
              let x = Double(tokens[2]), let y = Double(tokens[3]) else { return nil }
        var ref: CGSize? = nil
        if tokens.count >= 6, let w = Double(tokens[4]), let h = Double(tokens[5]), w > 0, h > 0 {
            ref = CGSize(width: w, height: h)
        }
        return FocusCalibration(center: CGPoint(x: x, y: y), reference: ref)
    }

    static func saveFocus(_ focus: FocusCalibration) {
        var text = String(format: "0 0 %.2f %.2f", focus.center.x, focus.center.y)
        if let ref = focus.reference {
            text += String(format: " %.0f %.0f", ref.width, ref.height)
        }
        try? text.write(to: focusURL, atomically: true, encoding: .utf8)
    }

    /// 按相机分辨率自动选档案（720p / 1k / 1080p / 4k）
    static func profile(forResolution size: CGSize) -> String {
        let w = Int(size.width), h = Int(size.height)
        if h <= 720 { return "720" }
        if h <= 768 || (w <= 1280 && h <= 1024) { return "1k" }
        if h <= 1080 { return "1080" }
        return "4k"
    }
}
