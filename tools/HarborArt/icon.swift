import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024x1024 App Store icon, drawn in the chart palette.
//
// Opaque by construction: CGImageAlphaInfo.noneSkipLast, never premultiplied
// alpha. A 1024 icon with an alpha channel is an upload rejection, and the
// AppIcon set here uses the single-size `universal` format, which auto-generates
// every other size — do not "fix" it into an ios-marketing-only set, which is
// what produces the "missing 120x120" reject.

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: size * 4,
                          space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create the bitmap context")
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1])!
}

let chartDeep = rgb(0x0C, 0x20, 0x33)
let chartGrid = rgb(0x16, 0x34, 0x4B)
let contour   = rgb(0x2F, 0x6C, 0x86)
let cyan      = rgb(0x5F, 0xD0, 0xE8)
let hullFill  = rgb(0x12, 0x3A, 0x52)
let gold      = rgb(0xF2, 0xC8, 0x40)

let s = CGFloat(size)

ctx.setFillColor(chartDeep)
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

// Chart grid.
ctx.setStrokeColor(chartGrid)
ctx.setLineWidth(3)
for i in 1..<8 {
    let t = s * CGFloat(i) / 8
    ctx.move(to: CGPoint(x: 0, y: t)); ctx.addLine(to: CGPoint(x: s, y: t))
    ctx.move(to: CGPoint(x: t, y: 0)); ctx.addLine(to: CGPoint(x: t, y: s))
}
ctx.strokePath()

// Depth contours.
ctx.setStrokeColor(contour)
ctx.setLineWidth(6)
for (i, y) in [0.30, 0.44, 0.58].enumerated() {
    let base = s * CGFloat(y)
    ctx.move(to: CGPoint(x: 0, y: base))
    ctx.addCurve(to: CGPoint(x: s, y: base + s * 0.04),
                 control1: CGPoint(x: s * 0.35, y: base - s * 0.09 - CGFloat(i) * 8),
                 control2: CGPoint(x: s * 0.68, y: base + s * 0.12))
    ctx.strokePath()
}

// Quay wall across the lower third.
ctx.setFillColor(gold)
ctx.fill(CGRect(x: 0, y: s * 0.20, width: s, height: s * 0.035))
ctx.setFillColor(chartGrid)
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.20))

// Bollards along the quay.
ctx.setFillColor(contour)
for i in 0..<5 {
    let x = s * (0.12 + 0.19 * CGFloat(i))
    ctx.fillEllipse(in: CGRect(x: x - 14, y: s * 0.155, width: 28, height: 28))
}

// Hull, bow to the right, sitting on the quay edge.
let hy = s * 0.30, hh = s * 0.20
let hx = s * 0.13, hw = s * 0.70
let bow = hx + hw - s * 0.13
ctx.beginPath()
ctx.move(to: CGPoint(x: hx + 26, y: hy + hh))
ctx.addLine(to: CGPoint(x: bow, y: hy + hh))
ctx.addQuadCurve(to: CGPoint(x: hx + hw, y: hy + hh / 2), control: CGPoint(x: bow + s * 0.10, y: hy + hh))
ctx.addQuadCurve(to: CGPoint(x: bow, y: hy), control: CGPoint(x: bow + s * 0.10, y: hy))
ctx.addLine(to: CGPoint(x: hx + 26, y: hy))
ctx.addQuadCurve(to: CGPoint(x: hx, y: hy + hh / 2), control: CGPoint(x: hx - 18, y: hy + hh / 2))
ctx.closePath()
ctx.setFillColor(hullFill)
ctx.fillPath()

ctx.beginPath()
ctx.move(to: CGPoint(x: hx + 26, y: hy + hh))
ctx.addLine(to: CGPoint(x: bow, y: hy + hh))
ctx.addQuadCurve(to: CGPoint(x: hx + hw, y: hy + hh / 2), control: CGPoint(x: bow + s * 0.10, y: hy + hh))
ctx.addQuadCurve(to: CGPoint(x: bow, y: hy), control: CGPoint(x: bow + s * 0.10, y: hy))
ctx.addLine(to: CGPoint(x: hx + 26, y: hy))
ctx.addQuadCurve(to: CGPoint(x: hx, y: hy + hh / 2), control: CGPoint(x: hx - 18, y: hy + hh / 2))
ctx.closePath()
ctx.setStrokeColor(cyan)
ctx.setLineWidth(16)
ctx.strokePath()

// Deck cells.
ctx.setStrokeColor(contour)
ctx.setLineWidth(10)
for i in 0..<3 {
    let cx = hx + s * (0.07 + 0.15 * CGFloat(i))
    ctx.stroke(CGRect(x: cx, y: hy + hh * 0.28, width: s * 0.11, height: hh * 0.44))
}

// Gold star, upper left.
func star(cx: CGFloat, cy: CGFloat, r: CGFloat) {
    ctx.beginPath()
    for i in 0..<10 {
        let ang = Double(i) * .pi / 5 - .pi / 2
        let rr = i % 2 == 0 ? r : r * 0.42
        let p = CGPoint(x: cx + CGFloat(cos(ang)) * rr, y: cy + CGFloat(sin(ang)) * rr)
        if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
    }
    ctx.closePath()
    ctx.setFillColor(gold)
    ctx.fillPath()
}
star(cx: s * 0.20, cy: s * 0.80, r: s * 0.085)

// Buoys.
ctx.setFillColor(rgb(0xC6, 0x45, 0x3D))
ctx.fill(CGRect(x: s * 0.72, y: s * 0.72, width: s * 0.05, height: s * 0.07))
ctx.setFillColor(rgb(0x3E, 0x8C, 0x74))
ctx.beginPath()
ctx.move(to: CGPoint(x: s * 0.86, y: s * 0.83))
ctx.addLine(to: CGPoint(x: s * 0.90, y: s * 0.72))
ctx.addLine(to: CGPoint(x: s * 0.82, y: s * 0.72))
ctx.closePath()
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("could not render the icon") }
let out = URL(fileURLWithPath: "Quaylock/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not create the PNG destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write the PNG") }
print("wrote \(out.path)")
