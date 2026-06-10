import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: generate_icon.swift <iconset-directory> [icns-file]\n".utf8))
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let icnsURL = CommandLine.arguments.count == 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let icnsTypesByPixelSize: [Int: String] = [
    16: "icp4",
    32: "icp5",
    64: "icp6",
    128: "ic07",
    256: "ic08",
    512: "ic09",
    1024: "ic10"
]

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: Int) throws -> Data {
    let scale = CGFloat(size) / 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "OneScreenIcon", code: 1)
    }

    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let backgroundPath = roundedRect(CGRect(x: 0, y: 0, width: 1024, height: 1024), radius: 220)
    context.addPath(backgroundPath)
    context.clip()

    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [NSColor(red: 0.082, green: 0.133, blue: 0.22, alpha: 1).cgColor,
                 NSColor(red: 0.02, green: 0.031, blue: 0.059, alpha: 1).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 168, y: 944),
        end: CGPoint(x: 856, y: 80),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    context.setStrokeColor(NSColor(red: 0.133, green: 0.196, blue: 0.29, alpha: 1).cgColor)
    context.setLineWidth(24)
    context.strokeEllipse(in: CGRect(x: 120, y: 120, width: 784, height: 784))

    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)

    let inactiveGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [NSColor(red: 0.2, green: 0.255, blue: 0.333, alpha: 1).cgColor,
                 NSColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1).cgColor] as CFArray,
        locations: [0, 1]
    )!
    for x in [112.0, 664.0] {
        let path = roundedRect(CGRect(x: x, y: 424, width: 248, height: 296), radius: 38)
        context.addPath(path)
        context.saveGState()
        context.clip()
        context.drawLinearGradient(inactiveGradient, start: CGPoint(x: x, y: 720), end: CGPoint(x: x, y: 424), options: [])
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(NSColor(red: 0.278, green: 0.333, blue: 0.412, alpha: 1).cgColor)
        context.setLineWidth(18)
        context.strokePath()
    }

    let outerScreen = roundedRect(CGRect(x: 294, y: 284, width: 436, height: 520), radius: 54)
    context.addPath(outerScreen)
    context.setFillColor(NSColor(red: 0.027, green: 0.067, blue: 0.122, alpha: 1).cgColor)
    context.fillPath()
    context.addPath(outerScreen)
    context.setStrokeColor(NSColor(red: 0.729, green: 0.902, blue: 0.992, alpha: 1).cgColor)
    context.setLineWidth(22)
    context.strokePath()

    let activeGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [NSColor(red: 0.49, green: 0.827, blue: 0.988, alpha: 1).cgColor,
                 NSColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1).cgColor] as CFArray,
        locations: [0, 1]
    )!
    let activeScreen = roundedRect(CGRect(x: 340, y: 334, width: 344, height: 420), radius: 28)
    context.addPath(activeScreen)
    context.saveGState()
    context.clip()
    context.drawLinearGradient(activeGradient, start: CGPoint(x: 348, y: 754), end: CGPoint(x: 676, y: 334), options: [])
    context.restoreGState()

    context.setFillColor(NSColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1).cgColor)
    context.beginPath()
    context.move(to: CGPoint(x: 422, y: 248))
    context.addLine(to: CGPoint(x: 602, y: 248))
    context.addLine(to: CGPoint(x: 630, y: 166))
    context.addLine(to: CGPoint(x: 394, y: 166))
    context.closePath()
    context.fillPath()

    context.setFillColor(NSColor(red: 0.8, green: 0.835, blue: 0.882, alpha: 1).cgColor)
    context.addPath(roundedRect(CGRect(x: 342, y: 132, width: 340, height: 46), radius: 23))
    context.fillPath()

    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setLineWidth(26)
    context.setLineCap(.round)
    context.setStrokeColor(NSColor(red: 0.878, green: 0.949, blue: 0.996, alpha: 0.9).cgColor)
    context.beginPath()
    context.move(to: CGPoint(x: 398, y: 682))
    context.addCurve(to: CGPoint(x: 652, y: 695), control1: CGPoint(x: 432, y: 716), control2: CGPoint(x: 562, y: 735))
    context.strokePath()

    context.setFillColor(NSColor(red: 0.973, green: 0.98, blue: 0.988, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: 442, y: 476, width: 140, height: 140))
    context.setFillColor(NSColor(red: 0.008, green: 0.518, blue: 0.78, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: 480, y: 514, width: 64, height: 64))

    guard let image = context.makeImage() else {
        throw NSError(domain: "OneScreenIcon", code: 2)
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "OneScreenIcon", code: 3)
    }
    return stripAncillaryPNGChunks(from: data)
}

func stripAncillaryPNGChunks(from data: Data) -> Data {
    let signatureLength = 8
    guard data.count > signatureLength else { return data }

    var output = Data()
    output.append(data.prefix(signatureLength))

    var offset = signatureLength
    while offset + 12 <= data.count {
        let length = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let chunkStart = offset
        let typeStart = offset + 4
        let dataStart = offset + 8
        let chunkEnd = dataStart + Int(length) + 4

        guard chunkEnd <= data.count else { return data }

        let type = data[typeStart..<typeStart + 4]
        let isCritical = type.first.map { $0 & 0x20 == 0 } ?? false
        let typeString = String(bytes: type, encoding: .ascii) ?? ""

        if isCritical || typeString == "sRGB" {
            output.append(data[chunkStart..<chunkEnd])
        }

        offset = chunkEnd
        if typeString == "IEND" {
            break
        }
    }

    return output
}

var icnsEntries: [(type: String, data: Data)] = []
var addedICNSSizes = Set<Int>()

for iconSize in sizes {
    let data = try drawIcon(size: iconSize.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(iconSize.name))

    if let type = icnsTypesByPixelSize[iconSize.pixels], !addedICNSSizes.contains(iconSize.pixels) {
        icnsEntries.append((type: type, data: data))
        addedICNSSizes.insert(iconSize.pixels)
    }
}

func appendBigEndianUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

func makeICNS(entries: [(type: String, data: Data)]) -> Data {
    var totalLength: UInt32 = 8
    for entry in entries {
        totalLength += UInt32(8 + entry.data.count)
    }

    var output = Data()
    output.append(contentsOf: [0x69, 0x63, 0x6e, 0x73])
    appendBigEndianUInt32(totalLength, to: &output)

    for entry in entries {
        output.append(entry.type.data(using: .ascii)!)
        appendBigEndianUInt32(UInt32(8 + entry.data.count), to: &output)
        output.append(entry.data)
    }

    return output
}

if let icnsURL {
    try makeICNS(entries: icnsEntries).write(to: icnsURL)
}
