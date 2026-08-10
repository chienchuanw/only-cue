#!/usr/bin/env swift
// Regenerate OnlyCue's DMG installer background (art ONLY — Finder draws the
// live app icon, Applications folder, labels, and title bar on top).
// Run from repo root:  ./scripts/generate-dmg-background.swift
// Deterministic: a pure function of the constants below — same bytes every run.
import AppKit

let W: CGFloat = 600, H: CGFloat = 400
let indigo = (r: CGFloat(0.42), g: CGFloat(0.40), b: CGFloat(0.93))

// Fixed integer hash -> [0,1): the ONLY source of "randomness" (reproducible).
func hash01(_ n: Int) -> CGFloat {
    var x = UInt64(bitPattern: Int64(n &* 2654435761 &+ 12345))
    x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
    return CGFloat(x % 100000) / 100000
}

func render(scale: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    func ty(_ t: CGFloat) -> CGFloat { H - t }   // top-left -> bottom-left
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    // 1. brand dark gradient (matches the app icon)
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(0.16, 0.18, 0.24), rgb(0.04, 0.06, 0.10)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    let iconCX: CGFloat = 168, folderCX: CGFloat = 432, rowCY: CGFloat = 165

    // 2. cool-white glow behind the app-icon anchor
    let glow = CGGradient(colorsSpace: cs,
                          colors: [rgb(0.75, 0.80, 0.95, 0.16), rgb(0.75, 0.80, 0.95, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: iconCX, y: ty(rowCY)), startRadius: 0,
                           endCenter: CGPoint(x: iconCX, y: ty(rowCY)), endRadius: 120, options: [])

    // 3. "like a real song" vertical-bar waveform (deterministic)
    let baseY = ty(305), halfW: CGFloat = 205
    let x0 = W / 2 - halfW, x1 = W / 2 + halfW, maxH: CGFloat = 22
    ctx.setFillColor(rgb(0.74, 0.72, 0.66, 0.34))
    var bx = x0
    var i = 0
    while bx <= x1 {
        let t = (bx - x0) / (x1 - x0)
        var macro = 0.42 + 0.30 * sin(t * 8.2 + 0.4) + 0.16 * sin(t * 19.0 + 2.1) + 0.10 * sin(t * 3.1 + 1.0)
        macro = max(0.06, min(1.0, macro))
        let edge = max(0, min(1, min(t, 1 - t) / 0.06))
        let detail = 0.30 + 0.70 * hash01(i)
        let transient: CGFloat = hash01(i * 13 + 7) > 0.90 ? 1.4 : 1.0
        let h = max(1.2, maxH * macro * detail * transient * edge)
        ctx.fill(CGRect(x: bx, y: baseY - h, width: 1.7, height: 2 * h))
        bx += 5; i += 1
    }

    // 4. cue markers (the icon's playhead: indigo line + round dot cap on top)
    func cueMarker(_ x: CGFloat) {
        ctx.setStrokeColor(rgb(indigo.r, indigo.g, indigo.b)); ctx.setLineWidth(2); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: x, y: baseY - 22)); ctx.addLine(to: CGPoint(x: x, y: baseY + 42)); ctx.strokePath()
        ctx.setFillColor(rgb(indigo.r, indigo.g, indigo.b))
        ctx.fillEllipse(in: CGRect(x: x - 4.5, y: baseY + 42 - 4.5, width: 9, height: 9))
    }
    cueMarker(W / 2 - 72)
    cueMarker(W / 2 + 58)

    // 5. precise straight "engineering" arrow: icon -> folder
    ctx.setStrokeColor(rgb(0.88, 0.86, 0.80, 0.92)); ctx.setLineWidth(1.8); ctx.setLineJoin(.miter)
    let ay = ty(rowCY), ax0 = iconCX + 76, ax1 = folderCX - 76
    ctx.setLineCap(.butt)
    ctx.move(to: CGPoint(x: ax0, y: ay)); ctx.addLine(to: CGPoint(x: ax1, y: ay)); ctx.strokePath()
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: ax1 - 9, y: ay + 6)); ctx.addLine(to: CGPoint(x: ax1, y: ay))
    ctx.addLine(to: CGPoint(x: ax1 - 9, y: ay - 6)); ctx.strokePath()
    ctx.setFillColor(rgb(0.88, 0.86, 0.80, 0.8))
    ctx.fillEllipse(in: CGRect(x: ax0 - 2, y: ay - 2, width: 4, height: 4))

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let dir = "scripts/dmg-assets"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
writePNG(render(scale: 1), to: "\(dir)/dmg-background.png")
writePNG(render(scale: 2), to: "\(dir)/dmg-background@2x.png")
