import Testing
import simd
@testable import weashion

@MainActor
struct GarmentBodyProfileTests {
    @Test func fittedLegAndFootProfilesUseActualSurfacesAndTranslateTogether() async throws {
        let worker = BodyPreviewRenderer()
        for base in [MannequinBase.male, .female] {
            var body = UserBody.defaults(for: base)
            body.footLength = base == .male ? 270 : 240
            let fitted = try await worker.prepareFitting(.init(body: body, base: base)).fitted
            let profile = fitted.profile
            let wrist = try #require(profile.rightWrist)
            #expect(wrist.isValid)
            #expect(profile.rightHandSections.count >= 4)
            #expect(profile.rightHandSections.allSatisfy { $0.center.x > 0 && $0.isValid })
            #expect(zip(profile.rightHandSections, profile.rightHandSections.dropFirst()).allSatisfy {
                $0.center.y > $1.center.y
            })
            #expect(profile.rightLegSections.count >= 12)
            #expect(profile.leftLegSections.count >= 12)
            #expect(profile.rightLegSections.allSatisfy { $0.center.x > 0 && $0.isValid })
            #expect(profile.leftLegSections.allSatisfy { $0.center.x < 0 && $0.isValid })
            for sections in [profile.rightLegSections, profile.leftLegSections] {
                #expect(zip(sections, sections.dropFirst()).allSatisfy { $0.center.y < $1.center.y })
            }
            let right = try #require(profile.rightFoot)
            let left = try #require(profile.leftFoot)
            let expected = Float(try #require(body.footLength)) / 1000
            let feet: [(GarmentFootBounds, String, BodyAnatomy.LandmarkID, BodyAnatomy.LandmarkID)] = [
                (right, "rightFoot", .rightHeel, .rightToe),
                (left, "leftFoot", .leftHeel, .leftToe)
            ]
            for (foot, part, heelID, toeID) in feet {
                let anatomy = try #require(fitted.anatomy)
                let binding = try #require(anatomy.parts[part])
                let points = binding.indices.map { fitted.surface.vertices[Int($0)] }
                let worldLength = try #require(points.map(\.z).max()) - #require(points.map(\.z).min())
                #expect(abs(worldLength - expected) < 0.005, "Existing body foot-length calibration must not change")
                let heel = try #require(fitted.landmarks[heelID])
                let toe = try #require(fitted.landmarks[toeID])
                let forward = simd_normalize(SIMD3<Float>(toe.x - heel.x, 0, toe.z - heel.z))
                #expect(simd_distance(foot.forward, forward) < 0.000001)
                #expect(foot.length > 0.15 && foot.width > 0.05)
            }
            #expect(right.center.x > 0 && left.center.x < 0)
            #expect(right.width > 0.05 && left.width > 0.05)
            #expect(abs(right.floor + fitted.anchor.y) < 0.005)
            let offset = SIMD3<Float>(0.031, -0.23, 0.04)
            let moved = profile.translated(by: offset)
            #expect(simd_distance(try #require(moved.rightWrist).center, wrist.center + offset) < 0.000001)
            #expect(simd_distance(try #require(moved.rightFoot).center, right.center + offset) < 0.000001)
            #expect(try #require(moved.rightFoot).length == right.length)
            #expect(try #require(moved.rightFoot).forward == right.forward)
            #expect(abs(try #require(moved.leftFoot).floor - left.floor - offset.y) < 0.000001)
            #expect(zip(moved.rightLegSections, profile.rightLegSections).allSatisfy {
                simd_distance($0.center, $1.center + offset) < 0.000001
            })
            #expect(zip(moved.rightHandSections, profile.rightHandSections).allSatisfy {
                simd_distance($0.center, $1.center + offset) < 0.000001
            })
            #expect(zip(moved.leftLegSections, profile.leftLegSections).allSatisfy {
                simd_distance($0.center, $1.center + offset) < 0.000001
            })
        }
    }

    @Test func independentLeftAndRightBodyEditsKeepSeparateLowerBindings() async throws {
        let worker = BodyPreviewRenderer()
        var body = UserBody()
        body.setPartScale(1.15, for: .leftThigh, mirrored: false)
        body.setPartScale(0.85, for: .rightThigh, mirrored: false)
        body.setPartScale(1.15, for: .leftFoot, mirrored: false)
        body.setPartScale(0.85, for: .rightFoot, mirrored: false)
        let profile = try await worker.prepareFitting(.init(body: body, base: .male)).fitted.profile
        let right = try #require(profile.rightFoot)
        let left = try #require(profile.leftFoot)
        #expect(left.width > right.width + 0.005)
        let rightThigh = try #require(profile.rightLegSections.last).circumference
        let leftThigh = try #require(profile.leftLegSections.last).circumference
        #expect(leftThigh > rightThigh + 0.01)
    }
}
