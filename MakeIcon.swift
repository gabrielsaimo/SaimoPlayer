import AppKit
import Foundation

// Draws the app icon at 1024pt and writes a PNG. Rendered rather than shipped
// as an asset so it stays crisp at every icns size.

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

func squircle(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// Plate
let plateRect = NSRect(x: 74, y: 74, width: size - 148, height: size - 148)
let plate = squircle(plateRect, radius: 210)
NSColor(calibratedRed: 0.957, green: 0.965, blue: 0.976, alpha: 1).setFill()
plate.fill()

// Screen
let screenOuter = NSRect(x: 250, y: 470, width: 524, height: 340)
let screenPath = squircle(screenOuter, radius: 44)
NSGradient(colors: [
    NSColor(calibratedRed: 0.290, green: 0.878, blue: 0.784, alpha: 1),
    NSColor(calibratedRed: 0.404, green: 0.353, blue: 0.855, alpha: 1),
])?.draw(in: screenPath, angle: -35)

let screenInner = screenOuter.insetBy(dx: 26, dy: 26)
let innerPath = squircle(screenInner, radius: 26)
NSGradient(colors: [
    NSColor(calibratedRed: 0.114, green: 0.153, blue: 0.443, alpha: 1),
    NSColor(calibratedRed: 0.180, green: 0.212, blue: 0.545, alpha: 1),
])?.draw(in: innerPath, angle: -60)

// Antenna
let antenna = NSBezierPath()
antenna.move(to: NSPoint(x: 404, y: 810))
antenna.line(to: NSPoint(x: 352, y: 902))
antenna.lineWidth = 14
antenna.lineCapStyle = .round
NSColor(calibratedRed: 0.157, green: 0.208, blue: 0.478, alpha: 1).setStroke()
antenna.stroke()
NSColor(calibratedRed: 0.157, green: 0.208, blue: 0.478, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 334, y: 892, width: 32, height: 32)).fill()

// The S sweeping across the screen
let swoosh = NSBezierPath()
swoosh.move(to: NSPoint(x: 545, y: 878))
swoosh.curve(to: NSPoint(x: 402, y: 700),
             controlPoint1: NSPoint(x: 430, y: 872),
             controlPoint2: NSPoint(x: 392, y: 790))
swoosh.curve(to: NSPoint(x: 596, y: 596),
             controlPoint1: NSPoint(x: 414, y: 620),
             controlPoint2: NSPoint(x: 596, y: 660))
swoosh.curve(to: NSPoint(x: 470, y: 428),
             controlPoint1: NSPoint(x: 596, y: 534),
             controlPoint2: NSPoint(x: 520, y: 448))
swoosh.lineWidth = 62
swoosh.lineCapStyle = .round
swoosh.lineJoinStyle = .round

// Stroke it into a fillable outline so the gradient runs along the ribbon.
ctx.saveGState()
let ribbon = swoosh.cgPath.copy(strokingWithWidth: 62, lineCap: .round,
                                lineJoin: .round, miterLimit: 10)
ctx.addPath(ribbon)
ctx.clip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.290, green: 0.878, blue: 0.784, alpha: 1),
    NSColor(calibratedRed: 0.427, green: 0.365, blue: 0.898, alpha: 1),
    NSColor(calibratedRed: 0.847, green: 0.325, blue: 0.847, alpha: 1),
])?.draw(in: NSRect(x: 360, y: 396, width: 280, height: 512), angle: -80)
ctx.restoreGState()

// Play triangle
let play = NSBezierPath()
play.move(to: NSPoint(x: 494, y: 690))
play.line(to: NSPoint(x: 594, y: 638))
play.line(to: NSPoint(x: 494, y: 586))
play.close()
NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
play.fill()

// Wordmark
let navy = NSColor(calibratedRed: 0.106, green: 0.176, blue: 0.365, alpha: 1)
func roundedFont(_ pointSize: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: pointSize) {
        return font
    }
    return base
}

let title = NSAttributedString(string: "Saimo", attributes: [
    .font: roundedFont(196, weight: .bold),
    .foregroundColor: navy,
])
let titleSize = title.size()
title.draw(at: NSPoint(x: (size - titleSize.width) / 2 - 14, y: 232))

let sub = NSAttributedString(string: "TV", attributes: [
    .font: roundedFont(104, weight: .semibold),
    .foregroundColor: navy,
])
let subSize = sub.size()
sub.draw(at: NSPoint(x: (size + titleSize.width) / 2 - subSize.width - 20, y: 150))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: out))
print("gerado: \(out)")
