import AppKit
import CoreGraphics

// Turns a square source image into a macOS app iconset.
//
// macOS does NOT mask app icons the way iOS does — whatever the PNG contains is
// what Finder draws. So the rounded shape, the transparent margin and the drop
// shadow all have to be baked in here. Apple's grid for a 1024pt canvas puts the
// icon body at 824x824 with a 185.4pt corner radius, which is the 0.225 ratio
// below; the remaining 100pt margin on each side is where the shadow lives.
//
// CoreGraphics rather than sips: sips cannot round corners, and it stages output
// through the system temp directory, which is unavailable under some sandboxes —
// where it still exits 0, so a failure looks like success.

let canvas: CGFloat = 1024
let bodyRatio: CGFloat = 824.0 / 1024.0
let radiusRatio: CGFloat = 185.4 / 824.0

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("""
        usage: ShapeIcon <source.png> <out.icns|out.png> [options]

          --bg RRGGBB   fill the rounded body with this colour and draw the
                        source over it, fitted rather than cropped. For artwork
                        with alpha. Without it the source is cropped to fill.
          --scale 0…1   fraction of the body the source occupies. With --bg.
          --shadow off  omit the baked drop shadow.
          --preview DIR write every size as a PNG instead of an .icns.

""".data(using: .utf8)!)
    exit(2)
}
let sourcePath = CommandLine.arguments[1]
let outFile = URL(fileURLWithPath: CommandLine.arguments[2])

/// `--bg RRGGBB`: the body is filled and the source is *fitted* inside it, so a
/// logo with alpha keeps its shape instead of being cropped to a square.
var background: CGColor?
var artScale: CGFloat = 1.0
var previewDir: URL?
var shadowEnabled = true
var argv = Array(CommandLine.arguments.dropFirst(3))
while let flag = argv.first {
    argv.removeFirst()
    guard let value = argv.first else {
        FileHandle.standardError.write("\(flag) needs a value\n".data(using: .utf8)!)
        exit(2)
    }
    argv.removeFirst()
    switch flag {
    case "--bg":
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let rgb = Int(hex, radix: 16) else {
            FileHandle.standardError.write("--bg wants RRGGBB, got \(value)\n".data(using: .utf8)!)
            exit(2)
        }
        background = CGColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    case "--scale":
        guard let s = Double(value), s > 0, s <= 1 else {
            FileHandle.standardError.write("--scale wants 0…1, got \(value)\n".data(using: .utf8)!)
            exit(2)
        }
        artScale = CGFloat(s)
    case "--preview":
        previewDir = URL(fileURLWithPath: value)
    case "--shadow":
        // macOS draws a legacy .icns exactly as given — no mask, no lighting —
        // so on 14/15 the shadow has to be painted in or the icon sits flat
        // against the desktop next to Apple's own. macOS 26's Icon Composer
        // format moves this to the system; if that treatment also reaches
        // legacy icons, a baked shadow may double up there. Hence a switch.
        shadowEnabled = (value != "off" && value != "no" && value != "0")
    default:
        FileHandle.standardError.write("unknown flag \(flag)\n".data(using: .utf8)!)
        exit(2)
    }
}

guard let src = NSImage(contentsOfFile: sourcePath),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

/// Draws the shaped icon at `size` px and returns the PNG bytes.
func render(size: CGFloat, shadow wantsShadow: Bool) -> Data? {
    let shadow = wantsShadow && shadowEnabled
    let scale = size / canvas
    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high

    let body = (canvas * bodyRatio) * scale
    let origin = (size - body) / 2
    let rect = CGRect(x: origin, y: origin, width: body, height: body)
    let radius = body * radiusRatio
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // The shadow is drawn by filling the shape once beneath the clip. Below
    // ~64px it is more mud than depth, so it is dropped at small sizes.
    if shadow {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.012),
            blur: size * 0.022,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
        )
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let srcAspect = CGFloat(srcCG.width) / CGFloat(srcCG.height)
    var draw = rect

    if let background {
        // Filled tile: the source sits *inside* the body, fitted so nothing is
        // cropped, because artwork with alpha is a shape and cropping it lies
        // about that shape.
        ctx.setFillColor(background)
        ctx.fill(rect)
        let box = rect.insetBy(dx: rect.width * (1 - artScale) / 2,
                               dy: rect.height * (1 - artScale) / 2)
        if srcAspect > 1 {
            draw = CGRect(x: box.minX, y: box.midY - (box.width / srcAspect) / 2,
                          width: box.width, height: box.width / srcAspect)
        } else {
            draw = CGRect(x: box.midX - (box.height * srcAspect) / 2, y: box.minY,
                          width: box.height * srcAspect, height: box.height)
        }
    } else if srcAspect > 1 {
        // .aspectRatio(.fill): cover the square body, cropping the long edge.
        draw.size.width = rect.height * srcAspect
        draw.origin.x = rect.midX - draw.width / 2
    } else if srcAspect < 1 {
        draw.size.height = rect.width / srcAspect
        draw.origin.y = rect.midY - draw.height / 2
    }

    ctx.draw(srcCG, in: draw)
    ctx.restoreGState()

    guard let out = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: out)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

// The .icns container, written directly rather than via `iconutil`.
//
// iconutil stages through the system temp directory and so fails under a
// sandbox that denies it — reporting only "Failed to generate ICNS" with no
// cause. The format needs no tool: a 'icns' magic, the total byte count, then
// one chunk per image of {4-byte OSType, 4-byte length including these 8 bytes,
// PNG bytes}. All lengths are big-endian. Modern OSTypes take PNG payloads as
// they are, so the rendered files need no conversion.
//
// Each OSType encodes a pixel size; the @2x names are a Finder convention, not
// something the container knows about.
let types: [(ostype: String, px: CGFloat)] = [
    ("icp4", 16),    // 16x16
    ("ic11", 32),    // 16x16@2x
    ("icp5", 32),    // 32x32
    ("ic12", 64),    // 32x32@2x
    ("ic07", 128),   // 128x128
    ("ic13", 256),   // 128x128@2x
    ("ic08", 256),   // 256x256
    ("ic14", 512),   // 256x256@2x
    ("ic09", 512),   // 512x512
    ("ic10", 1024),  // 512x512@2x
]

func be32(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return Data(bytes: &big, count: 4)
}

// `--preview DIR` writes each size as its own PNG rather than an .icns, so a
// candidate can be judged before it is committed. Small sizes are written
// twice: once at true pixel size, and once magnified with interpolation OFF, so
// what you see is the actual pixel grid rather than a smoothed guess at it.
// Judging a 16px icon by looking at a scaled-up smooth version is how you ship
// a mark that turns to mush in System Settings.
if let previewDir {
    try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    for px in [16, 32, 64, 128, 256, 512, 1024] as [CGFloat] {
        guard let png = render(size: px, shadow: px >= 64) else { exit(1) }
        let name = String(format: "%04d.png", Int(px))
        try? png.write(to: previewDir.appendingPathComponent(name))

        guard px <= 64, let small = NSBitmapImageRep(data: png)?.cgImage else { continue }
        let factor: CGFloat = 512 / px
        guard let ctx = CGContext(
            data: nil, width: 512, height: 512,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { continue }
        ctx.interpolationQuality = .none   // nearest neighbour: show the pixels
        ctx.draw(small, in: CGRect(x: 0, y: 0, width: px * factor, height: px * factor))
        if let out = ctx.makeImage(),
           let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) {
            let zoom = String(format: "%04d-magnified.png", Int(px))
            try? data.write(to: previewDir.appendingPathComponent(zoom))
        }
    }
    print("previews in \(previewDir.path)")
    exit(0)
}

// A .png output writes one 1024 image instead of the container, for looking at
// a candidate before committing it.
if outFile.pathExtension.lowercased() == "png" {
    guard let png = render(size: 1024, shadow: true) else { exit(1) }
    do { try png.write(to: outFile) } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
    print("wrote \(outFile.lastPathComponent) — 1024px preview")
    exit(0)
}

var chunks = Data()
for (ostype, px) in types {
    guard let png = render(size: px, shadow: px >= 64) else {
        FileHandle.standardError.write("render failed at \(Int(px))px\n".data(using: .utf8)!)
        exit(1)
    }
    chunks.append(ostype.data(using: .ascii)!)
    chunks.append(be32(png.count + 8))
    chunks.append(png)
}

var icns = Data("icns".utf8)
icns.append(be32(chunks.count + 8))
icns.append(chunks)

do {
    try icns.write(to: outFile)
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outFile.lastPathComponent) — \(types.count) sizes, \(icns.count) bytes")
