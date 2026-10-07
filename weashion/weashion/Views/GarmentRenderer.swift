import RealityKit
import UIKit
import simd

nonisolated struct GarmentMeshAsset: Codable, Sendable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    let trims: [GarmentTrim]
    var fitting: GarmentFitProfile? = nil

    var memoryCost: Int {
        vertices.count * MemoryLayout<SIMD3<Float>>.stride + indices.count * 4
            + trims.reduce(0) { $0 + $1.vertices.count * MemoryLayout<Int>.stride }
            + (fitting?.memoryCost ?? 0)
    }

    var isValid: Bool {
        guard (3...12000).contains(vertices.count), !indices.isEmpty, indices.count <= 120000,
              indices.count.isMultiple(of: 3),
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && simd_length_squared($0) < 9 }),
              indices.allSatisfy({ Int($0) < vertices.count }) else { return false }
        var used = Set<UInt32>()
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let first = indices[triangle]
            let second = indices[triangle + 1]
            let third = indices[triangle + 2]
            guard first != second, second != third, third != first,
                  simd_length_squared(simd_cross(vertices[Int(second)] - vertices[Int(first)],
                                                 vertices[Int(third)] - vertices[Int(first)])) > 1e-14 else { return false }
            used.formUnion([first, second, third])
        }
          guard used.count == vertices.count,
              fitting?.isValid(vertexCount: vertices.count) ?? true else { return false }
        return trims.allSatisfy { trim in
            trim.vertices.count >= 3 && trim.vertices.count <= vertices.count
                && trim.vertices.allSatisfy { vertices.indices.contains($0) }
                && trim.radius.isFinite && (0.0001...0.01).contains(trim.radius)
                && trim.ribbonWidth.isFinite && (0...0.03).contains(trim.ribbonWidth)
        }
    }
}

nonisolated struct GarmentTrim: Codable, Sendable {
    let vertices: [Int]
    let radius: Float
    let ribbonWidth: Float
}

@MainActor
enum GarmentRenderer {
    static func makeModel(asset: GarmentMeshAsset, positions: [SIMD3<Float>], appearance: GarmentAppearance) -> Entity? {
        guard positions.count == asset.vertices.count else { return nil }
        func material(_ color: SIMD3<Float>) -> SimpleMaterial {
            SimpleMaterial(
                color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1),
                roughness: .init(floatLiteral: appearance.roughness),
                isMetallic: false
            )
        }
        let surface = GarmentSurface(vertices: positions, indices: asset.indices)
        guard let panels = surface.entity(material: material(appearance.color), name: "Draped garment") else { return nil }
        let model = Entity()
        model.addChild(panels)
        var finishing = GarmentSurface()
        for trim in asset.trims {
            let loop = trim.vertices.map { positions[$0] }
            finishing.addBinding(around: loop, width: trim.radius)
            if trim.ribbonWidth > 0 {
                let start = finishing.vertices.count
                let center = loop.reduce(SIMD3<Float>.zero, +) / Float(loop.count)
                for row in 0...4 {
                    let fraction = Float(row) / 4
                    for point in loop {
                        let radial = SIMD3<Float>(point.x - center.x, 0, point.z - center.z)
                        let outward = simd_length_squared(radial) > 1e-12 ? simd_normalize(radial) : SIMD3<Float>(1, 0, 0)
                        finishing.vertices.append(point + outward * (trim.ribbonWidth * fraction)
                            + SIMD3<Float>(0, 0.0015 - 0.006 * fraction, 0))
                    }
                }
                finishing.connectRings(start: start, rows: 4, columns: loop.count, reversed: true)
            }
        }
        if !finishing.indices.isEmpty {
            guard let trim = finishing.entity(material: material(appearance.trimColor), name: "Garment finishing") else { return nil }
            model.addChild(trim)
        }
        return model
    }
}

nonisolated struct GarmentSurface {
    var vertices: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    var smoothPairs: [(Int, Int)] = []

    mutating func weldSeams() -> [Int] {
        var parents = Array(vertices.indices)
        func representative(_ index: Int) -> Int {
            var root = index
            while parents[root] != root { root = parents[root] }
            return root
        }
        for (first, second) in smoothPairs {
            let firstRoot = representative(first)
            let secondRoot = representative(second)
            parents[max(firstRoot, secondRoot)] = min(firstRoot, secondRoot)
        }
        var unique: [SIMD3<Float>] = []
        var lookup: [Int: Int] = [:]
        let mapping = vertices.indices.map { index -> Int in
            let root = representative(index)
            if let existing = lookup[root] { return existing }
            let result = unique.count
            unique.append(vertices[root])
            lookup[root] = result
            return result
        }
        var faces: [UInt32] = []
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let first = mapping[Int(indices[triangle])]
            let second = mapping[Int(indices[triangle + 1])]
            let third = mapping[Int(indices[triangle + 2])]
            guard first != second, second != third, third != first,
                  simd_length_squared(simd_cross(unique[second] - unique[first], unique[third] - unique[first])) > 1e-14 else { continue }
            faces.append(contentsOf: [UInt32(first), UInt32(second), UInt32(third)])
        }
        vertices = unique
        indices = faces
        smoothPairs.removeAll()
        return mapping
    }

    mutating func connectGrid(start: Int, rows: Int, columns: Int) {
        for row in 0..<rows {
            for column in 0..<(columns - 1) {
                addQuad(start + row * columns + column, start + (row + 1) * columns + column,
                        start + row * columns + column + 1, start + (row + 1) * columns + column + 1)
            }
        }
    }

    mutating func connectRings(start: Int, rows: Int, columns: Int, reversed: Bool = false) {
        for row in 0..<rows {
            for column in 0..<columns {
                let next = (column + 1) % columns
                addQuad(start + row * columns + column, start + (row + 1) * columns + column,
                        start + row * columns + next, start + (row + 1) * columns + next, reversed: reversed)
            }
        }
    }

    private mutating func addQuad(_ lower: Int, _ upper: Int, _ next: Int, _ upperNext: Int, reversed: Bool = false) {
        let triangle = reversed ? [lower, next, upper, next, upperNext, upper] : [lower, upper, next, next, upper, upperNext]
        indices.append(contentsOf: triangle.map { UInt32($0) })
    }

    mutating func addBinding(around points: [SIMD3<Float>], width: Float) {
        let start = vertices.count
        let sides = 6
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            let delta = next - previous
            let tangent = simd_length_squared(delta) > 1e-12 ? simd_normalize(delta) : SIMD3<Float>(1, 0, 0)
            let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [0, 0, 1]
            let across = simd_normalize(simd_cross(tangent, reference))
            let normal = simd_cross(tangent, across)
            for side in 0..<sides {
                let angle = Float(side) * 2 * .pi / Float(sides)
                vertices.append(points[index] + width * (across * cos(angle) + normal * sin(angle)))
            }
        }
        for index in points.indices {
            let next = (index + 1) % points.count
            for side in 0..<sides {
                let nextSide = (side + 1) % sides
                addQuad(start + index * sides + side, start + next * sides + side,
                        start + index * sides + nextSide, start + next * sides + nextSide, reversed: true)
            }
        }
    }

    @MainActor
    func entity(material: SimpleMaterial, name: String) -> ModelEntity? {
        var normals = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let first = Int(indices[triangle])
            let second = Int(indices[triangle + 1])
            let third = Int(indices[triangle + 2])
            let normal = simd_cross(vertices[second] - vertices[first], vertices[third] - vertices[first])
            normals[first] += normal
            normals[second] += normal
            normals[third] += normal
        }
        normals = normals.map { simd_length_squared($0) > 1e-16 ? simd_normalize($0) : [0, 1, 0] }
        var descriptor = MeshDescriptor(name: name)
        let outer = vertices.indices.map { vertices[$0] + normals[$0] * 0.0004 }
        let inner = vertices.indices.map { vertices[$0] - normals[$0] * 0.0004 }
        descriptor.positions = MeshBuffers.Positions(outer + inner)
        descriptor.normals = MeshBuffers.Normals(normals + normals.map { -$0 })
        var doubleSided = indices
        let offset = UInt32(vertices.count)
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            doubleSided.append(contentsOf: [indices[triangle] + offset, indices[triangle + 2] + offset, indices[triangle + 1] + offset])
        }
        descriptor.primitives = .triangles(doubleSided)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }
}