import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generate the standard ICNS container with RGBA PNG representations at 1×/2×.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for (source, name) in [("Resources/icon-main.png", "SpaceTabs"), ("Resources/icon-settings.png", "SpaceTabsSettings")] {
    guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw NSError(
            domain: "SpaceTabsIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read \(source)"])
    }
    let iconset = output.appendingPathComponent("\(name).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    var chunks = Data()
    let types = [
        16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"], 256: ["ic08", "ic14"],
        512: ["ic09", "ic10"],
    ]
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard
                let context = CGContext(
                    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                throw NSError(domain: "SpaceTabsIcons", code: 2)
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let suffix = scale == 2 ? "@2x" : ""
            let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
            guard let result = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(
                    file as CFURL, UTType.png.identifier as CFString, 1, nil)
            else {
                throw NSError(domain: "SpaceTabsIcons", code: 3)
            }
            CGImageDestinationAddImage(destination, result, nil)
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "SpaceTabsIcons", code: 4) }
            let png = try Data(contentsOf: file)
            chunks.append(Data(types[size]![scale - 1].utf8))
            var length = UInt32(png.count + 8).bigEndian
            chunks.append(withUnsafeBytes(of: &length) { Data($0) })
            chunks.append(png)
        }
    }
    var container = Data("icns".utf8)
    var total = UInt32(chunks.count + 8).bigEndian
    container.append(withUnsafeBytes(of: &total) { Data($0) })
    container.append(chunks)
    try container.write(to: output.appendingPathComponent("\(name).icns"), options: .atomic)
}
