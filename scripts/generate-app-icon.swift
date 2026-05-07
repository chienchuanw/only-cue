#!/usr/bin/env swift
// Regenerate OnlyCue's placeholder app icon (1024×1024 PNG).
// Run from repo root: ./scripts/generate-app-icon.swift
// Output: OnlyCue/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let outputPath = "OnlyCue/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create CGContext") }

let rect = CGRect(x: 0, y: 0, width: size, height: size)

let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1),
        CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Teal "OC" mark — matches the default cue swatch color.
let teal = CGColor(red: 0.31, green: 0.80, blue: 0.77, alpha: 1)
ctx.setFillColor(teal)
let dot = CGRect(x: 220, y: 600, width: 180, height: 180)
ctx.fillEllipse(in: dot)

ctx.setStrokeColor(teal)
ctx.setLineWidth(48)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 320, y: 380))
ctx.addLine(to: CGPoint(x: 720, y: 380))
ctx.strokePath()
ctx.move(to: CGPoint(x: 320, y: 240))
ctx.addLine(to: CGPoint(x: 560, y: 240))
ctx.strokePath()

guard let cgImage = ctx.makeImage() else { fatalError("could not make CGImage") }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
let url = URL(fileURLWithPath: outputPath)
try png.write(to: url)
print("wrote \(outputPath)")
