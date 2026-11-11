// make-icon.swift — renders the Kodierer app icon (1024×1024 PNG).
// Usage: swift Scripts/make-icon.swift [output.png]
//
// Design: an ECU / microchip (the module being coded) on a graphite
// background, with a "K" monogram inside it built from a vertical stem plus a
// `<` code chevron — "K" for Kodierer, "|<" for code. A small cursor block
// sits after it, as if the chip is mid-edit. Original artwork: no vehicle
// maker's marks, emblems or brand colors.

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

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Palette
let bgTop     = rgb(0x1C2128)   // graphite
let bgBottom  = rgb(0x0D1014)
let chipFill  = rgb(0x262C35)
let chipEdge  = rgb(0x3A4250)
let pinColor  = rgb(0x8A93A3)
let traceCol  = rgb(0xF5A524, 0.18)
let amber     = rgb(0xFFB020)   // monogram, top
let orange    = rgb(0xFF6A1A)   // monogram, bottom
let center = CGPoint(x: s / 2, y: s / 2)

// MARK: Background — vertical graphite gradient + soft warm glow
let bg = CGGradient(colorsSpace: colorSpace, colors: [bgTop, bgBottom] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: colorSpace,
                      colors: [rgb(0xFF8A20, 0.22), rgb(0xFF8A20, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                       endCenter: center, endRadius: s * 0.48, options: [])

// MARK: Circuit traces running out from the chip to the icon edges
let chipHalf = s * 0.255
let pinsPerSide = 5
let pinPitch = (chipHalf * 2) / CGFloat(pinsPerSide + 1)
let pinLen = s * 0.055
let pinW = s * 0.026

ctx.setStrokeColor(traceCol)
ctx.setLineWidth(s * 0.010)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
for i in 1...pinsPerSide {
    let off = -chipHalf + pinPitch * CGFloat(i)
    let jog = s * 0.035   // same direction on every trace so they run parallel
    let start = chipHalf + pinLen
    // Four sides, each trace with a 45° jog so it reads as PCB routing.
    for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] as [(CGFloat, CGFloat)] {
        func p(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            // `along` runs outward from the chip, `across` along the chip edge.
            CGPoint(x: center.x + dx * along + dy * across,
                    y: center.y + dy * along + dx * across)
        }
        ctx.beginPath()
        ctx.move(to: p(start, off))
        ctx.addLine(to: p(start + s * 0.06, off))
        ctx.addLine(to: p(start + s * 0.06 + abs(jog), off + jog))
        ctx.addLine(to: p(s * 0.62, off + jog))
        ctx.strokePath()
        // Via at the jog
        let v = p(start + s * 0.06 + abs(jog), off + jog)
        ctx.setFillColor(traceCol)
        ctx.fillEllipse(in: CGRect(x: v.x - s * 0.013, y: v.y - s * 0.013,
                                   width: s * 0.026, height: s * 0.026))
    }
}

// MARK: Pins
ctx.setFillColor(pinColor)
for i in 1...pinsPerSide {
    let off = -chipHalf + pinPitch * CGFloat(i)
    let rects = [
        CGRect(x: center.x + chipHalf - 2, y: center.y + off - pinW / 2, width: pinLen + 2, height: pinW),
        CGRect(x: center.x - chipHalf - pinLen, y: center.y + off - pinW / 2, width: pinLen + 2, height: pinW),
        CGRect(x: center.x + off - pinW / 2, y: center.y + chipHalf - 2, width: pinW, height: pinLen + 2),
        CGRect(x: center.x + off - pinW / 2, y: center.y - chipHalf - pinLen, width: pinW, height: pinLen + 2),
    ]
    for r in rects {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: pinW * 0.3, cornerHeight: pinW * 0.3, transform: nil))
        ctx.fillPath()
    }
}

// MARK: Chip body
let chipRect = CGRect(x: center.x - chipHalf, y: center.y - chipHalf,
                      width: chipHalf * 2, height: chipHalf * 2)
let chipPath = CGPath(roundedRect: chipRect, cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.04, color: rgb(0x000000, 0.6))
ctx.setFillColor(chipFill)
ctx.addPath(chipPath)
ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(chipEdge)
ctx.setLineWidth(s * 0.008)
ctx.addPath(chipPath)
ctx.strokePath()
// Pin-1 marker dot (top-left)
ctx.setFillColor(rgb(0x4A5363))
ctx.fillEllipse(in: CGRect(x: chipRect.minX + s * 0.04, y: chipRect.maxY - s * 0.07,
                           width: s * 0.03, height: s * 0.03))

// MARK: "K" monogram = stem + `<` chevron, with a cursor block
// Built as one stroked path, then clipped to an amber→orange gradient.
let lw = s * 0.062
let kh = chipHalf * 0.56                  // monogram half-height
let stemX = center.x - chipHalf * 0.46
let tipX = stemX + chipHalf * 0.10        // chevron vertex sits just off the stem
let armX = center.x + chipHalf * 0.22

let k = CGMutablePath()
k.move(to: CGPoint(x: stemX, y: center.y + kh))       // stem
k.addLine(to: CGPoint(x: stemX, y: center.y - kh))
k.move(to: CGPoint(x: armX, y: center.y + kh))        // `<`
k.addLine(to: CGPoint(x: tipX, y: center.y))
k.addLine(to: CGPoint(x: armX, y: center.y - kh))
let kStroke = k.copy(strokingWithWidth: lw, lineCap: .round, lineJoin: .round, miterLimit: 10)

// Cursor block after the K, aligned to the baseline
let cursor = CGPath(roundedRect: CGRect(x: armX + lw * 0.5 + chipHalf * 0.10, y: center.y - kh - lw / 2,
                                        width: chipHalf * 0.22, height: lw * 0.8),
                    cornerWidth: lw * 0.2, cornerHeight: lw * 0.2, transform: nil)

let mono = CGMutablePath()
mono.addPath(kStroke)
mono.addPath(cursor)

// Glow underneath
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: s * 0.035, color: rgb(0xFF7A1A, 0.85))
ctx.setFillColor(orange)
ctx.addPath(mono)
ctx.fillPath()
ctx.restoreGState()
// Gradient fill
ctx.saveGState()
ctx.addPath(mono)
ctx.clip()
let monoGrad = CGGradient(colorsSpace: colorSpace, colors: [amber, orange] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(monoGrad, start: CGPoint(x: 0, y: center.y + kh + lw),
                       end: CGPoint(x: 0, y: center.y - kh - lw), options: [])
ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(size)×\(size))")
