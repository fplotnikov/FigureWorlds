import Foundation
import simd

/// Finding a way around furniture, walls and through doors, so a tap anywhere just works.
///
/// The village is covered by a grid of small squares (per floor). A square is free when an animal
/// can stand in its middle without touching anything. A path is found over free squares (A*),
/// then straightened so the animal walks in long smooth lines.
extension Village {
    static let navCell: Float = 0.3
    static let navOrigin: Float = -18
    static let navSize = 120

    func navIndex(_ p: SIMD2<Float>) -> Int? {
        let ix = Int(floor((p.x - Self.navOrigin) / Self.navCell))
        let iz = Int(floor((p.y - Self.navOrigin) / Self.navCell))
        guard ix >= 0, iz >= 0, ix < Self.navSize, iz < Self.navSize else { return nil }
        return iz * Self.navSize + ix
    }

    func navCenter(_ i: Int) -> SIMD2<Float> {
        let ix = i % Self.navSize
        let iz = i / Self.navSize
        return SIMD2<Float>(Self.navOrigin + (Float(ix) + 0.5) * Self.navCell,
                            Self.navOrigin + (Float(iz) + 0.5) * Self.navCell)
    }

    /// Marches from `a` along `dir` and returns how far it gets before passing close to a tree,
    /// pine or lamp post on this floor (nil when the view is clear).
    func viewBlocked(from a: SIMD3<Float>, toward dir: SIMD3<Float>, length: Float, level: Int) -> Float? {
        // A canopy the animal is standing (or riding) under doesn't count.
        let blockers = obstacles.filter { o in
            guard o.enabled, o.level == level, let v = o.view else { return false }
            return simd_distance(flat(a), o.center) > v.crown
        }
        // The igloo's dome blocks the view too, unless the animal is inside (then it hides).
        let domes = level == 0 ? houses.filter { $0.entrance != nil && !$0.contains(flat(a)) } : []
        guard !blockers.isEmpty || !domes.isEmpty else { return nil }
        let floorY = Float(level) * Self.floorHeight
        var d: Float = 0.5   // right next to the animal doesn't count
        while d <= length {
            let p = a + dir * d
            let q = flat(p)
            let y = p.y - floorY
            for o in blockers {
                guard case .circle(let r) = o.shape, let v = o.view, y < v.top else { continue }
                let low = (v.trunk ?? r) + 0.35
                let reach = y > v.crownBottom ? max(low, v.crown) : low
                if simd_distance_squared(q, o.center) < reach * reach { return d }
            }
            for h in domes where y < h.top {
                let r = h.halfX + 0.3
                if simd_distance_squared(q, h.center) < r * r { return d }
            }
            d += 0.1
        }
        return nil
    }

    /// Under a big canopy (the carousel)? Then the camera stays low to look in under it.
    func underCanopy(_ p: SIMD2<Float>, level: Int) -> Bool {
        obstacles.contains { o in
            guard o.enabled, o.level == level, let v = o.view, v.crown > 2 else { return false }
            return simd_distance(p, o.center) < v.crown
        }
    }

    /// Can an animal stand here without touching anything?
    func isFree(_ p: SIMD2<Float>, level: Int) -> Bool {
        if simd_length(p) > Self.walkRadius - 0.05 { return false }
        if level > 0 {
            guard let big = bigHouse, big.contains(p, margin: -0.2) else { return false }
        }
        let r = Walker.radius + 0.04
        for o in obstacles where o.enabled && o.level == level {
            if simd_distance_squared(o.pushOut(p, radius: r), p) > 1e-6 { return false }
        }
        return true
    }

    func cellFree(_ i: Int, level: Int) -> Bool {
        let l = min(max(level, 0), navCache.count - 1)
        if navCache[l].isEmpty {
            navCache[l] = [Int8](repeating: -1, count: Self.navSize * Self.navSize)
        }
        let known = navCache[l][i]
        if known >= 0 { return known == 1 }
        let free = isFree(navCenter(i), level: l)
        navCache[l][i] = free ? 1 : 0
        return free
    }

    func nearestFreeCell(_ p: SIMD2<Float>, level: Int, maxRing: Int = 8) -> Int? {
        guard let c = navIndex(p) else { return nil }
        if cellFree(c, level: level) { return c }
        let n = Self.navSize
        let cx = c % n, cz = c / n
        for ring in 1...maxRing {
            var best: Int?
            var bestD = Float.infinity
            for dz in -ring...ring {
                for dx in -ring...ring where max(abs(dx), abs(dz)) == ring {
                    let x = cx + dx, z = cz + dz
                    guard x >= 0, z >= 0, x < n, z < n else { continue }
                    let i = z * n + x
                    guard cellFree(i, level: level) else { continue }
                    let d = simd_distance_squared(navCenter(i), p)
                    if d < bestD {
                        bestD = d
                        best = i
                    }
                }
            }
            if let best { return best }
        }
        return nil
    }

    /// Is the straight line from p to q clear? (The first bit is allowed to touch a wall the animal leans on.)
    func lineFree(_ p: SIMD2<Float>, _ q: SIMD2<Float>, level: Int) -> Bool {
        let d = simd_distance(p, q)
        let steps = max(1, Int(d / 0.1))
        for k in 0...steps {
            let x = p + (q - p) * (Float(k) / Float(steps))
            if simd_distance(x, p) < 0.25 { continue }
            guard let i = navIndex(x), cellFree(i, level: level) else { return false }
        }
        return true
    }

    /// Corners to walk past from `a` to `b` on one floor. The last point is always `b`.
    func findPath(from a: SIMD2<Float>, to b: SIMD2<Float>, level: Int) -> [SIMD2<Float>] {
        if lineFree(a, b, level: level) { return [b] }
        guard let s = nearestFreeCell(a, level: level),
              let g = nearestFreeCell(b, level: level), s != g else { return [b] }
        let n = Self.navSize
        var cost = [Float](repeating: .infinity, count: n * n)
        var came = [Int32](repeating: -1, count: n * n)
        var heap = NavHeap()
        let goalP = navCenter(g)
        cost[s] = 0
        heap.push(NavHeap.Item(f: simd_distance(navCenter(s), goalP), i: s))
        let dirs: [(Int, Int, Float)] = [
            (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
            (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)
        ]
        var found = false
        var steps = 0
        while let cur = heap.pop() {
            if cur.i == g { found = true; break }
            steps += 1
            if steps > 16000 { break }
            let i = cur.i
            let gi = cost[i]
            if cur.f > gi + simd_distance(navCenter(i), goalP) + 0.001 { continue }   // an old entry
            let x = i % n, z = i / n
            for (dx, dz, w) in dirs {
                let nx = x + dx, nz = z + dz
                guard nx >= 0, nz >= 0, nx < n, nz < n else { continue }
                let j = nz * n + nx
                guard cellFree(j, level: level) else { continue }
                if dx != 0 && dz != 0 {
                    guard cellFree(z * n + nx, level: level), cellFree(nz * n + x, level: level) else { continue }
                }
                let c = gi + w * Self.navCell
                if c < cost[j] {
                    cost[j] = c
                    came[j] = Int32(i)
                    heap.push(NavHeap.Item(f: c + simd_distance(navCenter(j), goalP), i: j))
                }
            }
        }
        guard found else { return [b] }

        var cells: [Int] = [g]
        var k = g
        while k != s {
            k = Int(came[k])
            cells.append(k)
        }
        cells.reverse()
        let pts: [SIMD2<Float>] = [a] + cells.map { navCenter($0) } + [b]

        // Straighten: from each corner, jump to the farthest point that can be seen.
        var out: [SIMD2<Float>] = []
        var i = 0
        while i < pts.count - 1 {
            var j = pts.count - 1
            while j > i + 1 && !lineFree(pts[i], pts[j], level: level) { j -= 1 }
            out.append(pts[j])
            i = j
        }
        return out
    }
}

/// A small priority queue for the path search.
struct NavHeap {
    struct Item {
        var f: Float
        var i: Int
    }

    private var items: [Item] = []

    mutating func push(_ x: Item) {
        items.append(x)
        var c = items.count - 1
        while c > 0 {
            let p = (c - 1) / 2
            if items[p].f <= items[c].f { break }
            items.swapAt(p, c)
            c = p
        }
    }

    mutating func pop() -> Item? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var c = 0
            while true {
                let l = 2 * c + 1, r = l + 1
                var m = c
                if l < items.count && items[l].f < items[m].f { m = l }
                if r < items.count && items[r].f < items[m].f { m = r }
                if m == c { break }
                items.swapAt(c, m)
                c = m
            }
        }
        return top
    }
}
