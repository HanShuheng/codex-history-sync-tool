import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("用法：dmg_background.swift <输出 PNG>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 900, height: 600)
let image = NSImage(size: size)
image.lockFocus()

NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

func drawCentered(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: y), withAttributes: attributes)
}

drawCentered(
    "CodexHistorySync",
    y: 465,
    attributes: [
        .font: NSFont.systemFont(ofSize: 54, weight: .bold),
        .foregroundColor: NSColor.black
    ]
)
drawCentered(
    "恢复 / 管理 / 同步",
    y: 410,
    attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)
    ]
)

NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 250, y: 270))
arrow.curve(
    to: NSPoint(x: 650, y: 270),
    controlPoint1: NSPoint(x: 360, y: 360),
    controlPoint2: NSPoint(x: 500, y: 180)
)
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 650, y: 270))
arrowHead.line(to: NSPoint(x: 620, y: 290))
arrowHead.move(to: NSPoint(x: 650, y: 270))
arrowHead.line(to: NSPoint(x: 615, y: 260))
arrowHead.lineWidth = 6
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

NSColor(calibratedRed: 0.05, green: 0.68, blue: 0.85, alpha: 0.9).setFill()
let accent = NSBezierPath()
accent.move(to: NSPoint(x: 95, y: 330))
accent.line(to: NSPoint(x: 125, y: 345))
accent.line(to: NSPoint(x: 110, y: 310))
accent.close()
accent.fill()

image.unlockFocus()
if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try! png.write(to: outputURL)
}
