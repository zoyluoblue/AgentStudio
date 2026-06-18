import AppKit

// Renders several AgentStudio icon directions onto one comparison sheet so you can pick.
// Usage: swift iconsheet.swift /abs/out.png
// (tools/icongen.swift renders the CHOSEN variant to the real 1024 asset.)

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}
func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).cgPath
}
func sparkPath(_ c: CGPoint, _ R: CGFloat, innerRatio: CGFloat = 0.17, bow: CGFloat = 0.32) -> CGPath {
    let p = CGMutablePath(); let r = R * innerRatio
    func pt(_ d: CGFloat, _ rad: CGFloat) -> CGPoint { CGPoint(x: c.x + rad*cos(d * .pi/180), y: c.y + rad*sin(d * .pi/180)) }
    let seq = [pt(90,R),pt(45,r),pt(0,R),pt(-45,r),pt(-90,R),pt(-135,r),pt(180,R),pt(135,r)]
    p.move(to: seq[0])
    for i in 1...seq.count {
        let a = seq[i-1], b = seq[i % seq.count]
        let m = CGPoint(x:(a.x+b.x)/2, y:(a.y+b.y)/2)
        p.addQuadCurve(to: b, control: CGPoint(x: c.x+(m.x-c.x)*(1-bow), y: c.y+(m.y-c.y)*(1-bow)))
    }
    p.closeSubpath(); return p
}

enum BG { case dark(CGColor, CGColor); case cosmic; case metal; case bright }
struct Variant {
    let name: String
    let bg: BG
    let glow: CGColor
    let spark: [CGColor]      // white-hot → … → tip
    let dual: Bool
    let sparkShadow: Bool     // soft dark shadow under spark (for bright bg legibility)
}

let variants: [Variant] = [
    Variant(name: "1 · Amber Dual", bg: .dark(rgb(0.090,0.110,0.165), rgb(0.016,0.022,0.040)),
            glow: rgb(1.0,0.50,0.12,0.60), spark: [rgb(1,1,1), rgb(1,0.86,0.66), rgb(1,0.55,0.16)], dual: true, sparkShadow: false),
    Variant(name: "2 · Amber Solo", bg: .dark(rgb(0.090,0.110,0.165), rgb(0.016,0.022,0.040)),
            glow: rgb(1.0,0.50,0.12,0.62), spark: [rgb(1,1,1), rgb(1,0.86,0.66), rgb(1,0.55,0.16)], dual: false, sparkShadow: false),
    Variant(name: "3 · Electric Cyan", bg: .dark(rgb(0.055,0.095,0.150), rgb(0.010,0.028,0.052)),
            glow: rgb(0.20,0.70,1.0,0.60), spark: [rgb(1,1,1), rgb(0.70,0.93,1.0), rgb(0.13,0.58,0.96)], dual: true, sparkShadow: false),
    Variant(name: "4 · Cosmic Violet", bg: .cosmic,
            glow: rgb(0.62,0.35,1.0,0.55), spark: [rgb(1,1,1), rgb(0.90,0.85,1.0), rgb(0.55,0.40,0.96)], dual: true, sparkShadow: false),
    Variant(name: "5 · Gunmetal", bg: .metal,
            glow: rgb(1.0,0.52,0.13,0.45), spark: [rgb(1,1,1), rgb(1,0.86,0.66), rgb(1,0.55,0.16)], dual: false, sparkShadow: false),
    Variant(name: "6 · Bright Orange", bg: .bright,
            glow: rgb(1,1,1,0.0), spark: [rgb(1,1,1), rgb(1,1,1), rgb(1,0.97,0.92)], dual: true, sparkShadow: true),
]

func renderIcon(_ ctx: CGContext, _ frame: CGRect, _ v: Variant) {
    let S = frame.width
    let inset = S * 0.082
    let tile = frame.insetBy(dx: inset, dy: inset)
    let radius = tile.width * 0.2237
    let path = roundedPath(tile, radius)
    let center = CGPoint(x: tile.midX, y: tile.midY + tile.height*0.02)

    // tile shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S*0.016), blur: S*0.045, color: rgb(0,0,0,0.5))
    ctx.addPath(path); ctx.setFillColor(rgb(0,0,0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    // background
    switch v.bg {
    case .dark(let top, let bot):
        let g = CGGradient(colorsSpace: space, colors: [top, bot] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    case .cosmic:
        let g = CGGradient(colorsSpace: space, colors: [rgb(0.16,0.09,0.30), rgb(0.035,0.025,0.085)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    case .metal:
        let g = CGGradient(colorsSpace: space, colors: [rgb(0.22,0.23,0.27), rgb(0.065,0.070,0.085)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
        let sheen = CGGradient(colorsSpace: space, colors: [rgb(1,1,1,0.0), rgb(1,1,1,0.10), rgb(1,1,1,0.0)] as CFArray, locations: [0.35,0.5,0.65])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
    case .bright:
        let g = CGGradient(colorsSpace: space, colors: [rgb(1.0,0.74,0.36), rgb(0.93,0.42,0.07)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    }
    // vignette (skip for bright)
    if case .bright = v.bg {} else {
        let vig = CGGradient(colorsSpace: space, colors: [rgb(0,0,0,0.0), rgb(0,0,0,0.55)] as CFArray, locations: [0.5,1])!
        ctx.drawRadialGradient(vig, startCenter: CGPoint(x: tile.midX, y: tile.midY), startRadius: 0,
                               endCenter: CGPoint(x: tile.midX, y: tile.midY), endRadius: tile.width*0.80, options: [])
        let glow = CGGradient(colorsSpace: space, colors: [v.glow, v.glow.copy(alpha: 0)!] as CFArray, locations: [0,1])!
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: tile.width*0.46, options: [])
    }
    ctx.restoreGState()

    // glassy rim
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.addPath(roundedPath(tile.insetBy(dx: 2, dy: 2), radius))
    ctx.setStrokeColor(rgb(1,1,1, (v.bg.isBright ? 0.22 : 0.13))); ctx.setLineWidth(S*0.003); ctx.strokePath()
    let topHi = CGGradient(colorsSpace: space, colors: [rgb(1,1,1,0.10), rgb(1,1,1,0.0)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(topHi, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.maxY - tile.height*0.30), options: [])
    ctx.restoreGState()

    func drawSpark(_ c: CGPoint, _ R: CGFloat, blur: CGFloat) {
        let sp = sparkPath(c, R)
        ctx.saveGState()
        if v.sparkShadow { ctx.setShadow(offset: CGSize(width: 0, height: -R*0.05), blur: R*0.18, color: rgb(0,0,0,0.30)) }
        else { ctx.setShadow(offset: .zero, blur: blur, color: v.glow.copy(alpha: 0.9) ?? v.glow) }
        ctx.addPath(sp); ctx.setFillColor(v.spark.last ?? rgb(1,1,1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(sp); ctx.clip()
        let g = CGGradient(colorsSpace: space, colors: v.spark as CFArray, locations: [0,0.45,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y+R), end: CGPoint(x: c.x, y: c.y-R), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    drawSpark(center, tile.width * (v.dual ? 0.30 : 0.345), blur: tile.width*0.085)
    if v.dual { drawSpark(CGPoint(x: center.x + tile.width*0.205, y: center.y + tile.height*0.255), tile.width*0.095, blur: tile.width*0.035) }
}

extension BG { var isBright: Bool { if case .bright = self { return true }; return false } }

// ---- compose the sheet ----
let cols = 3, rows = 2
let icon: CGFloat = 300, cellW: CGFloat = 340, cellH: CGFloat = 384, margin: CGFloat = 44, labelH: CGFloat = 58
let sheetW = Int(margin*2 + CGFloat(cols)*cellW)
let sheetH = Int(margin*2 + CGFloat(rows)*cellH)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.setFillColor(rgb(0.086,0.094,0.110)); ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

for (i, v) in variants.enumerated() {
    let c = i % cols, r = i / cols
    let cellX = margin + CGFloat(c)*cellW
    // bottom-left origin: top row first → invert r
    let cellY = CGFloat(sheetH) - margin - CGFloat(r+1)*cellH
    let iconX = cellX + (cellW - icon)/2
    let iconY = cellY + labelH + (cellH - labelH - icon)/2
    renderIcon(ctx, CGRect(x: iconX, y: iconY, width: icon, height: icon), v)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21, weight: .medium), .foregroundColor: NSColor(white: 0.86, alpha: 1)]
    let str = NSAttributedString(string: v.name, attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: cellX + (cellW - sz.width)/2, y: cellY + (labelH - sz.height)/2))
}

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "variants.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
