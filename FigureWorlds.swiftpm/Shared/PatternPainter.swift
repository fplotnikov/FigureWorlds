import CoreGraphics
import Foundation
import ImageIO

/// Paints a pattern (dots, stripes, checks, stars, hearts) onto an animal's colour texture.
///
/// Meshy textures are cut into many small pieces, so a pattern drawn flat on the picture would
/// break at every seam. Instead each animal has a "position map" (<name>_pos.png, baked by
/// models/bake_position_map.py): for every texel it stores the 3D point on the body it belongs
/// to. The pattern is worked out from those 3D points, so dots stay round and stripes run round
/// the body without breaks. Eyes and other dark details keep their own colour.
enum PatternPainter {

    /// The pattern's coverage (0...1) for every texel of the position map, worked out once per
    /// animal and pattern (the colour is mixed in later, for whichever colour is chosen).
    struct Mask {
        let width: Int
        let height: Int
        let values: [UInt8]
    }

    static func mask(posURL: URL, box: [Float], pattern: Pattern) -> Mask? {
        guard box.count == 6, pattern != .plain,
              let src = CGImageSourceCreateWithURL(posURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let raw = rawRGB(image) else { return nil }
        let w = image.width, h = image.height
        let lo = SIMD3<Float>(box[0], box[1], box[2])
        let span = SIMD3<Float>(box[3] - box[0], box[4] - box[1], box[5] - box[2])
        let cx = (box[0] + box[3]) / 2, cz = (box[2] + box[5]) / 2
        var out = [UInt8](repeating: 0, count: w * h)
        raw.withUnsafeBufferPointer { px in
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 3
                    let r = px[i], g = px[i + 1], b = px[i + 2]
                    if Int(r) + Int(g) + Int(b) < 3 { continue }   // outside the texture's pieces
                    let v = SIMD3<Float>(Float(r), Float(g), Float(b)) / 255
                    let p = lo + v * span
                    let m = coverage(pattern, p, cx: cx, cz: cz)
                    out[y * w + x] = UInt8(max(0, min(255, m * 255)))
                }
            }
        }
        return Mask(width: w, height: h, values: out)
    }

    /// The colour texture with the pattern mixed in. The pattern colour is a lighter version of
    /// the fur where it is dark and a deeper version where it is light, so it always shows.
    /// A cheerful pattern colour for each colour choice (nil = work it out from the fur).
    static func ink(for skin: Skin) -> SIMD3<Float>? {
        switch skin {
        case .natural: nil
        case .sunny: SIMD3(0.95, 0.52, 0.18)    // orange on yellow
        case .ocean: SIMD3(0.13, 0.36, 0.72)    // deep blue on blue
        case .mint: SIMD3(0.12, 0.55, 0.47)     // teal on mint
        case .berry: SIMD3(0.50, 0.20, 0.62)    // purple on pink
        case .galaxy: SIMD3(0.98, 0.84, 0.40)   // gold on night blue
        case .snow: SIMD3(0.45, 0.66, 0.90)     // sky blue on white
        }
    }

    static func paint(base: CGImage, mask: Mask, ink: SIMD3<Float>? = nil) -> CGImage? {
        let w = base.width, h = base.height
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let sx = Float(mask.width) / Float(w), sy = Float(mask.height) / Float(h)
        mask.values.withUnsafeBufferPointer { mv in
            for y in 0..<h {
                // memory row 0 is the top of the picture, the same way round as the mask
                // smooth (bilinear) lookup, so edges stay soft when the colour texture is
                // bigger than the position map
                let fy = max(0, min(Float(mask.height - 1), (Float(y) + 0.5) * sy - 0.5))
                let y0 = Int(fy), y1 = min(mask.height - 1, y0 + 1), ty = fy - Float(y0)
                for x in 0..<w {
                    let fx = max(0, min(Float(mask.width - 1), (Float(x) + 0.5) * sx - 0.5))
                    let x0 = Int(fx), x1 = min(mask.width - 1, x0 + 1), tx = fx - Float(x0)
                    let top = Float(mv[y0 * mask.width + x0]) * (1 - tx) + Float(mv[y0 * mask.width + x1]) * tx
                    let bottom = Float(mv[y1 * mask.width + x0]) * (1 - tx) + Float(mv[y1 * mask.width + x1]) * tx
                    let m = (top * (1 - ty) + bottom * ty) / 255
                    if m <= 0.001 { continue }
                    let i = (y * w + x) * 4
                    let r = Float(px[i]) / 255, g = Float(px[i + 1]) / 255, b = Float(px[i + 2]) / 255
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    if lum < 0.13 { continue }                    // eyes, nose and dark lines stay
                    var (pr, pg, pb): (Float, Float, Float) = lum < 0.6
                        ? (r + (1 - r) * 0.8, g + (1 - g) * 0.8, b + (1 - b) * 0.8)
                        : (r * 0.5, g * 0.5, b * 0.52)
                    if let ink {
                        // the colour's own ink, unless it would hardly show on this bit of fur
                        let inkLum = 0.299 * ink.x + 0.587 * ink.y + 0.114 * ink.z
                        let diff = abs(ink.x - r) + abs(ink.y - g) + abs(ink.z - b)
                        if abs(inkLum - lum) > 0.12 || diff > 0.6 { (pr, pg, pb) = (ink.x, ink.y, ink.z) }
                    }
                    px[i] = UInt8((r + (pr - r) * m) * 255)
                    px[i + 1] = UInt8((g + (pg - g) * m) * 255)
                    px[i + 2] = UInt8((b + (pb - b) * m) * 255)
                }
            }
        }
        return ctx.makeImage()
    }

    // MARK: - The patterns (p in metres, app axes: x right, y up, z toward the viewer)

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    private static func fract(_ x: Float) -> Float { x - x.rounded(.down) }

    static func coverage(_ pattern: Pattern, _ p: SIMD3<Float>, cx: Float, cz: Float) -> Float {
        let aa: Float = 0.0006   // soft edge, about one texel
        switch pattern {
        case .plain:
            return 0
        case .dots:
            // little balls on a staggered 3D grid; where the body cuts through one, a dot shows
            let s: Float = 0.026, r: Float = 0.0072
            let iy = (p.y / s).rounded()
            let shift: Float = Int(iy) % 2 == 0 ? 0 : s / 2
            let qx = p.x - ((p.x - shift) / s).rounded() * s - shift
            let qz = p.z - ((p.z - shift) / s).rounded() * s - shift
            let qy = p.y - iy * s
            let d = (qx * qx + qy * qy + qz * qz).squareRoot()
            return 1 - smooth(r - aa, r + aa, d)
        case .stripes:
            // bands round the body
            let period: Float = 0.022
            let f = fract(p.y / period) * period
            let half = period * 0.24
            return 1 - smooth(half - aa, half + aa, abs(f - period / 2))
        case .checks:
            let c: Float = 0.018
            let n = Int((p.x / c).rounded(.down)) + Int((p.y / c).rounded(.down)) + Int((p.z / c).rounded(.down))
            return n & 1 == 0 ? 1 : 0
        case .stars, .hearts:
            // shapes on a staggered grid wrapped round the body (around its middle, front = +z)
            // (near the centre line, e.g. the top of the head, they are laid out flat seen
            // from above instead, so they do not squeeze into a starburst there)
            let dx = p.x - cx, dz = p.z - cz
            let radial = (dx * dx + dz * dz).squareRoot()
            let flat = radial < 0.024
            let u = flat ? p.x : atan2(dx, dz) * 0.06
            let v = flat ? p.z + 0.5 : p.y
            let cell: Float = 0.032
            let row = (v / cell).rounded()
            let shift: Float = Int(row) % 2 == 0 ? 0 : 0.5
            let lu = (u / cell - shift) - (u / cell - shift).rounded()
            let lv = v / cell - row
            return pattern == .stars ? star(lu, lv) : heart(lu, lv)
        }
    }

    /// A five-pointed star (one point up) in a unit cell.
    private static func star(_ x: Float, _ y: Float) -> Float {
        let rOut: Float = 0.36, rIn: Float = 0.16
        let r = (x * x + y * y).squareRoot()
        if r > rOut { return 0 }
        var a = atan2(y, x) - .pi / 2
        let seg = 2 * Float.pi / 5
        a = a - (a / seg).rounded() * seg               // -seg/2 ... seg/2, 0 at a point
        let edge = rOut - (rOut - rIn) * abs(a) / (seg / 2)
        return r <= edge ? 1 : 0
    }

    /// A heart (point down) in a unit cell.
    private static func heart(_ x: Float, _ y: Float) -> Float {
        let k: Float = 0.3
        let X = x / k, Y = y / k + 0.15
        let a = X * X + Y * Y - 1
        return a * a * a - X * X * Y * Y * Y <= 0 ? 1 : 0
    }

    /// The position map's pixels as tightly packed RGB bytes, exactly as stored (no colour
    /// management: the values are positions, not colours).
    private static func rawRGB(_ image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8, let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = image.width, h = image.height, bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        guard bpp >= 3 else { return nil }
        let alphaFirst: Bool = {
            switch image.alphaInfo {
            case .first, .premultipliedFirst, .noneSkipFirst: return true
            default: return false
            }
        }()
        let off = (bpp == 4 && alphaFirst) ? 1 : 0
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let s = y * bpr + x * bpp + off
                let d = (y * w + x) * 3
                out[d] = bytes[s]; out[d + 1] = bytes[s + 1]; out[d + 2] = bytes[s + 2]
            }
        }
        return out
    }
}
