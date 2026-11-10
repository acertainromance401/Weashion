import Foundation
import ClothPhysics
import RealityKit
import Testing
import simd
@testable import weashion

@MainActor
@Suite(.serialized)
struct GarmentCategoryTests {
    @Test func shapeProjectionPreservesPinnedGeometryAndReportsBoundedResiduals() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1]
        let faces: [Int32] = [0, 1, 2]
        let context = try #require(body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer {
                weashion_cloth_create_body(points.baseAddress, 3, $0.baseAddress, 1, nil)
            }
        })
        defer { weashion_cloth_destroy(context) }
        for height: Float in [-0.02, 0.1] {
            let garment: [Float] = [-0.01, height, -0.01, 0, height, 0.01, 0.01, height, -0.01]
            #expect(garment.withUnsafeBufferPointer { points in
                faces.withUnsafeBufferPointer {
                    weashion_cloth_set_garment(context, points.baseAddress, 3, $0.baseAddress, 1, points.baseAddress)
                }
            } == 1)
            let invalid: [Float] = [0, 0.006, .nan]
            #expect(invalid.withUnsafeBufferPointer {
                weashion_cloth_project_shape(context, $0.baseAddress, 3, 8, nil)
            } == 0)
            let limits: [Float] = [0.006, 0.006, 0]
            #expect(limits.withUnsafeBufferPointer {
                weashion_cloth_project_shape(context, $0.baseAddress, 3, 8, { 1 })
            } == -1)
            var before = Array(repeating: Float.zero, count: garment.count)
            before.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
            #expect(before == garment)
            #expect(limits.withUnsafeBufferPointer {
                weashion_cloth_project_shape(context, $0.baseAddress, 3, 8, nil)
            } == 2)
            var output = before
            output.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
            #expect(Array(output[6..<9]) == Array(garment[6..<9]))
            #expect(weashion_cloth_final_contact_passes(context) <= 8)
            for index in 0..<3 {
                let delta = SIMD3<Float>(output[index * 3] - garment[index * 3],
                                         output[index * 3 + 1] - garment[index * 3 + 1],
                                         output[index * 3 + 2] - garment[index * 3 + 2])
                #expect(simd_length(delta) <= limits[index] + 0.000001)
            }
            if height < 0 {
                #expect(output[1] > height, "Invalid limits must not partially pin the first vertex")
                #expect(weashion_cloth_remaining_overlap(context) >= 0.019)
            } else {
                #expect(output == garment, "No gravity or wrinkle solving may run in shape mode")
            }
        }
    }

    @Test func displaySmoothingCannotIntroduceSkinPenetrationAcrossAClearEdge() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1]
        let triangle: [Int32] = [0, 1, 2]
        let context = try #require(body.withUnsafeBufferPointer { points in
            triangle.withUnsafeBufferPointer {
                weashion_cloth_create_body(points.baseAddress, 3, $0.baseAddress, 1, nil)
            }
        })
        defer { weashion_cloth_destroy(context) }
        var source = GarmentSurface()
        for z: Float in [-0.01, 0.01] {
            for (x, y): (Float, Float) in [(-0.03, 0.03), (-0.01, 0.001), (0.01, 0.001), (0.03, 0.03)] {
                source.vertices.append([x, y, z])
            }
        }
        for column in 0..<3 {
            let first = UInt32(column)
            source.indices += [first, first + 4, first + 1, first + 1, first + 4, first + 5]
        }
        func depth(_ point: SIMD3<Float>) -> Float {
            [point.x, point.y, point.z].withUnsafeBufferPointer { weashion_cloth_body_depth(context, $0.baseAddress) }
        }
        #expect(source.vertices.allSatisfy { depth($0) == 0 })
        let original = source.smoothed()
        #expect(original.vertices.contains { depth($0) > 0.0001 })
        let corrected = source.smoothed(bodyDepth: depth)
        #expect(corrected.vertices.allSatisfy { depth($0) == 0 })
        #expect(Array(corrected.vertices.prefix(source.vertices.count)) == source.vertices)
        #expect(corrected.indices == original.indices)
        let points = corrected.vertices.flatMap { [$0.x, $0.y, $0.z] }
        let indices = corrected.indices.map { Int32($0) }
        var overlap: Float = -1
        let measured = points.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer {
                weashion_cloth_measure_body_overlap(context, points.baseAddress, Int32(corrected.vertices.count),
                    $0.baseAddress, Int32(indices.count / 3), &overlap, nil)
            }
        }
        #expect(measured == 1 && overlap == 0)
        #expect(weashion_cloth_body_depth(context, nil).isNaN)
        #expect(weashion_cloth_measure_body_overlap(context, nil, 3, nil, 1, &overlap, nil) == 0)
        #expect(points.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer {
                weashion_cloth_measure_body_overlap(context, points.baseAddress, Int32(corrected.vertices.count),
                    $0.baseAddress, Int32(indices.count / 3), &overlap, { 1 })
            }
        } == -1)
    }

    @Test func layerCorrectionCannotPushClothThroughAnAdjacentBodyArm() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1,
                             0.025, -1, -1, 0.025, -1, 1, 0.025, 1, 0,
                             -1, 0.02, -1, 0, 0.02, 1, 1, 0.02, -1]
        let faces: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
        let groups: [UInt8] = [0, 0, 1]
        let arms: [UInt8] = [0, 1, 0]
        let context = try #require(body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer { faces in
                groups.withUnsafeBufferPointer { groups in
                    arms.withUnsafeBufferPointer {
                        weashion_cloth_create_layered_body(points.baseAddress, 9, faces.baseAddress, 3,
                                                           $0.baseAddress, groups.baseAddress)
                    }
                }
            }
        })
        defer { weashion_cloth_destroy(context) }
        let garment: [Float] = [0.018, 0.01, -0.001, 0.019, 0.01, 0.001, 0.02, 0.01, -0.001]
        let triangle: [Int32] = [0, 1, 2]
        #expect(garment.withUnsafeBufferPointer { points in
            triangle.withUnsafeBufferPointer {
                weashion_cloth_set_garment(context, points.baseAddress, 3, $0.baseAddress, 1, points.baseAddress)
            }
        } == 1)
        let origins = Array(repeating: Float(0), count: 9)
        let axes: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
        #expect(origins.withUnsafeBufferPointer { origins in
            axes.withUnsafeBufferPointer { weashion_cloth_set_contact_guides(context, origins.baseAddress, $0.baseAddress, 3) }
        } == 1)
        var invalidAxes = axes
        invalidAxes[8] = 2
        #expect(origins.withUnsafeBufferPointer { origins in
            invalidAxes.withUnsafeBufferPointer { weashion_cloth_set_contact_guides(context, origins.baseAddress, $0.baseAddress, 3) }
        } == 0)
        var status: Int32 = 1
        for _ in 0..<72 where status == 1 {
            status = weashion_cloth_step(context, 1, nil)
            var positions = Array(repeating: Float(0), count: 9)
            positions.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
            #expect([positions[0], positions[3], positions[6]].allSatisfy { $0 < 0.0251 })
        }
        #expect(status == 2)
        #expect(weashion_cloth_remaining_overlap(context) < 0.001)
    }

    @Test func innerSurfaceCannotBeHiddenByANearerBodyTriangle() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1,
                             -1, 0.02, -1, 0, 0.02, 1, 1, 0.02, -1]
        let groups: [UInt8] = [0, 1]
        for innerFace: [Int32] in [[3, 4, 5], [3, 5, 4]] {
            let faces: [Int32] = [0, 1, 2] + innerFace
            let context = try #require(body.withUnsafeBufferPointer { points in
                faces.withUnsafeBufferPointer { faces in
                    groups.withUnsafeBufferPointer { groups in
                        weashion_cloth_create_layered_body(points.baseAddress, 6, faces.baseAddress, 2, nil, groups.baseAddress)
                    }
                }
            })
            defer { weashion_cloth_destroy(context) }
            for height: Float in [0.006, 0.03] {
                let garment: [Float] = [-0.01, height, -0.01, 0, height, 0.01, 0.01, height, -0.01]
                let triangle: [Int32] = [0, 1, 2]
                let initialized = garment.withUnsafeBufferPointer { positions in
                    triangle.withUnsafeBufferPointer { indices in
                        weashion_cloth_set_garment(context, positions.baseAddress, 3, indices.baseAddress, 1, positions.baseAddress)
                    }
                }
                #expect(initialized == 1)
                var status: Int32 = 1
                for _ in 0..<72 where status == 1 { status = weashion_cloth_step(context, 1, nil) }
                #expect(status == 2)
                var result = Array(repeating: Float(0), count: 9)
                result.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
                #expect([result[1], result[4], result[7]].allSatisfy { $0 >= 0.023 })
            }
        }
        let faces: [Int32] = [0, 1, 2, 3, 4, 5]
        let invalid: [UInt8] = [0, 4]
        let rejected = body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer { faces in
                invalid.withUnsafeBufferPointer { groups in
                    weashion_cloth_create_layered_body(points.baseAddress, 6, faces.baseAddress, 2, nil, groups.baseAddress)
                }
            }
        }
        #expect(rejected == nil)
    }

    @Test func pinnedPenetrationRemainsReportedWithoutUselessFinalPasses() throws {
        let body: [Float] = [-1, 0.02, -1, 0, 0.02, 1, 1, 0.02, -1]
        let indices: [Int32] = [0, 1, 2]
        let garment: [Float] = [-0.01, 0.006, -0.01, 0, 0.006, 0.01, 0.01, 0.006, -0.01]
        let context = try #require(body.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer { triangles in
                weashion_cloth_create_body(points.baseAddress, 3, triangles.baseAddress, 1, nil)
            }
        })
        defer { weashion_cloth_destroy(context) }
        let initialized = garment.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer { triangles in
                weashion_cloth_set_garment(context, points.baseAddress, 3, triangles.baseAddress, 1, points.baseAddress)
            }
        }
        #expect(initialized == 1)
        #expect(indices.withUnsafeBufferPointer { weashion_cloth_pin_vertices(context, $0.baseAddress, 3) } == 1)
        var status: Int32 = 1
        for _ in 0..<72 where status == 1 {
            status = weashion_cloth_step(context, 1, nil)
        }
        #expect(status == 2)
        #expect(abs(weashion_cloth_remaining_overlap(context) - 0.014) < 0.00001)
        #expect(weashion_cloth_final_contact_passes(context) == 0)
        var positions = Array(repeating: Float(0), count: garment.count)
        positions.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
        #expect(positions == garment)
        weashion_cloth_clear_garment(context)
        #expect(weashion_cloth_final_contact_passes(context) == 0)
    }

    @Test func openInnerHemDoesNotExtendAnInfiniteCollisionPlane() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1,
                             0, 0.02, -0.1, 0, 0.02, 0.1, 0.02, 0.04, 0]
        let faces: [Int32] = [0, 1, 2, 3, 4, 5]
        let groups: [UInt8] = [0, 1]
        let context = try #require(body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer { triangles in
                groups.withUnsafeBufferPointer { groups in
                    weashion_cloth_create_layered_body(points.baseAddress, 6, triangles.baseAddress, 2, nil, groups.baseAddress)
                }
            }
        })
        defer { weashion_cloth_destroy(context) }
        let garment: [Float] = [-0.004, 0.006, -0.002, -0.003, 0.006, 0.002, -0.002, 0.006, -0.002]
        let indices: [Int32] = [0, 1, 2]
        let initialized = garment.withUnsafeBufferPointer { positions in
            indices.withUnsafeBufferPointer { triangles in
                weashion_cloth_set_garment(context, positions.baseAddress, 3, triangles.baseAddress, 1, positions.baseAddress)
            }
        }
        #expect(initialized == 1)
        #expect(weashion_cloth_step(context, 1, nil) == 1)
        var result = Array(repeating: Float(0), count: 9)
        result.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
        #expect([result[1], result[4], result[7]].allSatisfy { (0.004...0.006).contains($0) })
    }

    @Test func excludingSleeveLayersDoesNotDisableSkinArmContact() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1,
                             -1, 0.02, -1, 0, 0.02, 1, 1, 0.02, -1,
                             -1, 0.04, -1, 0, 0.04, 1, 1, 0.04, -1]
        let faces: [Int32] = [0, 1, 2, 3, 4, 5, 6, 8, 7]
        let groups: [UInt8] = [0, 0, 1]
        let arms: [UInt8] = [0, 1, 1]
        let context = try #require(body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer { triangles in
                groups.withUnsafeBufferPointer { groups in
                    arms.withUnsafeBufferPointer { arms in
                        weashion_cloth_create_layered_body(points.baseAddress, 9, triangles.baseAddress, 3, arms.baseAddress, groups.baseAddress)
                    }
                }
            }
        })
        defer { weashion_cloth_destroy(context) }
        let garment: [Float] = [-0.01, 0.016, -0.01, 0, 0.016, 0.01, 0.01, 0.016, -0.01]
        let indices: [Int32] = [0, 1, 2]
        let limits = Array(repeating: Float(0.05), count: 3)
        let expected: [(UInt8, ClosedRange<Float>)] = [(0, 0.043...0.05), (2, 0.023...0.03), (3, 0.004...0.01), (4, 0.043...0.05)]
        for (mask, range) in expected {
            let initialized = garment.withUnsafeBufferPointer { positions in
                indices.withUnsafeBufferPointer { triangles in
                    weashion_cloth_set_garment(context, positions.baseAddress, 3, triangles.baseAddress, 1, positions.baseAddress)
                }
            }
            #expect(initialized == 1)
            let flags = Array(repeating: mask, count: 3)
            #expect(flags.withUnsafeBufferPointer { flags in
                limits.withUnsafeBufferPointer { limits in
                    weashion_cloth_configure(context, flags.baseAddress, limits.baseAddress, 3, 4, 0.18)
                }
            } == 1)
            var status: Int32 = 1
            for _ in 0..<72 where status == 1 { status = weashion_cloth_step(context, 1, nil) }
            #expect(status == 2)
            var result = Array(repeating: Float(0), count: 9)
            result.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
            #expect([result[1], result[4], result[7]].allSatisfy { range.contains($0) })
        }
    }

    @Test func infeasiblePinnedLayerKeepsMaterialBoundsAndReportsOverlap() throws {
        let body: [Float] = [-1, 0, -1, 0, 0, 1, 1, 0, -1,
                             -1, 0.04, -1, 0, 0.04, 1, 1, 0.04, -1]
        let faces: [Int32] = [0, 1, 2, 3, 4, 5]
        let groups: [UInt8] = [0, 1]
        let context = try #require(body.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer { triangles in
                groups.withUnsafeBufferPointer { groups in
                    weashion_cloth_create_layered_body(points.baseAddress, 6, triangles.baseAddress, 2, nil, groups.baseAddress)
                }
            }
        })
        defer { weashion_cloth_destroy(context) }
        let garment: [Float] = [-0.01, 0.006, -0.01, 0, 0.006, 0.01, 0.01, 0.006, -0.01]
        let indices: [Int32] = [0, 1, 2]
        let initialized = garment.withUnsafeBufferPointer { positions in
            indices.withUnsafeBufferPointer { triangles in
                weashion_cloth_set_garment(context, positions.baseAddress, 3, triangles.baseAddress, 1, positions.baseAddress)
            }
        }
        #expect(initialized == 1)
        #expect(indices.withUnsafeBufferPointer { weashion_cloth_pin_vertices(context, $0.baseAddress, 2) } == 1)
        var status: Int32 = 1
        for _ in 0..<72 where status == 1 { status = weashion_cloth_step(context, 1, nil) }
        #expect(status == 2)
        #expect(weashion_cloth_final_contact_passes(context) < 96)
        #expect(weashion_cloth_remaining_overlap(context) > 0.03)
        #expect(weashion_cloth_max_strain(context) < 2)
    }

    private let resources = ["meshy_long_sleeve", "meshy_hoodie", "meshy_dress_pants",
                             "meshy_jeans", "meshy_bomber", "meshy_sneakers"]

    private func asset(_ resource: String) throws -> GarmentMeshAsset {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
        let value = try JSONDecoder().decode(GarmentMeshAsset.self, from: Data(contentsOf: url))
        let valid = value.isValid
        #expect(valid, "\(resource) must satisfy runtime geometry and binding limits")
        return value
    }

    private func resized(_ source: GarmentMeshAsset, definition: GarmentDefinition) throws -> GarmentMeshAsset {
        if let dimensions = definition.pattern.dimensions {
            return try #require(source.sizing?.resized(source, to: dimensions,
                preservingNeckShape: definition.pattern.fittingMode == .shapePreserving))
        }
        if let dimensions = definition.pattern.trouserDimensions {
            return try #require(LowerGarmentFitter.resized(source, to: dimensions))
        }
        return try #require(definition.pattern.footwearDimensions.flatMap { LowerGarmentFitter.resized(source, to: $0) })
    }

    private func meanDistance(_ first: [SIMD3<Float>], _ second: [SIMD3<Float>]) -> Float {
        guard first.count == second.count, !first.isEmpty else { return .infinity }
        return zip(first, second).reduce(Float.zero) { $0 + simd_distance($1.0, $1.1) } / Float(first.count)
    }

    private func originalHoodieMedium() throws -> GarmentDefinition {
        // Freeze the pre-rebase fixture; the approved 175 cm baseline has a separate test.
        let sample = try #require(GarmentCatalog.samples.first { $0.id == "meshy-hoodie-m" })
        var input = try #require(sample.measurements?.shortSleeve)
        input.length = 70
        input.shoulderWidth = 52
        input.chestWidth = 58
        input.sleeveLength = 60
        input.sleeveWidthPercent = nil
        return try #require(GarmentMeasurements.shortSleeve(input).applying(to: sample))
    }

    private func maximumEdgeRatio(_ result: GarmentDrapeResult) -> Float {
        var maximum: Float = 1
        for offset in stride(from: 0, to: result.asset.indices.count, by: 3) {
            for corner in 0..<3 {
                let first = Int(result.asset.indices[offset + corner])
                let second = Int(result.asset.indices[offset + (corner + 1) % 3])
                let reference = simd_distance(result.asset.vertices[first], result.asset.vertices[second])
                if reference >= 0.005 {
                    maximum = max(maximum, simd_distance(result.positions[first], result.positions[second]) / reference)
                }
            }
        }
        return maximum
    }

    private func newSharpEdges(source: GarmentMeshAsset, positions: [SIMD3<Float>]) -> Int {
        var adjacent: [UInt64: (SIMD3<Float>, SIMD3<Float>)] = [:]
        var count = 0
        for offset in stride(from: 0, to: source.indices.count, by: 3) {
            let face = (0..<3).map { Int(source.indices[offset + $0]) }
            let before = simd_cross(source.vertices[face[1]] - source.vertices[face[0]],
                                    source.vertices[face[2]] - source.vertices[face[0]])
            let after = simd_cross(positions[face[1]] - positions[face[0]],
                                   positions[face[2]] - positions[face[0]])
            guard simd_length_squared(before) > 1e-14, simd_length_squared(after) > 1e-14 else { continue }
            let normals = (simd_normalize(before), simd_normalize(after))
            for corner in 0..<3 {
                let first = face[corner], second = face[(corner + 1) % 3]
                guard simd_distance(source.vertices[first], source.vertices[second]) >= 0.005 else { continue }
                let key = UInt64(min(first, second)) << 32 | UInt64(max(first, second))
                if let previous = adjacent[key] {
                    if simd_dot(previous.0, normals.0) > 0.866 && simd_dot(previous.1, normals.1) < 0 {
                        count += 1
                    }
                } else {
                    adjacent[key] = normals
                }
            }
        }
        return count
    }

    private func checkShapePreservingBodyContact(_ result: GarmentDrapeResult,
                                                 body: GarmentBodySnapshot) throws {
        let collision = try #require(body.collision)
        let points = collision.vertices.flatMap { [$0.x, $0.y, $0.z] }
        let faces = collision.indices.map { Int32($0) }
        let context = try #require(points.withUnsafeBufferPointer { points in
            faces.withUnsafeBufferPointer {
                weashion_cloth_create_body(points.baseAddress, Int32(collision.vertices.count),
                                           $0.baseAddress, Int32(faces.count / 3), nil)
            }
        })
        defer { weashion_cloth_destroy(context) }
        let placement = GarmentFitter.placement(for: result.asset, body: body.fitProfile, preservingShape: true)
        let fixed = Set(placement.pins.map { Int($0) })
        var maximumFreeDepth: Float = 0
        var maximumFreePoint = SIMD3<Float>.zero
        var maximumFixedContactDepth: Float = 0
        func measure(_ point: SIMD3<Float>, touchingFixedGeometry: Bool) {
            let depth = [point.x, point.y, point.z].withUnsafeBufferPointer {
                weashion_cloth_body_depth(context, $0.baseAddress)
            }
            #expect(depth.isFinite)
            if touchingFixedGeometry {
                maximumFixedContactDepth = max(maximumFixedContactDepth, depth)
            } else {
                if depth > maximumFreeDepth { maximumFreePoint = point }
                maximumFreeDepth = max(maximumFreeDepth, depth)
            }
        }
        for index in result.positions.indices {
            measure(result.positions[index], touchingFixedGeometry: fixed.contains(index))
        }
        let samples: [SIMD3<Float>] = [
            [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5], [1 / 3, 1 / 3, 1 / 3]
        ]
        for offset in stride(from: 0, to: result.asset.indices.count, by: 3) {
            let face = (0..<3).map { Int(result.asset.indices[offset + $0]) }
            for weights in samples {
                let point = (0..<3).reduce(SIMD3<Float>.zero) {
                    $0 + result.positions[face[$1]] * weights[$1]
                }
                measure(point, touchingFixedGeometry: (0..<3).contains {
                    weights[$0] > 0 && fixed.contains(face[$0])
                })
            }
        }
        #expect(maximumFreeDepth < 0.003, "Free body/sleeve contacts must still clear skin")
        #expect(result.remainingOverlap + 0.00001 >= maximumFixedContactDepth,
                "Preserved hood and undersized fixed cuffs must not hide their real overlap")
        #expect(result.displayBodyOverlap <= max(maximumFixedContactDepth, 0.003) + 0.001)
        print("HOODIE_CONTACT free=\(maximumFreeDepth) point=\(maximumFreePoint) fixed=\(maximumFixedContactDepth) display=\(result.displayBodyOverlap)")
    }

    @Test func sixConvertedResourcesHaveCategoryBindingsAndThreeDistinctSizes() throws {
        #expect(GarmentCatalog.samples.count == 21)
        for resource in resources {
            let source = try asset(resource)
            #expect(source.vertices.count < 12000)
            #expect(source.indices.count / 3 < 40000)
            #expect(source.collisionArmTriangles.count == source.indices.count / 3)
            #expect(source.collisionArmTriangles.contains(1) == (source.fitting != nil))
            let sizes = GarmentCatalog.samples.filter { $0.pattern.meshResource == resource }
            #expect(Set(sizes.map(\.selectionLabel)) == Set(["S", "M", "L"]))
            #expect(Set(sizes.map(\.pattern.id)).count == 1)
            #expect(sizes.allSatisfy { $0.isValid && $0.measurements?.isValid == true })
            for size in sizes {
                let result = try resized(source, definition: size)
                let valid = result.isValid
                if !valid {
                    let areas = stride(from: 0, to: result.indices.count, by: 3).map { offset in
                        let points = (0..<3).map { result.vertices[Int(result.indices[offset + $0])] }
                        return simd_length_squared(simd_cross(points[1] - points[0], points[2] - points[0]))
                    }
                    print("GARMENT_INVALID \(resource) \(size.selectionLabel) minCrossSquared=\(areas.min() ?? 0) badAreas=\(areas.filter { $0 <= 1e-14 }.count)")
                }
                #expect(valid, "\(resource) \(size.selectionLabel)")
                #expect(result.indices == source.indices)
                #expect(result.vertices.count == source.vertices.count)
            }
            let small = try resized(source, definition: #require(sizes.first { $0.selectionLabel == "S" }))
            let large = try resized(source, definition: #require(sizes.first { $0.selectionLabel == "L" }))
            #expect(meanDistance(small.vertices, large.vertices) > 0.005, "\(resource) size geometry must visibly change")
            switch try #require(sizes.first).kind {
            case .pants:
                #expect(source.trousers != nil && source.sizing == nil && source.footwear == nil)
                #expect(sizes.allSatisfy { $0.pattern.anchor == .waist })
            case .shoes:
                #expect(source.footwear != nil && source.sizing == nil && source.trousers == nil)
                #expect(sizes.allSatisfy { $0.pattern.anchor == .feet })
            default:
                #expect(source.sizing != nil && source.fitting != nil)
                #expect(source.sleeves?.isValid == true)
                #expect(sizes.allSatisfy { $0.pattern.anchor == .shoulders })
                for size in sizes {
                    let dimensions = try #require(size.pattern.dimensions)
                    let input = GarmentSizeInput(dimensions: dimensions)
                    #expect(abs(input.specification.sleeveOpening - dimensions.sleeveOpening) < 0.00001,
                            "Saving an unchanged long sleeve must not replace its cuff with a T-shirt opening")
                }
            }
        }
    }

    @Test func lowerMeasurementsRoundTripAndCannotBeAppliedToTheWrongCategory() throws {
        let values: [GarmentMeasurements] = [.shortSleeve(.medium), .trousers(.init()), .footwear(.init())]
        for input in values {
            #expect(try JSONDecoder().decode(GarmentMeasurements.self, from: JSONEncoder().encode(input)) == input)
        }
        let pants = try #require(GarmentCatalog.samples.first { $0.kind == .pants })
        let shoes = try #require(GarmentCatalog.samples.first { $0.kind == .shoes })
        let top = try #require(GarmentCatalog.samples.first)
        #expect(values[0].applying(to: pants) == nil)
        #expect(values[1].applying(to: shoes) == nil)
        #expect(values[2].applying(to: top) == nil)
        #expect(values[1].applying(to: pants)?.pattern.trouserDimensions == TrouserSizeInput().specification)
        #expect(values[2].applying(to: shoes)?.pattern.footwearDimensions == FootwearSizeInput().specification)
        #expect(!TrouserSizeInput(waistWidth: .nan).isValid)
        #expect(!FootwearSizeInput(length: .infinity).isValid)
        #expect(!FootwearSizeInput(width: 49).isValid)
        let incompatible = ProductSize(label: "M", measurements: values[0])
        let product = GarmentProduct(name: "Pants", kind: .pants, templateID: pants.pattern.id)
        #expect(product.definition(for: incompatible, in: GarmentCatalog.samples) == nil)
        #expect(!product.sizeIsComplete(incompatible))
        #expect(product.sizeValidationMessage(incompatible) != nil)
    }

    @Test func hoodieLengthDoesNotIncludeOrFlattenItsHood() throws {
        let source = try asset("meshy_hoodie")
        let sizing = try #require(source.sizing)
        let converted = try #require(sizing.resized(source, to: sizing.reference))
        let before = try #require(source.vertices.map(\.y).max())
        let after = try #require(converted.vertices.map(\.y).max())
        #expect(before > 0.1)
        #expect(after > 0.1)
        #expect(abs(before - after) < 0.005)
        #expect(abs(try #require(converted.vertices.map(\.y).min()) + sizing.reference.length) < 0.005)
    }

    @Test func shapePreservingHoodieModeSurvivesEditsAndKeepsTheHoodAcrossSizes() throws {
        let source = try asset("meshy_hoodie")
        let weights = try #require(source.fitting).weights
        let neck = weights.indices.filter { weights[$0].preservesNeckShape(at: source.vertices[$0]) }
        #expect(neck.count > 100)
        let hoodie = GarmentCatalog.samples.filter { $0.pattern.meshResource == "meshy_hoodie" }
        #expect(hoodie.count == 3)
        #expect(GarmentCatalog.samples.filter { $0.pattern.fittingMode != nil }.count == 3)
        for definition in hoodie {
            #expect(definition.pattern.fittingMode == .shapePreserving)
            let roundTrip = try JSONDecoder().decode(GarmentDefinition.self, from: JSONEncoder().encode(definition))
            #expect(roundTrip == definition)
            let changed = try resized(source, definition: definition)
            for index in neck {
                #expect(simd_distance(changed.vertices[index], source.vertices[index]) < 0.000001)
            }
            let measurements = try #require(definition.measurements)
            let edited = try #require(measurements.applying(to: definition))
            #expect(edited.pattern.fittingMode == .shapePreserving)
        }
        let legacy = Data("""
        {"id":"legacy","version":1,"source":"mesh","meshResource":"legacy"}
        """.utf8)
        #expect(try JSONDecoder().decode(GarmentPatternDescriptor.self, from: legacy).fittingMode == nil)
    }

    @Test func shapePreservingHoodieKeepsItsPreviewShapeOnThe172cmBody() async throws {
        await GarmentDraper.shared.releaseCachedResources()
        var body = UserBody()
        body.height = 172
        let request = BodyPreviewRenderer.Request(body: body, base: .male)
        let worker = BodyPreviewRenderer()
        let fitted = try await worker.prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        let definition = try originalHoodieMedium()
        let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
        let start = ContinuousClock.now
        let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
        let duration = start.duration(to: .now)
        let weights = try #require(result.asset.fitting).weights
        var maximumMovement: Float = 0
        for index in result.positions.indices {
            let distance = simd_distance(result.positions[index], preview.positions[index])
            maximumMovement = max(maximumMovement, distance)
            #expect(distance <= 0.04001)
            if weights[index].preservesNeckShape(at: result.asset.vertices[index]) { #expect(distance < 0.000001) }
        }
        #expect(maximumEdgeRatio(result) < 3)
        #expect(result.remainingOverlap >= result.displayBodyOverlap)
        #expect(result.remainingOverlap.isFinite && result.maximumStrain.isFinite)
        try checkShapePreservingBodyContact(result, body: snapshot)
        print("HOODIE_SHAPE_172 latency=\(duration) movement=\(maximumMovement) overlap=\(result.remainingOverlap) displayBody=\(result.displayBodyOverlap) edgeRatio=\(maximumEdgeRatio(result))")
        struct Diagnostic: Encodable {
            let body: Geometry
            let initial: Geometry
            let final: Geometry
            let anchor: SIMD3<Float>
        }
        let diagnostic = Diagnostic(body: .init(vertices: fitted.surface.vertices, indices: fitted.surface.indices),
            initial: .init(vertices: preview.surface.vertices, indices: preview.surface.indices),
            final: .init(vertices: result.displayVertices, indices: result.displayIndices), anchor: fitted.anchor)
        let capture = FileManager.default.temporaryDirectory.appending(path: "HoodieShape172.json")
        try JSONEncoder().encode(diagnostic).write(to: capture, options: .atomic)
        print("HOODIE_SHAPE_CAPTURE \(capture.path)")
    }

    @Test func hoodieApprovedMediumKeepsItsLabelsAndCoversShoulders() async throws {
        let source = try asset("meshy_hoodie")
        #expect(source.vertices.count == 8669)
        #expect(source.indices.count == 16792 * 3, "Preserve the approved resource topology")
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        let fitted = try await BodyPreviewRenderer().prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        let definition = try #require(GarmentCatalog.samples.first { $0.id == "meshy-hoodie-m" })
        let input = try #require(definition.measurements?.shortSleeve)
        #expect(input.length == 65 && input.shoulderWidth == 58 && input.chestWidth == 56 && input.sleeveLength == 50)
        #expect(input.sleeveWidthPercent == 80)
        let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
        let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
        #expect(newSharpEdges(source: source, positions: result.positions) < 15)
        #expect(maximumEdgeRatio(result) < 3)
        try checkShapePreservingBodyContact(result, body: snapshot)
        struct Capture: Encodable {
            let body: Geometry
            let final: Geometry
            let initial: Geometry
            let anchor: SIMD3<Float>
        }
        let diagnostic = Capture(body: .init(vertices: fitted.surface.vertices, indices: fitted.surface.indices),
            final: .init(vertices: result.displayVertices, indices: result.displayIndices),
            initial: .init(vertices: preview.surface.vertices, indices: preview.surface.indices), anchor: fitted.anchor)
        let capture = FileManager.default.temporaryDirectory.appending(path: "HoodieApprovedMedium175.json")
        try JSONEncoder().encode(diagnostic).write(to: capture, options: .atomic)
        print("HOODIE_APPROVED folds=\(newSharpEdges(source: source, positions: result.positions)) overlap=\(result.remainingOverlap) capture=\(capture.path)")
    }

    @Test func hoodieShouldersAndWidthsKeepContinuousPanels() async throws {
        await GarmentDraper.shared.releaseCachedResources()
        var body = UserBody()
        body.height = 172
        let request = BodyPreviewRenderer.Request(body: body, base: .male)
        let fitted = try await BodyPreviewRenderer().prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        let source = try asset("meshy_hoodie")
        let sample = try #require(GarmentCatalog.samples.first {
            $0.pattern.meshResource == "meshy_hoodie" && $0.selectionLabel == "M"
        })
        struct Stages: Encodable {
            let body: Geometry
            let bodySections: [GarmentFitSection]
            let armSections: [GarmentFitSection]
            let legSections: [GarmentFitSection]
            let handSections: [GarmentFitSection]
            let wrist: GarmentFitSection?
            let shoulderWidth: Float
            let shoulderHeight: Float
            let sizedAsset: GarmentMeshAsset
            let source: Geometry
            let sized: Geometry
            let initial: Geometry
            let final: Geometry
            let anchor: SIMD3<Float>
        }
        let profile = try #require(fitted.profile)
        for percent: Double in [80, 100, 120] {
            var input = try #require(sample.measurements?.shortSleeve)
            input.sleeveWidthPercent = percent / GarmentSizeLabelCalibration(templateID: sample.pattern.id).sleeveWidth
            let saved = try JSONDecoder().decode(GarmentSizeInput.self, from: JSONEncoder().encode(input))
            #expect(saved == input)
            let definition = input.applying(to: sample)
            let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
            let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
            let sizedFolds = newSharpEdges(source: source, positions: result.asset.vertices)
            let initialFolds = newSharpEdges(source: source, positions: preview.positions)
            let finalFolds = newSharpEdges(source: source, positions: result.positions)
            print("HOODIE_PANEL width=\(percent) sizedFolds=\(sizedFolds) initialFolds=\(initialFolds) finalFolds=\(finalFolds) edgeRatio=\(maximumEdgeRatio(result)) overlap=\(result.remainingOverlap)")
            let stages = Stages(body: .init(vertices: fitted.surface.vertices, indices: fitted.surface.indices),
                bodySections: [profile.hip, profile.waist, profile.chest],
                armSections: profile.rightArmSections, legSections: profile.rightLegSections,
                handSections: profile.rightHandSections,
                wrist: profile.rightWrist, shoulderWidth: profile.shoulderWidth, shoulderHeight: profile.shoulderHeight,
                sizedAsset: result.asset,
                source: .init(vertices: source.vertices, indices: source.indices),
                sized: .init(vertices: result.asset.vertices, indices: source.indices),
                initial: .init(vertices: preview.surface.vertices, indices: preview.surface.indices),
                final: .init(vertices: result.displayVertices, indices: result.displayIndices), anchor: fitted.anchor)
            let path = FileManager.default.temporaryDirectory.appending(path: "HoodiePanels\(Int(percent)).json")
            try JSONEncoder().encode(stages).write(to: path, options: .atomic)
            print("HOODIE_PANEL_CAPTURE \(path.path)")
            #expect(initialFolds < 15, "Initial arm placement must not introduce folded panels")
            #expect(finalFolds < 15, "Originally smooth panel edges must not become sharp folded ridges")
            #expect(maximumEdgeRatio(result) < 3)
            #expect(result.asset.isValid)
            let dimensions = try #require(result.asset.sizing).reference
            #expect(GarmentSizeInput(dimensions: dimensions).sleeveWidthPercent == input.sleeveWidthPercent)
        }
    }

    @Test func hoodiePanelsStayContinuousOnFemaleMedium() async throws {
        let request = BodyPreviewRenderer.Request(body: UserBody.defaults(for: .female), base: .female)
        let fitted = try await BodyPreviewRenderer().prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        let definition = try originalHoodieMedium()
        let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
        let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
        let source = try asset("meshy_hoodie")
        #expect(newSharpEdges(source: source, positions: preview.positions) < 15)
        #expect(newSharpEdges(source: source, positions: result.positions) < 15)
        #expect(maximumEdgeRatio(result) < 3)
        try checkShapePreservingBodyContact(result, body: snapshot)
        print("HOODIE_FEMALE initialFolds=\(newSharpEdges(source: source, positions: preview.positions)) finalFolds=\(newSharpEdges(source: source, positions: result.positions)) edgeRatio=\(maximumEdgeRatio(result)) overlap=\(result.remainingOverlap)")
    }

    @Test func shapePreservingHoodieFitsThreeSizesOnBothBodyBases() async throws {
        let worker = BodyPreviewRenderer()
        let definitions = GarmentCatalog.samples.filter { $0.pattern.meshResource == "meshy_hoodie" }
        for base in [MannequinBase.male, .female] {
            let request = BodyPreviewRenderer.Request(body: UserBody.defaults(for: base), base: base)
            let fitted = try await worker.prepareFitting(request).fitted
            let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                              collision: fitted.collisionMesh, fitProfile: fitted.profile)
            var ease: [Float] = []
            var poses: [[SIMD3<Float>]] = []
            for definition in definitions {
                let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
                let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
                let fitting = try #require(result.asset.fitting)
                for index in result.positions.indices {
                    let movement = simd_distance(result.positions[index], preview.positions[index])
                    #expect(movement <= 0.04001)
                    if fitting.weights[index].preservesNeckShape(at: result.asset.vertices[index]) {
                        #expect(movement < 0.000001)
                    }
                }
                #expect(maximumEdgeRatio(result) < 3)
                #expect(result.remainingOverlap.isFinite && result.maximumStrain.isFinite)
                if maximumEdgeRatio(result) >= 3 {
                    var worst: (first: Int, second: Int, ratio: Float) = (0, 0, 0)
                    for offset in stride(from: 0, to: result.asset.indices.count, by: 3) {
                        for corner in 0..<3 {
                            let first = Int(result.asset.indices[offset + corner])
                            let second = Int(result.asset.indices[offset + (corner + 1) % 3])
                            let reference = simd_distance(result.asset.vertices[first], result.asset.vertices[second])
                            if reference >= 0.005 {
                                let ratio = simd_distance(result.positions[first], result.positions[second]) / reference
                                if ratio > worst.ratio { worst = (first, second, ratio) }
                            }
                        }
                    }
                    for index in [worst.first, worst.second] {
                        print("HOODIE_BAD_EDGE base=\(base.rawValue) size=\(definition.selectionLabel) index=\(index) source=\(result.asset.vertices[index]) initial=\(preview.positions[index]) final=\(result.positions[index]) weight=\(fitting.weights[index])")
                    }
                }
                ease.append(try #require(result.summary).chestEase)
                poses.append(result.positions)
                print("HOODIE_SHAPE_SIZE base=\(base.rawValue) size=\(definition.selectionLabel) edgeRatio=\(maximumEdgeRatio(result)) overlap=\(result.remainingOverlap)")
            }
            #expect(try #require(ease.max()) - #require(ease.min()) > 0.05)
            #expect(meanDistance(try #require(poses.first), try #require(poses.last)) > 0.005)
        }
    }

    @Test func longSleevesKeepTheirMeasuredCuffsAndFollowTheWearersArms() async throws {
        let worker = BodyPreviewRenderer()
        let body = try await worker.prepareFitting(.init(body: UserBody(), base: .male)).fitted.profile
        for resource in ["meshy_long_sleeve", "meshy_hoodie"] {
            let source = try asset(resource)
            let definition = try #require(GarmentCatalog.samples.first {
                $0.pattern.meshResource == resource && $0.selectionLabel == "M"
            })
            let prepared = try resized(source, definition: definition)
            let sizing = try #require(prepared.sizing)
            func center(_ trim: GarmentTrim) -> SIMD3<Float> {
                trim.vertices.reduce(SIMD3<Float>.zero) { $0 + prepared.vertices[$1] } / Float(trim.vertices.count)
            }
            let cuff = try #require(prepared.trims.min {
                simd_distance_squared(center($0), sizing.rightCuff) < simd_distance_squared(center($1), sizing.rightCuff)
            })
            func circumference(_ positions: [SIMD3<Float>]) -> Float {
                let loop = cuff.vertices.map { positions[$0] }
                return zip(loop, Array(loop.dropFirst()) + [loop[0]]).reduce(Float.zero) { $0 + simd_distance($1.0, $1.1) }
            }
            #expect(abs(circumference(prepared.vertices) - sizing.reference.sleeveOpening) < 0.015)
            let fitted = GarmentFitter.positions(for: prepared, body: body)
            let cuffCenter = cuff.vertices.reduce(SIMD3<Float>.zero) { $0 + fitted[$1] } / Float(cuff.vertices.count)
            #expect(cuffCenter.x > 0)
            #expect(cuffCenter.y < body.chest.center.y - 0.10)
            #expect(abs(circumference(fitted) - circumference(prepared.vertices)) < 0.015,
                    "Arm placement must not silently expand a measured cuff to the wearer's arm size")
        }
    }

    @Test func measuredSleeveFramesPreserveTheSourceFrontAndResizeWithTheGarment() throws {
        for resource in ["meshy_long_sleeve", "meshy_hoodie", "meshy_bomber"] {
            let source = try asset(resource)
            let binding = try #require(source.sleeves)
            for knots in [binding.right, binding.left] {
                let curve = GarmentSleeveCurve(knots: knots)
                for knot in knots {
                    let frame = try #require(curve.closestFrame(to: knot.center))
                    #expect(simd_distance(frame.center, knot.center) < 0.0001)
                    #expect(abs(simd_dot(frame.depth, frame.tangent)) < 0.0001)
                    #expect(abs(simd_length(frame.radial) - 1) < 0.0001)
                }
            }
            for definition in GarmentCatalog.samples where definition.pattern.meshResource == resource {
                let resized = try resized(source, definition: definition)
                let sleeves = try #require(resized.sleeves)
                let length = try #require(definition.pattern.dimensions).sleeveLength
                #expect(abs(try #require(sleeves.right.last).station - length) < 0.0001)
                #expect(abs(try #require(sleeves.left.last).station - length) < 0.0001)
            }
        }
        let source = try asset("meshy_long_sleeve")
        let binding = try #require(source.sleeves)
        let curve = GarmentSleeveCurve(knots: binding.right)
        let frame = try #require(curve.closestFrame(to: source.vertices[2630]))
        #expect(simd_dot(source.vertices[2630] - frame.center, frame.depth) > 0.03,
                "The source front must not be collapsed onto or behind a shoulder-to-cuff chord")
    }

    @Test func upperSleeveSurfacesClearStandardMaleArms() async throws {
        let worker = BodyPreviewRenderer()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        let fitted = try await worker.prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        for resource in ["meshy_long_sleeve", "meshy_hoodie", "meshy_bomber"] {
            let definition = try #require(GarmentCatalog.samples.first {
                $0.pattern.meshResource == resource && $0.selectionLabel == "M"
            })
            let started = ContinuousClock.now
            let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
            print("UPPER_LATENCY \(resource) \(started.duration(to: .now))")
            let placement = GarmentFitter.placement(for: result.asset, body: fitted.profile)
            #expect(!placement.pins.isEmpty, "A measured cuff narrower than the hand must stop at the wrist")
            print("UPPER_CUFF \(resource) pins=\(placement.pins.count) wrist=\(fitted.profile.rightWrist?.circumference ?? 0) hand=\(fitted.profile.rightHandSections.map(\.circumference).max() ?? 0)")
            let collision = try #require(fitted.collisionMesh)
            let initial = GarmentFitter.positions(for: result.asset, body: fitted.profile)
            let diagnostic = [
                "body": Geometry(vertices: collision.vertices, indices: collision.indices),
                "initial": Geometry(vertices: initial, indices: result.asset.indices),
                "final": Geometry(vertices: result.positions, indices: result.asset.indices),
                "display": Geometry(vertices: result.displayVertices, indices: result.displayIndices)
            ]
            let capture = FileManager.default.temporaryDirectory.appending(path: "SleeveDiagnostic-\(resource).json")
            try JSONEncoder().encode(diagnostic).write(to: capture, options: .atomic)
            print("SLEEVE_DIAGNOSTIC \(capture.path)")
            print("UPPER_SLEEVE \(resource) overlap=\(result.remainingOverlap) strain=\(result.maximumStrain)")
            #expect(result.remainingOverlap < 0.003)
            #expect(maximumEdgeRatio(result) < 3, "Collision clearance must not be obtained by exploding sleeve triangles")
        }
    }

    @Test func legacyTShirtChecksArmsOnTheActualMaleAndFemaleMannequins() async throws {
        let worker = BodyPreviewRenderer()
        let definition = try #require(GarmentCatalog.samples.first {
            $0.pattern.meshResource == "meshy_cotton_tshirt" && $0.selectionLabel == "M"
        })
        for base: MannequinBase in [.male, .female] {
            let request = BodyPreviewRenderer.Request(body: .defaults(for: base), base: base)
            let fitted = try await worker.prepareFitting(request).fitted
            let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                              collision: fitted.collisionMesh, fitProfile: fitted.profile)
            let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
            print("LEGACY_ACTUAL_MANNEQUIN \(base) overlap=\(result.remainingOverlap) displayBody=\(result.displayBodyOverlap)")
            #expect(result.remainingOverlap < 0.002)
            #expect(result.displayBodyOverlap < 0.002)
            #expect(maximumEdgeRatio(result) < 3)
        }
    }

    @Test func hoodieColdAndCachedLatencyKeepsSurfaceQuality() async throws {
        await GarmentDraper.shared.releaseCachedResources()
        let worker = BodyPreviewRenderer()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        let fitted = try await worker.prepareFitting(request).fitted
        let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: fitted.anchor),
                                          collision: fitted.collisionMesh, fitProfile: fitted.profile)
        let definition = try #require(GarmentCatalog.samples.first {
            $0.pattern.meshResource == "meshy_hoodie" && $0.selectionLabel == "M"
        })
        let previewStarted = ContinuousClock.now
        let preview = try await GarmentDraper.shared.preview(definition: definition, body: snapshot)
        let previewDuration = previewStarted.duration(to: .now)
        #expect(previewDuration < .seconds(1))
        #expect(preview.positions.count == preview.asset.vertices.count)
        print("HOODIE_PREVIEW_LATENCY \(previewDuration)")
        let cold = ContinuousClock.now
        let first = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
        let coldDuration = cold.duration(to: .now)
        let warm = ContinuousClock.now
        let second = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
        let warmDuration = warm.duration(to: .now)
        print("HOODIE_LATENCY cold=\(coldDuration) cached=\(warmDuration)")
        #expect(coldDuration < .seconds(15))
        #expect(warmDuration < .milliseconds(100))
        #expect(first.positions == second.positions)
        try checkShapePreservingBodyContact(first, body: snapshot)
        #expect(maximumEdgeRatio(first) < 3)
    }

    @Test func trouserTotalLengthPreservesRiseAndMovesBothHems() throws {
        for resource in ["meshy_dress_pants", "meshy_jeans"] {
            let source = try asset(resource)
            let reference = try #require(source.trousers).reference
            var input = TrouserSizeInput(dimensions: reference)
            let rise = input.rise
            let before = input.totalLength
            input.totalLength -= 12
            #expect(input.rise == rise)
            #expect(abs(input.totalLength - (before - 12)) < 0.00001)
            let roundTrip = try JSONDecoder().decode(TrouserSizeInput.self, from: JSONEncoder().encode(input))
            #expect(roundTrip.totalLength == input.totalLength)
            let shortened = try #require(LowerGarmentFitter.resized(source, to: input.specification))
            #expect(shortened.indices == source.indices)
            #expect(shortened.trousers?.reference.rise == reference.rise)
            for side: Float in [-1, 1] {
                let beforeHem = try #require(source.vertices.filter { $0.x * side > 0 }.map(\.y).min())
                let afterHem = try #require(shortened.vertices.filter { $0.x * side > 0 }.map(\.y).min())
                #expect(abs(afterHem - beforeHem - 0.12) < 0.005)
            }
            input.totalLength = rise + 29
            #expect(!input.isValid)
        }
    }

    @Test func fourSlotsRenderTogetherAndReuseUnchangedInnerSurfaces() async throws {
        await GarmentDraper.shared.releaseCachedResources()
        let state = EditorialSceneState()
        let request = BodyPreviewRenderer.Request(body: UserBody(), base: .male)
        try await state.prepare(request, bodyOnly: false)
        let definitions = try ["meshy_hoodie", "meshy_jeans", "meshy_sneakers", "meshy_bomber"].map { resource in
            try #require(GarmentCatalog.samples.first { $0.pattern.meshResource == resource && $0.selectionLabel == "M" })
        }
        let controller = state.garment
        let started = ContinuousClock.now
        controller.update(outfit: definitions, focused: definitions[0], mannequin: state.mannequin)
        for _ in 0..<9000 where controller.isSettling { try await Task.sleep(for: .milliseconds(20)) }
        let duration = started.duration(to: .now)
        print("FOUR_SLOT_LATENCY \(duration)")
        #expect(duration < .seconds(120))
        #expect(!controller.isSettling)
        #expect(controller.visibleSlots == Set(OutfitSlot.allCases))
        #expect(controller.root.children.count == 4)
        #expect(controller.fittedResults.count == 4)
        var diagnostic: [String: Geometry] = [:]
        if let collision = state.mannequin.garmentCollisionMesh {
            diagnostic["body"] = Geometry(
                vertices: collision.vertices.map { $0 + state.mannequin.topGarmentAnchor - controller.root.position },
                indices: collision.indices)
        }
        for (slot, result) in controller.fittedResults {
            let definition = try #require(definitions.first { $0.kind.slot == slot })
            let anchor = state.mannequin.garmentAnchor(definition.pattern.anchor ?? .shoulders) - controller.root.position
            diagnostic[slot.rawValue] = Geometry(vertices: result.displayVertices.map { $0 + anchor },
                                                 indices: result.displayIndices)
            print("FOUR_SLOT_GEOMETRY \(slot.rawValue) overlap=\(result.remainingOverlap) displayBody=\(result.displayBodyOverlap) edgeRatio=\(maximumEdgeRatio(result))")
            #expect(result.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(maximumEdgeRatio(result) < 3)
            if slot == .outer {
                #expect(result.remainingOverlap < 0.07)
                #expect(result.displayBodyOverlap < 0.003)
                #expect(controller.slotMessages[slot] != nil)
            } else if slot == .top {
                #expect(result.remainingOverlap < 0.006)
            } else if slot == .bottom {
                #expect(result.remainingOverlap < 0.012)
            }
        }
        let capture = FileManager.default.temporaryDirectory.appending(path: "LayeredOutfitDiagnostic.json")
        try JSONEncoder().encode(diagnostic).write(to: capture, options: .atomic)
        print("FOUR_SLOT_DIAGNOSTIC \(capture.path)")
        #expect(abs(state.mannequin.root.position.y - 0.0348) < 0.001)
        #expect(controller.root.position.y == state.mannequin.root.position.y)
        let count = controller.settlementRequestCount
        let children = Array(controller.root.children)
        controller.update(outfit: definitions, focused: definitions[3], mannequin: state.mannequin)
        #expect(controller.settlementRequestCount == count)
        #expect(zip(children, controller.root.children).allSatisfy { $0 === $1 })
        let largerOuter = try #require(GarmentCatalog.samples.first {
            $0.pattern.meshResource == "meshy_bomber" && $0.selectionLabel == "L"
        })
        let largerOutfit = definitions.map { $0.kind.slot == .outer ? largerOuter : $0 }
        controller.update(outfit: largerOutfit, focused: largerOuter, mannequin: state.mannequin)
        for _ in 0..<9000 where controller.isSettling { try await Task.sleep(for: .milliseconds(20)) }
        let largerResult = try #require(controller.fittedResults[.outer])
        print("FOUR_SLOT_LARGER_OUTER overlap=\(largerResult.remainingOverlap) displayBody=\(largerResult.displayBodyOverlap) edgeRatio=\(maximumEdgeRatio(largerResult))")
        #expect(maximumEdgeRatio(largerResult) < 3)
        #expect(largerResult.displayBodyOverlap < 0.003)
        #expect(controller.visibleSlots == Set(OutfitSlot.allCases))
        let withoutShoes = definitions.filter { $0.kind != .shoes }
        controller.update(outfit: withoutShoes, focused: definitions[0], mannequin: state.mannequin)
        for _ in 0..<9000 where controller.isSettling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!controller.isSettling)
        #expect(controller.visibleSlots == Set([.top, .bottom, .outer]))
        let outer = try #require(controller.fittedResults[.outer])
        #expect(outer.summary?.collisionWasSolved == true)
        #expect(controller.fittedResults.values.allSatisfy { maximumEdgeRatio($0) < 3 })
        #expect(state.mannequin.root.position.y == 0)
        controller.update(outfit: [], focused: nil, mannequin: state.mannequin)
        #expect(controller.root.children.isEmpty)
        #expect(!controller.root.isEnabled)
        state.cancelPreparation()
    }

    @Test func cancelledOutfitDoesNotPublishPreviewAsACompletedFitAndCanRetry() async throws {
        await GarmentDraper.shared.releaseCachedResources()
        let state = EditorialSceneState()
        try await state.prepare(.init(body: UserBody(), base: .male), bodyOnly: false)
        let definition = try #require(GarmentCatalog.samples.first {
            $0.pattern.meshResource == "meshy_hoodie" && $0.selectionLabel == "M"
        })
        let controller = state.garment
        controller.update(outfit: [definition], focused: definition, mannequin: state.mannequin)
        #expect(controller.isSettling)
        #expect(controller.requestedSlotCount == 1)
        controller.cancelFitting()
        #expect(controller.wasCancelled && !controller.isSettling)
        #expect(controller.fitSummary == nil && controller.fittedResults.isEmpty)
        #expect(!controller.root.isEnabled)
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.wasCancelled && controller.root.children.isEmpty)
        controller.update(outfit: [definition], focused: definition, mannequin: state.mannequin)
        for _ in 0..<500 where controller.activeFittingPhase != .correcting {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.activeFittingPhase == .correcting && controller.isSettling)
        let cancelledAt = ContinuousClock.now
        controller.cancelFitting()
        #expect(controller.wasCancelled && controller.fittedResults.isEmpty)
        let retry = GarmentCatalog.samples.first { $0.pattern.meshResource == "meshy_sneakers" && $0.selectionLabel == "M" }
        let latest = try #require(retry)
        controller.update(outfit: [latest], focused: latest, mannequin: state.mannequin)
        for _ in 0..<500 where controller.isSettling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!controller.wasCancelled && !controller.isSettling)
        #expect(controller.visibleSlots == [.shoes])
        #expect(controller.fittedResults[.top] == nil)
        #expect(controller.fitSummary?.footLengthEase != nil)
        #expect(cancelledAt.duration(to: .now) < .seconds(5))
        state.cancelPreparation()
    }

    @Test func footwearElevationMovesBothBodyAnchorsAndReturnsToBarefootFloor() {
        let mannequin = WEASHIONMannequin()
        let top = mannequin.topGarmentAnchor
        let waist = mannequin.garmentWaistAnchor
        mannequin.setFootwearElevation(0.035)
        #expect(mannequin.root.position.y == 0.035)
        #expect(mannequin.garmentAnchor(.feet).y == 0.035)
        #expect(abs(mannequin.topGarmentAnchor.y - top.y - 0.035) < 0.000001)
        #expect(abs(mannequin.garmentWaistAnchor.y - waist.y - 0.035) < 0.000001)
        mannequin.setFootwearElevation(0)
        #expect(mannequin.root.position == .zero)
        #expect(mannequin.topGarmentAnchor == top)
    }

    @Test func cuffPinsValidateAtomicallyAndClearWithTheGarment() throws {
        let body: [Float] = [10, 0, 10, 10, 0, 11, 11, 0, 10]
        let indices: [Int32] = [0, 1, 2]
        let reference: [Float] = [0, 1, 0, 0.02, 1, 0, 0, 1, 0.02]
        let context = try #require(body.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer { triangles in
                weashion_cloth_create_body(points.baseAddress, 3, triangles.baseAddress, 1, nil)
            }
        })
        defer { weashion_cloth_destroy(context) }
        func prepare() {
            let initialized = reference.withUnsafeBufferPointer { points in
                indices.withUnsafeBufferPointer { triangles in
                    weashion_cloth_set_garment(context, points.baseAddress, 3, triangles.baseAddress, 1, points.baseAddress)
                }
            }
            #expect(initialized == 1)
        }
        func settledFirstHeight() -> Float {
            var status: Int32 = 1
            for _ in 0..<12 {
                status = weashion_cloth_step(context, 8, nil)
                if status != 1 { break }
            }
            #expect(status == 2)
            var result = Array(repeating: Float.zero, count: reference.count)
            result.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(context, $0.baseAddress) }
            return result[1]
        }
        prepare()
        let invalid: [Int32] = [0, 3]
        #expect(invalid.withUnsafeBufferPointer { weashion_cloth_pin_vertices(context, $0.baseAddress, 2) } == 0)
        #expect(weashion_cloth_pin_vertices(context, nil, 1) == 0)
        #expect(settledFirstHeight() < reference[1] - 0.001,
                "Rejecting an invalid list must not partially pin its valid first index")
        prepare()
        let pin: [Int32] = [0]
        #expect(pin.withUnsafeBufferPointer { weashion_cloth_pin_vertices(context, $0.baseAddress, 1) } == 1)
        #expect(abs(settledFirstHeight() - reference[1]) < 0.000001)
        weashion_cloth_clear_garment(context)
        prepare()
        #expect(settledFirstHeight() < reference[1] - 0.001)
    }

    @Test func lowerDimensionsChangeIndependentlyWithoutChangingTopology() throws {
        for resource in ["meshy_dress_pants", "meshy_jeans"] {
            let source = try asset(resource)
            let reference = try #require(source.trousers).reference
            let target = TrouserSpecification(waistCircumference: reference.waistCircumference + 0.12,
                hipCircumference: reference.hipCircumference + 0.14, rise: reference.rise + 0.04,
                inseam: reference.inseam - 0.12, thighCircumference: reference.thighCircumference + 0.08,
                hemCircumference: reference.hemCircumference - 0.04)
            let resized = try #require(LowerGarmentFitter.resized(source, to: target))
            let valid = resized.isValid
            #expect(valid, "\(resource) resized geometry")
            #expect(resized.trousers?.reference == target)
            #expect(resized.indices == source.indices)
            let originalBottom = try #require(source.vertices.map(\.y).min())
            let expectedBottom = -target.rise + (originalBottom + reference.rise) * target.inseam / reference.inseam
            #expect(abs(try #require(resized.vertices.map(\.y).min()) - expectedBottom) < 0.00001)
            #expect(meanDistance(source.vertices, resized.vertices) > 0.025)
        }
        let source = try asset("meshy_sneakers")
        let binding = try #require(source.footwear)
        let target = FootwearSpecification(length: binding.reference.length + 0.04, width: binding.reference.width + 0.02)
        let resized = try #require(LowerGarmentFitter.resized(source, to: target))
        #expect(resized.isValid)
        for side in [-1, 1] {
            let vertices = resized.vertices.indices.filter { binding.sides[$0] == side }.map { resized.vertices[$0] }
            let length = try #require(vertices.map(\.z).max()) - #require(vertices.map(\.z).min())
            let width = try #require(vertices.map(\.x).max()) - #require(vertices.map(\.x).min())
            #expect(abs(length - target.length) < 0.001)
            #expect(abs(width - target.width) < 0.001)
        }
        #expect(zip(source.vertices, resized.vertices).allSatisfy { $0.y == $1.y })
    }

    @Test func samplesAreExplicitPersistentAndDeletedModelsStayDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "GarmentLibrary-\(UUID().uuidString)")
        let file = directory.appending(path: "library.json")
        let suite = "Weashion.GarmentCategoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
            catch { Issue.record(error) }
        }
        let room = FittingRoom(defaults: defaults, fileURL: file, migratesLegacy: false)
        #expect(room.library.products.count == 1)
        for resource in resources {
            let definition = try #require(room.catalog.first { $0.pattern.meshResource == resource })
            try room.addSample(templateID: definition.pattern.id)
            let product = try #require(room.product)
            #expect(product.kind == definition.kind)
            #expect(product.sizes.count == 3)
            #expect(product.sizes.allSatisfy { $0.isSample && product.definition(for: $0, in: room.catalog) != nil })
            #expect(throws: FittingLibraryError.self) { try room.addSample(templateID: definition.pattern.id) }
        }
        #expect(room.library.products.count == 7)
        let restored = FittingRoom(defaults: defaults, fileURL: file, migratesLegacy: false)
        #expect(restored.library.products == room.library.products)
        let shoes = try #require(restored.library.products.first { $0.kind == .shoes })
        var size = try #require(shoes.sizes.first)
        size.measurements = .footwear(.init(length: 285, width: 110))
        try restored.saveSize(size, productID: shoes.id, select: true)
        #expect(restored.definition?.pattern.footwearDimensions == FootwearSizeInput(length: 285, width: 110).specification)
        try restored.deleteProduct(shoes.id)
        restored.reload()
        #expect(restored.library.products.count == 6)
        #expect(!restored.library.products.contains { $0.id == shoes.id })
    }

    @Test func trouserRiseIsNotSilentlyNormalizedToItsWearer() async throws {
        let worker = BodyPreviewRenderer()
        let fitted = try await worker.prepareFitting(.init(body: UserBody(), base: .male)).fitted
        let source = try asset("meshy_dress_pants")
        let reference = try #require(source.trousers).reference
        let target = TrouserSpecification(waistCircumference: reference.waistCircumference,
            hipCircumference: reference.hipCircumference, rise: reference.rise + 0.08,
            inseam: reference.inseam, thighCircumference: reference.thighCircumference,
            hemCircumference: reference.hemCircumference)
        let changed = try #require(LowerGarmentFitter.resized(source, to: target))
        let before = GarmentFitter.positions(for: source, body: fitted.profile)
        let after = GarmentFitter.positions(for: changed, body: fitted.profile)
        #expect(meanDistance(before, after) > 0.03)
        #expect(abs(try #require(before.map(\.y).min()) - #require(after.map(\.y).min()) - 0.08) < 0.00001)
    }

    @Test func nativeFitsRetainSizeAndBodyDifferencesAndExportComparableSurfaces() async throws {
        try await captureNativeFits(resources: resources)
    }

    @Test func rigidFootwearFollowsActualFeetWithoutChangingItsMeasurements() async throws {
        try await captureNativeFits(resources: ["meshy_sneakers"])
    }

    private func captureNativeFits(resources: [String]) async throws {
        let worker = BodyPreviewRenderer()
        var standard = UserBody()
        standard.measuredFields = [.chest, .waist, .hip]
        standard.footLength = 270
        var slim = standard
        slim.weight = 55
        slim.chest = 85
        slim.waist = 65
        slim.hip = 88
        slim.armSize = 0.8
        slim.legSize = 0.8
        slim.footLength = 250
        var full = standard
        full.weight = 92
        full.chest = 116
        full.waist = 104
        full.hip = 114
        full.armSize = 1.2
        full.legSize = 1.2
        full.footLength = 290
        var muscular = standard
        muscular.weight = 85
        muscular.chest = 112
        muscular.waist = 82
        muscular.shoulderWidth = 50
        muscular.armSize = 1.3
        muscular.legSize = 1.15
        muscular.footLength = 280
        let variants: [(String, UserBody, MannequinBase)] = [
            ("standard", standard, .male), ("slim", slim, .male), ("full", full, .male),
            ("muscular", muscular, .male), ("female", .defaults(for: .female), .female)
        ]
        let directory = FileManager.default.temporaryDirectory.appending(path: "GarmentValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("GARMENT_VALIDATION_CAPTURE \(directory.path)")
        var entries: [CaptureEntry] = []
        var baseline: [String: GarmentDrapeResult] = [:]
        for (name, body, base) in variants {
            let request = BodyPreviewRenderer.Request(body: body, base: base)
            let fitted = try await worker.prepareFitting(request).fitted
            #expect(fitted.profile.rightLegSections.count >= 2)
            #expect(fitted.profile.leftLegSections.count >= 2)
            #expect(fitted.profile.rightFoot != nil && fitted.profile.leftFoot != nil)
            try JSONEncoder().encode(Geometry(vertices: fitted.surface.vertices, indices: fitted.surface.indices))
                .write(to: directory.appending(path: "\(name)-body.json"), options: .atomic)
            for resource in resources {
                let sizes = GarmentCatalog.samples.filter { $0.pattern.meshResource == resource }
                let selections = name == "standard" ? ["S", "M", "L"] : ["M"]
                var previousSize: GarmentDrapeResult?
                for label in selections {
                    let definition = try #require(sizes.first { $0.selectionLabel == label })
                    let anchor: SIMD3<Float>
                    switch definition.pattern.anchor ?? .shoulders {
                    case .shoulders: anchor = fitted.anchor
                    case .waist: anchor = fitted.profile.waist.center + fitted.anchor
                    case .feet: anchor = .zero
                    }
                    let offset = fitted.anchor - anchor
                    let profile = fitted.profile.translated(by: offset)
                    let collision = fitted.collisionMesh.map {
                        GarmentCollisionMesh(vertices: $0.vertices.map { $0 + offset }, indices: $0.indices, armTriangles: $0.armTriangles)
                    }
                    let snapshot = GarmentBodySnapshot(key: .init(body: request, anchor: anchor), collision: collision, fitProfile: profile)
                    let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
                    let summary = try #require(result.summary)
                    #expect(result.positions.count == result.asset.vertices.count)
                    #expect(result.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                    #expect(result.maximumStrain.isFinite && result.remainingOverlap.isFinite)
                    if definition.kind != .shoes {
                        #expect(maximumEdgeRatio(result) < 3,
                                "\(resource) \(name) \(label) must not explode source triangles")
                    }
                    if definition.kind == .pants {
                        #expect(summary.waistEase != nil && summary.hipEase != nil)
                        #expect(summary.wornChest == nil)
                    } else if definition.kind == .shoes {
                        #expect(summary.footLengthEase != nil && summary.footWidthEase != nil)
                        #expect(!summary.collisionWasSolved)
                        #expect(result.maximumStrain == 0)
                        let binding = try #require(result.asset.footwear)
                        for side in [-1, 1] {
                            let foot = try #require(side > 0 ? profile.rightFoot : profile.leftFoot)
                            let across = SIMD3<Float>(foot.forward.z, 0, -foot.forward.x)
                            let points = result.positions.indices.filter { binding.sides[$0] == side }.map { result.positions[$0] }
                            let along = points.map { simd_dot($0, foot.forward) }
                            let lateral = points.map { simd_dot($0, across) }
                            let length = try #require(along.max()) - #require(along.min())
                            let width = try #require(lateral.max()) - #require(lateral.min())
                            #expect(abs(length - binding.reference.length) < 0.001)
                            #expect(abs(width - binding.reference.width) < 0.001)
                        }
                    } else {
                        #expect(summary.collisionWasSolved)
                        #expect(summary.waistEase == nil && summary.footLengthEase == nil)
                        if name == "standard", label == "M" {
                            #expect(result.remainingOverlap < 0.003, "\(resource) standard sleeve clearance")
                        }
                    }
                    if name == "standard" {
                        if let previousSize {
                            #expect(meanDistance(previousSize.positions, result.positions) > 0.002,
                                    "\(resource) adjacent sizes must remain visibly different after fitting")
                            #expect(summary.primaryEase > (previousSize.summary?.primaryEase ?? .infinity) + 0.005)
                        }
                        previousSize = result
                        if label == "M" { baseline[resource] = result }
                    } else if let reference = baseline[resource] {
                        if definition.kind == .shoes {
                            #expect(result.asset.vertices == reference.asset.vertices,
                                    "Rigid footwear must not silently expand to match its wearer")
                            #expect(abs(summary.primaryEase - (reference.summary?.primaryEase ?? 0)) > 0.005)
                        } else {
                            #expect(meanDistance(reference.positions, result.positions) > 0.005,
                                    "\(resource) \(name) must not reuse unchanged wearer geometry")
                        }
                        if definition.kind != .shoes, name != "muscular" {
                            #expect(abs(summary.primaryEase - (reference.summary?.primaryEase ?? 0)) > 0.05)
                        }
                    }
                    let filename = "\(resource)-\(name)-\(label).json"
                    let elevation = result.asset.footwear?.soleThickness ?? 0
                    try JSONEncoder().encode(Geometry(vertices: result.displayVertices.map { $0 + anchor + SIMD3<Float>(0, elevation, 0) },
                                                      indices: result.displayIndices))
                        .write(to: directory.appending(path: filename), options: .atomic)
                    entries.append(.init(resource: resource, body: name, size: label, file: filename,
                                         ease: summary.primaryEase, strain: result.maximumStrain, overlap: result.remainingOverlap,
                                         collisionWasSolved: summary.collisionWasSolved, bodyElevation: elevation,
                                         displayBodyOverlap: result.displayBodyOverlap))
                    try JSONEncoder().encode(entries).write(to: directory.appending(path: "index.json"), options: .atomic)
                    print("GARMENT_FIT \(resource) \(name) \(label) ease=\(summary.primaryEase) strain=\(result.maximumStrain) overlap=\(result.remainingOverlap)")
                }
            }
        }
        try JSONEncoder().encode(entries).write(to: directory.appending(path: "index.json"), options: .atomic)
        print("GARMENT_VALIDATION_CAPTURE \(directory.path)")
    }

    private struct Geometry: Encodable {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }

    private struct CaptureEntry: Encodable {
        let resource: String
        let body: String
        let size: String
        let file: String
        let ease: Float
        let strain: Float
        let overlap: Float
        let collisionWasSolved: Bool
        let bodyElevation: Float
        let displayBodyOverlap: Float
    }
}
