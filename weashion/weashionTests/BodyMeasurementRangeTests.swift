import Foundation
import Testing
import simd
@testable import weashion

@MainActor
struct BodyMeasurementRangeTests {
    @Test func femaleMinimaExpandWithoutChangingMaleLimitsOrMaxima() {
        let limits: [(BodyMeasurement, Double, Double, Double)] = [
            (.height, 140, 150, 200),
            (.weight, 35, 45, 100),
            (.shoulderWidth, 25, 35, 60),
            (.chest, 30, 75, 120),
            (.waist, 30, 60, 105),
            (.hip, 30, 75, 120),
            (.legLength, 45, 65, 95),
            (.armSize, 0.5, 0.7, 1.3),
            (.legSize, 0.5, 0.7, 1.3),
        ]
        #expect(limits.count == BodyMeasurement.allCases.count)
        for (measurement, female, male, maximum) in limits {
            #expect(measurement.range(for: .female) == female...maximum)
            #expect(measurement.range(for: .male) == male...maximum)
            for base in MannequinBase.allCases {
                let range = measurement.range(for: base)
                #expect(range.contains(range.lowerBound))
                #expect(range.contains(maximum))
                #expect(!range.contains(range.lowerBound - measurement.step))
                #expect(!range.contains(maximum + measurement.step))
                #expect(!range.contains(.nan))
                #expect(!range.contains(.infinity))
            }
        }
    }

    @Test func profileValidationAcceptsFemaleMinimaAndRejectsOutOfRangeValues() {
        var body = UserBody.defaults(for: .female)
        for measurement in BodyMeasurement.allCases {
            body.setMeasurement(measurement.range(for: .female).lowerBound, for: measurement)
        }
        #expect(BodyProfile(name: "하한 체형", body: body, base: .female).validationMessage == nil)
        #expect(BodyProfile(name: "하한 체형", body: body, base: .male).validationMessage != nil)
        for measurement in BodyMeasurement.allCases {
            let range = measurement.range(for: .female)
            #expect(body.measurementValue(measurement, base: .female) == range.lowerBound)
            for invalid in [range.lowerBound - measurement.step, range.upperBound + measurement.step] {
                var invalidBody = body
                invalidBody.setMeasurement(invalid, for: measurement)
                #expect(BodyProfile(name: "범위 밖", body: invalidBody, base: .female).validationMessage != nil)
            }
        }
    }

    @Test func setupValidatesBasicsAgainstTheSelectedBase() throws {
        var draft = BodySetupDraft()
        draft.height = 140
        draft.weight = 35
        #expect(!draft.hasValidBasics)
        draft.selectBase(.female)
        #expect(draft.hasValidBasics)
        #expect(draft.previewBody.height == 140)
        #expect(draft.previewBody.weight == 35)
        #expect(try draft.makeProfile().validationMessage == nil)
        draft.selectBase(.male)
        #expect(!draft.hasValidBasics)
        #expect(throws: FittingLibraryError.self) { try draft.makeProfile() }
        draft.selectBase(.female)
        for (height, weight): (Double, Double) in [(139.9, 35), (140, 34.9), (200.1, 35), (140, 100.1)] {
            draft.height = height
            draft.weight = weight
            #expect(!draft.hasValidBasics)
            #expect(throws: FittingLibraryError.self) { try draft.makeProfile() }
        }
    }

    @Test func femaleLowerLimitsProduceMatchingPreviewAndFittingSurfaces() async throws {
        let original = UserBody.defaults(for: .female)
        var variants = BodyMeasurement.allCases.map { measurement in
            var body = original
            body.setMeasurement(measurement.range(for: .female).lowerBound, for: measurement)
            return body
        }
        var minimumBody = original
        for measurement in BodyMeasurement.allCases {
            minimumBody.setMeasurement(measurement.range(for: .female).lowerBound, for: measurement)
        }
        variants.append(minimumBody)
        var smallBody = original
        smallBody.setMeasurement(140, for: .height)
        smallBody.setMeasurement(35, for: .weight)
        variants.append(smallBody)
        let renderer = BodyPreviewRenderer()
        for body in variants {
            #expect(BodyProfile(name: "작은 체형", body: body, base: .female).validationMessage == nil)
            let request = BodyPreviewRenderer.Request(body: body, base: .female)
            #expect(request.bodyMeasurements.weight == Float(body.weight))
            #expect(request.bodyMeasurements.chest == Float(body.measurementValue(.chest, base: .female) / 100))
            #expect(request.bodyMeasurements.waist == Float(body.measurementValue(.waist, base: .female) / 100))
            #expect(request.bodyMeasurements.hip == Float(body.measurementValue(.hip, base: .female) / 100))
            let preview = try #require(try await renderer.render(request))
            let result = try await renderer.prepareFitting(request)
            let fitted = result.fitted
            #expect(!preview.surface.vertices.isEmpty)
            #expect(preview.surface.vertices.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            })
            #expect(preview.surface.indices == fitted.surface.indices)
            #expect(preview.surface.vertices.count == fitted.surface.vertices.count)
            #expect(zip(preview.surface.vertices, fitted.surface.vertices).allSatisfy {
                simd_distance($0, $1) < 0.000001
            })
            let collision = try #require(fitted.collisionMesh)
            #expect(collision.vertices.count == fitted.surface.vertices.count)
            #expect(zip(collision.vertices, fitted.surface.vertices).allSatisfy {
                simd_distance($0 + fitted.anchor, $1) < 0.000001
            })
            #expect(fitted.anatomy?.isValid(vertexCount: fitted.surface.vertices.count) == true)
        }
    }
}
