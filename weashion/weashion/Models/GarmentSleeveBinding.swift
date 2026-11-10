import simd

nonisolated struct GarmentSleeveKnot: Codable, Sendable {
    let center: SIMD3<Float>
    let station: Float
}

nonisolated struct GarmentSleeveBinding: Codable, Sendable {
    let right: [GarmentSleeveKnot]
    let left: [GarmentSleeveKnot]

    var memoryCost: Int { (right.count + left.count) * MemoryLayout<GarmentSleeveKnot>.stride }

    var isValid: Bool {
        guard right.allSatisfy({ $0.center.x > 0 }), left.allSatisfy({ $0.center.x < 0 }) else { return false }
        for knots in [right, left] {
            guard (2...64).contains(knots.count) else { return false }
            for knot in knots {
                guard knot.center.x.isFinite, knot.center.y.isFinite, knot.center.z.isFinite,
                      simd_length_squared(knot.center) < 9,
                      knot.station.isFinite, (0...2).contains(knot.station) else { return false }
            }
            for (first, second) in zip(knots, knots.dropFirst()) {
                guard second.station - first.station > 0.00001,
                      simd_distance_squared(first.center, second.center) > 1e-10,
                      abs(second.center.x) > abs(first.center.x) else { return false }
            }
        }
        return true
    }

    func resized(stationScale: Float, transform: (SIMD3<Float>) -> SIMD3<Float>) -> Self {
        func resize(_ knots: [GarmentSleeveKnot]) -> [GarmentSleeveKnot] {
            knots.map { .init(center: transform($0.center), station: $0.station * stationScale) }
        }
        return Self(right: resize(right), left: resize(left))
    }
}

nonisolated struct GarmentSleeveCurve {
    nonisolated struct SmoothedOffsets {
        let length: Float
        let bow: SIMD3<Float>
        let skew: SIMD3<Float>

        func offset(at station: Float) -> SIMD3<Float> {
            let progress = station / length
            return (bow + skew * (1 - 2 * progress)) * progress * (1 - progress)
        }
    }

    nonisolated struct Frame {
        let center: SIMD3<Float>
        let tangent: SIMD3<Float>
        let radial: SIMD3<Float>
        let depth: SIMD3<Float>
        let station: Float
    }

    let frames: [Frame]

    init(knots: [GarmentSleeveKnot]) {
        guard knots.count >= 2 else {
            frames = []
            return
        }
        var result: [Frame] = []
        for index in knots.indices {
            let before = knots[max(index - 1, 0)].center
            let after = knots[min(index + 1, knots.count - 1)].center
            let tangent = simd_normalize(after - before)
            let hint: SIMD3<Float>
            if let previous = result.last {
                hint = simd_quatf(from: previous.tangent, to: tangent).act(previous.depth)
            } else {
                hint = abs(tangent.z) < 0.95 ? [0, 0, 1] : [0, 1, 0]
            }
            let depth = simd_normalize(hint - tangent * simd_dot(hint, tangent))
            result.append(.init(center: knots[index].center, tangent: tangent,
                                radial: simd_normalize(simd_cross(depth, tangent)), depth: depth,
                                station: knots[index].station))
        }
        frames = result
    }

    init(chain: [SIMD3<Float>]) {
        var station: Float = 0
        var knots: [GarmentSleeveKnot] = []
        for point in chain {
            if let previous = knots.last {
                let distance = simd_distance(previous.center, point)
                guard distance > 0.00001 else { continue }
                station += distance
            }
            knots.append(.init(center: point, station: station))
        }
        self.init(knots: knots)
    }

    // Fit a single cubic so scanned section centers cannot introduce local sleeve kinks.
    func smoothedOffsets(from start: SIMD3<Float>, to end: SIMD3<Float>, length: Float) -> SmoothedOffsets {
        var aa: Float = 0, ab: Float = 0, bb: Float = 0
        var av = SIMD3<Float>.zero, bv = SIMD3<Float>.zero
        for frame in frames where frame.station > 0 && frame.station < length {
            let progress = frame.station / length
            let first = progress * (1 - progress)
            let second = first * (1 - 2 * progress)
            let offset = frame.center - (start + (end - start) * progress)
            aa += first * first
            ab += first * second
            bb += second * second
            av += offset * first
            bv += offset * second
        }
        let determinant = aa * bb - ab * ab
        if determinant > 1e-10 {
            return .init(length: length, bow: (av * bb - bv * ab) / determinant,
                         skew: (bv * aa - av * ab) / determinant)
        }
        return .init(length: length, bow: aa > 0 ? av / aa : .zero, skew: .zero)
    }

    func frame(at station: Float) -> Frame? {
        guard frames.count >= 2 else { return nil }
        let upper = frames.indices.dropFirst().first { frames[$0].station >= station } ?? (frames.count - 1)
        let first = frames[upper - 1]
        let second = frames[upper]
        let fraction = (station - first.station) / (second.station - first.station)
        let orientation = min(max(fraction, 0), 1)
        let tangent = simd_normalize(first.tangent + (second.tangent - first.tangent) * orientation)
        let hint = first.depth + (second.depth - first.depth) * orientation
        let depth = simd_normalize(hint - tangent * simd_dot(hint, tangent))
        return .init(center: first.center + (second.center - first.center) * fraction,
                     tangent: tangent, radial: simd_normalize(simd_cross(depth, tangent)),
                     depth: depth, station: station)
    }

    func closestFrame(to point: SIMD3<Float>) -> Frame? {
        var bestDistance: Float = .infinity
        var station: Float?
        for index in frames.indices.dropLast() {
            let first = frames[index]
            let second = frames[index + 1]
            let edge = second.center - first.center
            let minimum = index == 0 ? -first.station / (second.station - first.station) : 0
            let fraction = min(max(simd_dot(point - first.center, edge) / simd_length_squared(edge), minimum), 1)
            let distance = simd_distance_squared(point, first.center + edge * fraction)
            if distance < bestDistance {
                bestDistance = distance
                station = first.station + (second.station - first.station) * fraction
            }
        }
        return station.flatMap { frame(at: $0) }
    }
}
