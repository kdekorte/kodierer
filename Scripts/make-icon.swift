// make-icon.swift — renders the Kodierer app icon (1024×1024 PNG).
// Usage: swift Scripts/make-icon.swift [output.png]
//
// Design: dark navy→blue gradient, BMW-style roundel (blue/white quadrants,
// dark ring), with bold `</>` code brackets across it — "the coder" for BMWs.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Apps/Assets.xcassets/AppIcon.appiconset/icon1024.png"

// Create the output directory if missing so the first run just works.
try FileManager.default.createDirectory(
    atPath: (outPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true)

let s = CGFloat(size)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: Background: vertical gradient dark navy → BMW blue
let bg = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(srgbRed: 0.043, green: 0.098, blue: 0.204, alpha: 1), // #0B1934
    CGColor(srgbRed: 0.075, green: 0.243, blue: 0.510, alpha: 1), // #133E82
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// Subtle radial glow behind the roundel
let glow = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 0.35),
    CGColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: s/2, y: s/2), startRadius: 0,
                       endCenter: CGPoint(x: s/2, y: s/2), endRadius: s * 0.42,
                       options: [])

// MARK: Roundel
let center = CGPoint(x: s/2, y: s/2)
let outerR = s * 0.335
// Dark outer ring
ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - outerR, y: center.y - outerR,
                           width: outerR * 2, height: outerR * 2))
// Thin silver ring on its inner edge
let ringW = s * 0.045
ctx.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.80, blue: 0.83, alpha: 1))
ctx.setLineWidth(ringW)
let innerR = outerR - ringW * 1.15
ctx.strokeEllipse(in: CGRect(x: center.x - innerR, y: center.y - innerR,
                             width: innerR * 2, height: innerR * 2))
// Blue / white quadrants
let q = innerR - ringW * 0.9
let bmwBlue = CGColor(srgbRed: 0.075, green: 0.392, blue: 0.761, alpha: 1) // #1364C2
let white = CGColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
let r = CGRect(x: center.x - q, y: center.y - q, width: q * 2, height: q * 2)
func wedge(_ start: CGFloat, _ end: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.move(to: center)
    ctx.addArc(center: center, radius: q, startAngle: start, endAngle: end, clockwise: false)
    ctx.addLine(to: center)
    ctx.fillPath()
}
wedge(.pi / 2, .pi, bmwBlue)          // top-left  (quadrant II)
wedge(.pi, .pi * 1.5, white)          // bottom-left
wedge(.pi * 1.5, .pi * 2, bmwBlue)    // bottom-right
wedge(0, .pi / 2, white)              // top-right
// Thin separators between quadrants
ctx.setStrokeColor(CGColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1))
ctx.setLineWidth(s * 0.008)
ctx.beginPath(); ctx.move(to: CGPoint(x: center.x - q, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + q, y: center.y)); ctx.strokePath()
ctx.beginPath(); ctx.move(to: CGPoint(x: center.x, y: center.y - q)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + q)); ctx.strokePath()

// MARK: `</>` brackets — the coding identity, drawn over the roundel
// Drawn as thick strokes so they stay crisp at small sizes.
let accent = CGColor(srgbRed: 0.20, green: 0.93, blue: 0.55, alpha: 1) // #4AED8C
ctx.setStrokeColor(accent)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setShadow(offset: .zero, blur: s * 0.02,
              color: CGColor(srgbRed: 0.1, green: 0.6, blue: 0.3, alpha: 0.8))

let lw = s * 0.052
ctx.setLineWidth(lw)
let w = q * 0.40       // bracket half-width
let h = q * 0.72       // bracket half-height
let gx = center.x + w * 1.12  // `</>` group spans -w..+3.36w; center it on the roundel
// <
ctx.beginPath()
ctx.move(to: CGPoint(x: gx - w, y: center.y + h))
ctx.addLine(to: CGPoint(x: gx - w * 2.24, y: center.y))
ctx.addLine(to: CGPoint(x: gx - w, y: center.y - h))
ctx.strokePath()
// >
ctx.beginPath()
ctx.move(to: CGPoint(x: gx + w, y: center.y + h))
ctx.addLine(to: CGPoint(x: gx + w * 2.24, y: center.y))
ctx.addLine(to: CGPoint(x: gx + w, y: center.y - h))
ctx.strokePath()
// center slash
ctx.beginPath()
ctx.move(to: CGPoint(x: gx + w * 0.55, y: center.y + h))
ctx.addLine(to: CGPoint(x: gx - w * 0.55, y: center.y - h))
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// MARK: Write PNG
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(size)×\(size))")
