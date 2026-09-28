// Vẽ icon app → Resources/AppIcon.icns
//   swift scripts/make-icon.swift
// Hai bong bóng chat: "A" được bôi vàng (đoạn text đang chọn) → "Ă" (tiếng Việt).
import AppKit

let size: CGFloat = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Bong bóng chat = rounded rect + đuôi nhọn ở góc dưới (trái hoặc phải).
/// Fill 2 phần riêng trong 1 transparency layer để bóng đổ không bị chồng.
func fillBubble(_ r: CGRect, radius: CGFloat, tailLeft: Bool, color: NSColor, shadow: NSShadow) {
    let ctx = NSGraphicsContext.current!.cgContext
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    color.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    let tail = NSBezierPath()
    let dir: CGFloat = tailLeft ? 1 : -1
    let x0 = tailLeft ? r.minX : r.maxX
    tail.move(to: CGPoint(x: x0 + dir * 70, y: r.minY + 40))
    tail.line(to: CGPoint(x: x0 + dir * 30, y: r.minY - 55))
    tail.line(to: CGPoint(x: x0 + dir * 170, y: r.minY))
    tail.close()
    tail.fill()
    ctx.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
}

func drawText(_ s: String, center: CGPoint, fontSize: CGFloat, color: NSColor) {
    let base = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let b = str.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
    // Căn giữa theo cap height để chữ có dấu vẫn cân.
    let y = center.y - (font.capHeight / 2) + font.descender
    str.draw(at: CGPoint(x: center.x - b.width / 2, y: y))
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Nền squircle theo lưới icon macOS (824pt, bo 185) + bóng đổ nhẹ.
let plate = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = CGSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
color(0x4F46E5).setFill()
plate.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(0x38BDF8), color(0x6366F1), color(0x9333EA)])!.draw(in: plate, angle: -60)

// Bong bóng sau: "A" với vệt bôi vàng như text đang được chọn.
let back = CGRect(x: 180, y: 470, width: 440, height: 330)
let soft = NSShadow()
soft.shadowColor = NSColor.black.withAlphaComponent(0.18)
soft.shadowOffset = CGSize(width: 0, height: -8)
soft.shadowBlurRadius = 24
fillBubble(back, radius: 100, tailLeft: true, color: color(0xEEF2FF), shadow: soft)
color(0xFACC15).setFill()
NSBezierPath(roundedRect: CGRect(x: 265, y: 560, width: 190, height: 190), xRadius: 26, yRadius: 26).fill()
drawText("A", center: CGPoint(x: 360, y: 655), fontSize: 200, color: color(0x1E1B4B))

// Bong bóng trước: "Ă" — bản dịch tiếng Việt.
let front = CGRect(x: 420, y: 220, width: 420, height: 330)
let drop = NSShadow()
drop.shadowColor = NSColor.black.withAlphaComponent(0.3)
drop.shadowOffset = CGSize(width: 0, height: -14)
drop.shadowBlurRadius = 30
fillBubble(front, radius: 100, tailLeft: false, color: .white, shadow: drop)
drawText("Ă", center: CGPoint(x: 630, y: 370), fontSize: 210, color: color(0x6D28D9))

NSGraphicsContext.restoreGraphicsState()

// Xuất iconset → icns.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let img = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: img)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: CGRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        try! img.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil failed")
