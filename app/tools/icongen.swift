import AppKit

// Renders the AgentStudio master app icon (1024×1024 PNG): a deep dark "glass" tile with a neon
// orange glow and a faceted, white-hot spark mark — a premium / high-tech look (think Raycast,
// Linear, Warp), with orange kept as an accent rather than the whole background.
// Usage: swift icongen.swift /abs/path/icon_1024.png

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// rounded-square tile (macOS continuous-corner look), inset to leave room for a soft shadow
let inset: CGFloat = 86
let tile = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = tile.width * 0.2237
let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).cgPath

// drop shadow under the tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: rgb(0, 0, 0, 0.5))
ctx.addPath(path); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
ctx.restoreGState()

// everything inside the tile
ctx.saveGState()
ctx.addPath(path); ctx.clip()

// 1) deep, cool dark gradient (near-black blue) — crisp tech base
let bg = CGGradient(colorsSpace: space, colors: [rgb(0.055, 0.095, 0.150), rgb(0.010, 0.028, 0.052)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: S/2, y: tile.maxY), end: CGPoint(x: S/2, y: tile.minY), options: [])

// 2) strong vignette first → keeps corners deep black so the spark pops
let vig = CGGradient(colorsSpace: space, colors: [rgb(0, 0, 0, 0.0), rgb(0, 0, 0, 0.55)] as CFArray, locations: [0.5, 1])!
ctx.drawRadialGradient(vig, startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S/2), endRadius: tile.width * 0.80, options: [])

// 3) tight electric-cyan halo centred on the spark (energy, not a hazy floor)
let sparkC = CGPoint(x: S/2, y: S/2 + 18)
let glow = CGGradient(colorsSpace: space, colors: [rgb(0.20, 0.70, 1.0, 0.60), rgb(0.18, 0.62, 1.0, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: sparkC, startRadius: 0,
                       endCenter: sparkC, endRadius: tile.width * 0.46, options: [])
ctx.restoreGState()

// 4) glassy top rim highlight (thin bright inner stroke along the top)
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: radius, yRadius: radius).cgPath
ctx.addPath(rim); ctx.setStrokeColor(rgb(1, 1, 1, 0.14)); ctx.setLineWidth(3); ctx.strokePath()
let topHi = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.12), rgb(1, 1, 1, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(topHi, start: CGPoint(x: S/2, y: tile.maxY), end: CGPoint(x: S/2, y: tile.maxY - tile.height * 0.32), options: [])
ctx.restoreGState()

// a sharp 4-point "spark" (concave star) path
func sparkPath(center c: CGPoint, R: CGFloat, innerRatio: CGFloat = 0.17, bow: CGFloat = 0.32) -> CGPath {
    let p = CGMutablePath()
    let r = R * innerRatio
    func pt(_ deg: CGFloat, _ rad: CGFloat) -> CGPoint {
        CGPoint(x: c.x + rad * cos(deg * .pi / 180), y: c.y + rad * sin(deg * .pi / 180))
    }
    // tips on the axes, inner vertices on the diagonals → thin needle arms
    let seq = [pt(90, R), pt(45, r), pt(0, R), pt(-45, r), pt(-90, R), pt(-135, r), pt(180, R), pt(135, r)]
    p.move(to: seq[0])
    for i in 1...seq.count {
        let a = seq[i - 1], b = seq[i % seq.count]
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let ctrl = CGPoint(x: c.x + (mid.x - c.x) * (1 - bow), y: c.y + (mid.y - c.y) * (1 - bow))
        p.addQuadCurve(to: b, control: ctrl)
    }
    p.closeSubpath()
    return p
}

func drawSpark(center: CGPoint, R: CGFloat, glowBlur: CGFloat, glowAlpha: CGFloat) {
    let sp = sparkPath(center: center, R: R)
    // glow base
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: glowBlur, color: rgb(0.20, 0.62, 1.0, glowAlpha))
    ctx.addPath(sp); ctx.setFillColor(rgb(0.30, 0.72, 1.0)); ctx.fillPath()
    ctx.restoreGState()
    // white-hot → sky → electric-blue gradient fill
    ctx.saveGState()
    ctx.addPath(sp); ctx.clip()
    let g = CGGradient(colorsSpace: space,
                       colors: [rgb(1, 1, 1), rgb(0.70, 0.93, 1.0), rgb(0.13, 0.58, 0.96)] as CFArray,
                       locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: center.x, y: center.y + R), end: CGPoint(x: center.x, y: center.y - R),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// main spark, slightly above centre; a smaller companion top-right
drawSpark(center: CGPoint(x: S/2, y: S/2 + 18), R: 286, glowBlur: 80, glowAlpha: 0.9)
drawSpark(center: CGPoint(x: S/2 + 196, y: S/2 + 250), R: 92, glowBlur: 34, glowAlpha: 0.85)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
