#!/usr/bin/env swift

// generate_app_icon.swift
// Renders the 🗣️ emoji on a white squircle and produces AppIcon.icns.
// Usage: swift scripts/generate_app_icon.swift

import AppKit
import Foundation

// MARK: - Helpers

func renderIcon(size: Int) -> NSImage {
    let dim = CGFloat(size)
    let image = NSImage(size: NSSize(width: dim, height: dim))

    image.lockFocus()

    // White squircle background
    let radius = dim * 0.225
    let rect = CGRect(x: 0, y: 0, width: dim, height: dim)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor.white.setFill()
    path.fill()

    // Draw emoji centered
    let fontSize = dim * 0.62
    let font = NSFont(name: "AppleColorEmoji", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize)

    let emoji = "🗣️"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let textSize = str.size()

    // Centre in canvas
    let x = (dim - textSize.width) / 2
    let y = (dim - textSize.height) / 2

    str.draw(at: NSPoint(x: x, y: y))

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to url: URL) throws {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage from NSImage"])
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = image.size
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG data"])
    }
    try data.write(to: url)
}

func shell(_ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "IconGen", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Command \(args.joined(separator: " ")) exited with status \(process.terminationStatus)"
        ])
    }
}

// MARK: - Main

// Resolve output path relative to this script's location (repo root / app/Susurro/Resources)
let scriptDir: URL = {
    // Swift scripts expose the source file path via #file
    let filePath = #file
    if filePath.hasPrefix("/") {
        return URL(fileURLWithPath: filePath).deletingLastPathComponent()
    }
    // Fallback: cwd / scripts
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts")
}()

let repoRoot = scriptDir.deletingLastPathComponent()
let outputDir = repoRoot
    .appendingPathComponent("app")
    .appendingPathComponent("Susurro")
    .appendingPathComponent("Resources")

let iconsetDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon.iconset")

// iconset spec: (filename, pixel size)
let specs: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

do {
    // Prepare temp iconset directory
    try? FileManager.default.removeItem(at: iconsetDir)
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    print("Rendering icon sizes…")
    for (filename, size) in specs {
        let image = renderIcon(size: size)
        let dest = iconsetDir.appendingPathComponent(filename)
        try savePNG(image: image, to: dest)
        print("  \(filename) (\(size)px)")
    }

    // Ensure output directory exists
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let icnsPath = outputDir.appendingPathComponent("AppIcon.icns").path
    print("Running iconutil…")
    try shell(["iconutil", "-c", "icns", iconsetDir.path, "-o", icnsPath])
    print("Created \(icnsPath)")

    // Clean up
    try? FileManager.default.removeItem(at: iconsetDir)
    print("Done.")
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
