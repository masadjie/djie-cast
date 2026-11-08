import AppKit

// Djie Cast icon: a phone on an indigo→cyan squircle with cast waves.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1),
                    NSColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1)])!.draw(in: bg, angle: -45)

// Phone body
let phone = NSRect(x: 300, y: 240, width: 300, height: 540)
NSColor.white.setFill()
NSBezierPath(roundedRect: phone, xRadius: 56, yRadius: 56).fill()
// Screen
NSColor(red: 0.20, green: 0.22, blue: 0.55, alpha: 1).setFill()
NSBezierPath(roundedRect: phone.insetBy(dx: 26, dy: 34), xRadius: 32, yRadius: 32).fill()
// "D" monogram on the screen
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 260, weight: .black),
    .foregroundColor: NSColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 1),
    .paragraphStyle: para,
]
("D" as NSString).draw(in: NSRect(x: phone.minX, y: phone.midY - 170, width: phone.width, height: 320), withAttributes: attrs)

// Cast waves from the top-right corner of the phone
NSColor.white.setStroke()
let center = NSPoint(x: 600, y: 600)
for (i, r) in [CGFloat(90), 170, 250].enumerated() {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: r, startAngle: 5, endAngle: 85)
    arc.lineWidth = 46
    arc.lineCapStyle = .round
    NSColor.white.withAlphaComponent(1 - CGFloat(i) * 0.22).setStroke()
    arc.stroke()
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
