import Foundation
import Testing
import simd
@testable import weashion

struct FemaleMannequinTests {
    private struct Geometry: Decodable {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }

    @Test func posteriorUpperArmHasDistinctTorsoTransition() throws {
        let url = try #require(Bundle.main.url(forResource: "female_body_40k", withExtension: "json"))
        let geometry = try JSONDecoder().decode(Geometry.self, from: Data(contentsOf: url))
        for side: Float in [-1, 1] {
            for height: Float in [1.18, 1.20, 1.22] {
                let center: Float = 0.156 + 0.20 * (height - 1.20)
                let depths = try [center - 0.028, center, center + 0.028].map {
                    try #require(posteriorDepth(at: SIMD2<Float>(side * $0, height), in: geometry))
                }
                let indentation = depths[1] - (depths[0] + depths[2]) * 0.5
                #expect(indentation > 0.007)
                #expect(indentation < 0.020)
            }
        }
        var edges: [ParametricBody.Edge: Int] = [:]
        var neighbors = Array(repeating: [Int](), count: geometry.vertices.count)
        for offset in stride(from: 0, to: geometry.indices.count, by: 3) {
            for corner in 0..<3 {
                let first = Int(geometry.indices[offset + corner])
                let second = Int(geometry.indices[offset + (corner + 1) % 3])
                edges[ParametricBody.Edge(first, second), default: 0] += 1
                neighbors[first].append(second)
                neighbors[second].append(first)
            }
        }
        #expect(edges.values.allSatisfy { $0 == 2 })
        var visited: Set<Int> = [0]
        var pending = [0]
        while let index = pending.popLast() {
            for other in neighbors[index] where visited.insert(other).inserted {
                pending.append(other)
            }
        }
        #expect(visited.count == geometry.vertices.count)
    }

    @MainActor @Test func femalePreviewAndFittingUseTheSameCorrectedSurface() async throws {
        var variants = [UserBody.defaults(for: .female)]
        for frame in FemaleBodyFramePreset.allCases where frame != .neutral {
            var body = variants[0]
            body.femaleFramePreset = frame
            variants.append(body)
        }
        for preset in [BodyShapePreset.slim, .full, .muscular] {
            var body = variants[0]
            body.shapePreset = preset
            variants.append(body)
        }
        for height: Double in [150, 180] {
            var body = variants[0]
            body.height = height
            variants.append(body)
        }
        for scale: Double in [0.5, 1.5] {
            var body = variants[0]
            body.setShapeScale(scale, for: .latissimusSize)
            variants.append(body)
        }
        var adjusted = variants[0]
        adjusted.setShapeScale(1.5, for: .breastSize)
        adjusted.setPartScale(1.15, for: .leftUpperArm, mirrored: true)
        variants.append(adjusted)
        let renderer = BodyPreviewRenderer()
        for body in variants {
            let request = BodyPreviewRenderer.Request(body: body, base: .female)
            let preview = try #require(try await renderer.render(request))
            let result = try await renderer.prepareFitting(request)
            let fitted = result.fitted
            #expect(preview.surface.indices == fitted.surface.indices)
            #expect(preview.surface.vertices.count == fitted.surface.vertices.count)
            #expect(zip(preview.surface.vertices, fitted.surface.vertices).allSatisfy {
                simd_distance($0, $1) < 0.000001
            })
            #expect(fitted.surface.vertices.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            })
            let collision = try #require(fitted.collisionMesh)
            #expect(collision.vertices.count == fitted.surface.vertices.count)
            #expect(zip(collision.vertices, fitted.surface.vertices).allSatisfy {
                simd_distance($0 + fitted.anchor, $1) < 0.000001
            })
            #expect(fitted.anatomy?.isValid(vertexCount: fitted.surface.vertices.count) == true)
        }
    }

    private func posteriorDepth(at point: SIMD2<Float>, in geometry: Geometry) -> Float? {
        var depth: Float?
        for offset in stride(from: 0, to: geometry.indices.count, by: 3) {
            let first = geometry.vertices[Int(geometry.indices[offset])]
            let second = geometry.vertices[Int(geometry.indices[offset + 1])]
            let third = geometry.vertices[Int(geometry.indices[offset + 2])]
            let denominator = (second.y - third.y) * (first.x - third.x)
                + (third.x - second.x) * (first.y - third.y)
            guard abs(denominator) > 1e-12 else { continue }
            let a = ((second.y - third.y) * (point.x - third.x)
                + (third.x - second.x) * (point.y - third.y)) / denominator
            let b = ((third.y - first.y) * (point.x - third.x)
                + (first.x - third.x) * (point.y - third.y)) / denominator
            let c = 1 - a - b
            guard min(a, b, c) >= -0.00001 else { continue }
            let value = first.z * a + second.z * b + third.z * c
            depth = min(depth ?? value, value)
        }
        return depth
    }
}
