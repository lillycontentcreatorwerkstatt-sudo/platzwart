// Zeichnet das App-Icon (Ordner mit Füllstandsanzeige) als 1024×1024-PNG.
// Aufruf: swift scripts/make-icon.swift <ziel.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Hintergrund: abgerundetes Quadrat nach Apples Icon-Raster (824 pt Fläche, 100 pt Rand)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0, 0, 0, 0.30)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSGradient(starting: color(58, 134, 255), ending: color(24, 64, 168))!.draw(in: tilePath, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Ordner: Reiter + Körper
let folderColor = color(246, 248, 252)
folderColor.setFill()
NSBezierPath(roundedRect: NSRect(x: 232, y: 560, width: 250, height: 120), xRadius: 34, yRadius: 34).fill()
let body = NSBezierPath(roundedRect: NSRect(x: 232, y: 262, width: 560, height: 360), xRadius: 44, yRadius: 44)
body.fill()

// Füllstandsanzeige auf dem Ordner
let center = NSPoint(x: 512, y: 360)
let radius: CGFloat = 165

func arc(from start: CGFloat, to end: CGFloat, color strokeColor: NSColor, round: Bool = true) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    path.lineWidth = 48
    path.lineCapStyle = round ? .round : .butt
    strokeColor.setStroke()
    path.stroke()
}

arc(from: 180, to: 0, color: color(218, 226, 240))          // Spur
arc(from: 180, to: 115, color: color(52, 199, 89))          // grün
arc(from: 115, to: 65, color: color(255, 179, 64), round: false) // orange

// Nadel
let needleAngle: CGFloat = 70 * .pi / 180
let tip = NSPoint(x: center.x + cos(needleAngle) * 150, y: center.y + sin(needleAngle) * 150)
let needle = NSBezierPath()
needle.move(to: center)
needle.line(to: tip)
needle.lineWidth = 26
needle.lineCapStyle = .round
color(24, 64, 168).setStroke()
needle.stroke()
color(24, 64, 168).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Icon gespeichert: \(output)")
