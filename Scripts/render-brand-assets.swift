#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private func leftLowerKey() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 88, y: 272))
    path.addLine(to: CGPoint(x: 224, y: 272))
    path.addCurve(
        to: CGPoint(x: 240, y: 288),
        control1: CGPoint(x: 233, y: 272),
        control2: CGPoint(x: 240, y: 279)
    )
    path.addLine(to: CGPoint(x: 240, y: 440))
    path.addCurve(
        to: CGPoint(x: 217, y: 455),
        control1: CGPoint(x: 240, y: 452),
        control2: CGPoint(x: 228, y: 460)
    )
    path.addLine(to: CGPoint(x: 166, y: 432))
    path.addCurve(
        to: CGPoint(x: 72, y: 288),
        control1: CGPoint(x: 108, y: 406),
        control2: CGPoint(x: 72, y: 350)
    )
    path.addCurve(
        to: CGPoint(x: 88, y: 272),
        control1: CGPoint(x: 72, y: 279),
        control2: CGPoint(x: 79, y: 272)
    )
    path.closeSubpath()
    return path
}

private func rightLowerKey() -> CGPath {
    var mirror = CGAffineTransform(translationX: 512, y: 0)
    mirror = mirror.scaledBy(x: -1, y: 1)
    return leftLowerKey().copy(using: &mirror) ?? leftLowerKey()
}

private func drawMark(in context: CGContext, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(
        roundedRect: CGRect(x: 72, y: 72, width: 168, height: 168),
        cornerWidth: 36,
        cornerHeight: 36,
        transform: nil
    ))
    context.addPath(CGPath(
        roundedRect: CGRect(x: 272, y: 72, width: 168, height: 168),
        cornerWidth: 36,
        cornerHeight: 36,
        transform: nil
    ))
    context.addPath(leftLowerKey())
    context.addPath(rightLowerKey())
    context.fillPath()
}

private func renderAppIcon(size: Int, destination: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let scale = CGFloat(size) / 512
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)
    drawMark(in: context, color: CGColor(gray: 1, alpha: 1))
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let encoded = NSMutableData()
    guard let imageDestination = CGImageDestinationCreateWithData(
        encoded,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(imageDestination, image, nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try (encoded as Data).write(to: destination)
}

private let outputs: [(String, Int)] = [
    ("assets/branding/exports/app-icon-1024.png", 1024),
    ("assets/branding/exports/app-icon-preview-256.png", 256),
    ("assets/branding/exports/app-icon-preview-64.png", 64),
    ("Sources/HostApp/Assets.xcassets/AppIcon.appiconset/AppIcon-Monochrome-1024.png", 1024)
]

for (path, size) in outputs {
    let destination = repositoryRoot.appendingPathComponent(path)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try renderAppIcon(size: size, destination: destination)
}
