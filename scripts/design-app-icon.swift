import AppKit

let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func gradient(_ colors: [NSColor], from start: NSPoint, to end: NSPoint) {
    NSGradient(colors: colors)!.draw(from: start, to: end, options: [])
}

context.saveGState()
let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 194)
tile.addClip()
gradient([color(0x12305C), color(0x285DC0), color(0x3199CE)],
         from: NSPoint(x: 130, y: 130), to: NSPoint(x: 850, y: 930))
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 30,
                  color: color(0x07152E, alpha: 0.35).cgColor)
color(0xF4F9FF).setFill()
rounded(NSRect(x: 225, y: 245, width: 574, height: 526), 66).fill()
context.restoreGState()

context.saveGState()
rounded(NSRect(x: 248, y: 268, width: 528, height: 480), 46).addClip()
gradient([color(0x255CB3), color(0x54B9D4)],
         from: NSPoint(x: 300, y: 250), to: NSPoint(x: 730, y: 760))
color(0xFFFFFF, alpha: 0.94).setFill()
NSBezierPath(ovalIn: NSRect(x: 572, y: 575, width: 88, height: 88)).fill()
let mountain = NSBezierPath()
mountain.move(to: NSPoint(x: 240, y: 260))
mountain.line(to: NSPoint(x: 240, y: 353))
mountain.line(to: NSPoint(x: 400, y: 536))
mountain.curve(to: NSPoint(x: 462, y: 538), controlPoint1: NSPoint(x: 417, y: 555), controlPoint2: NSPoint(x: 444, y: 556))
mountain.line(to: NSPoint(x: 640, y: 344))
mountain.line(to: NSPoint(x: 690, y: 398))
mountain.curve(to: NSPoint(x: 737, y: 399), controlPoint1: NSPoint(x: 703, y: 412), controlPoint2: NSPoint(x: 724, y: 412))
mountain.line(to: NSPoint(x: 790, y: 346))
mountain.line(to: NSPoint(x: 790, y: 260))
mountain.close()
color(0x0D336A, alpha: 0.90).setFill()
mountain.fill()
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
