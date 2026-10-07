//
//  weashionTests.swift
//  weashionTests
//
//  Created by 임재현 on 9/30/26.
//

import Foundation
import Testing
import simd
@testable import weashion

struct weashionTests {

    @Test func skeletonPreservesBindPoseAndJointHierarchy() {
        var skeleton = BodySkeleton(positions: BodySkeleton.referencePositions)
        for joint in BodySkeleton.Joint.allCases {
            let point = BodySkeleton.referencePositions[joint.rawValue] + SIMD3<Float>(0.013, -0.017, 0.021)
            let transformed = skeleton.deform(point, influences: [.init(joint: joint, weight: 1)])
            #expect(simd_distance(point, transformed) < 0.00001)
            #expect(joint.parent.map { $0.rawValue < joint.rawValue } ?? true)
        }
        let shoulder = skeleton.position(of: .rightShoulder)
        let elbow = skeleton.position(of: .rightElbow)
        let wrist = skeleton.position(of: .rightWrist)
        let otherWrist = skeleton.position(of: .leftWrist)
        skeleton.rotate(.rightShoulder, by: simd_quatf(angle: 0.35, axis: [0, 0, 1]))
        #expect(simd_distance(skeleton.position(of: .rightShoulder), shoulder) < 0.00001)
        #expect(abs(simd_distance(skeleton.position(of: .rightElbow), shoulder) - simd_distance(elbow, shoulder)) < 0.00001)
        #expect(abs(simd_distance(skeleton.position(of: .rightWrist), skeleton.position(of: .rightElbow)) - simd_distance(wrist, elbow)) < 0.00001)
        #expect(simd_distance(skeleton.position(of: .rightWrist), wrist) > 0.05)
        #expect(simd_distance(skeleton.position(of: .leftWrist), otherWrist) < 0.00001)
    }

    @Test func quaternionSkinningPreservesTwistVolume() {
        var skeleton = BodySkeleton(positions: BodySkeleton.referencePositions)
        let wrist = skeleton.position(of: .rightWrist)
        let axis = simd_normalize(skeleton.position(of: .rightPalm) - wrist)
        let radial = simd_normalize(simd_cross(axis, SIMD3<Float>(0, 0, 1))) * 0.02
        skeleton.rotate(.rightWrist, by: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        let influences: [BodySkeleton.Influence] = [.init(joint: .rightElbow, weight: 0.5), .init(joint: .rightWrist, weight: 0.5)]
        let center = skeleton.deform(wrist, influences: influences)
        let surface = skeleton.deform(wrist + radial, influences: influences)
        #expect(abs(simd_distance(center, surface) - 0.02) < 0.00001)
    }

    @Test func garmentsClearFittedBody() async throws {
        let template = ParametricBody.makeTemplate()
        #expect(GarmentCatalog.samples.count == 2)
        for feminine in [false, true] {
            let fitted = try #require(template.fitted(to: .init(
                height: 1.75, weight: 70, shoulderWidth: 0.45, chest: 0.98, waist: 0.82, hip: 0.98,
                inseam: 0.82, armSize: 1, legSize: 1, feminine: feminine)))
            let snapshot = GarmentBodySnapshot(
                key: GarmentBodyKey(id: UUID(), revision: 1, anchor: fitted.anchor),
                bands: fitted.collisionBands, fitProfile: fitted.profile)
            for definition in GarmentCatalog.samples {
                let result = try await GarmentDraper.shared.settle(definition: definition, body: snapshot)
                print("Garment \(definition.selectionLabel) feminine=\(feminine) overlap=\(result.remainingOverlap) strain=\(result.maximumStrain)")
                #expect(result.remainingOverlap < 0.002)
                #expect(result.positions.count == result.asset.vertices.count)
            }
        }
    }

    @Test func bodySurfaceHasConsistentClosedTopology() {
        let template = ParametricBody.makeTemplate()
        var counts: [ParametricBody.Edge: Int] = [:]
        print("Body mesh vertices=\(template.vertices.count) faces=\(template.faces.count)")
        var winding: [ParametricBody.Edge: Int] = [:]
        for face in template.faces {
            for corner in face.indices.indices {
                let first = face.indices[corner]
                let second = face.indices[(corner + 1) % face.indices.count]
                let edge = ParametricBody.Edge(first, second)
                counts[edge, default: 0] += 1
                winding[edge, default: 0] += first < second ? 1 : -1
            }
        }
        #expect(!counts.isEmpty)
        #expect(counts.values.allSatisfy { $0 == 2 })
        #expect(winding.values.allSatisfy { $0 == 0 })
    }

    @Test func bodyMeasurementsSurviveDeformation() throws {
        let template = ParametricBody.makeTemplate()
        for (height, inseam, chest, waist, hip, limbScale, shoulder, feminine): (Float, Float, Float, Float, Float, Float, Float, Bool) in [
            (1.75, 0.82, 0.98, 0.82, 0.98, 1, 0.45, false),
            (1.50, 0.65, 0.75, 0.60, 0.75, 0.7, 0.45, false),
            (2.00, 0.95, 1.20, 1.05, 1.20, 1.3, 0.45, false),
            (1.75, 0.82, 0.98, 0.82, 0.98, 1, 0.45, true),
            (1.50, 0.65, 0.75, 0.60, 0.75, 0.7, 0.45, true),
            (2.00, 0.95, 1.20, 1.05, 1.20, 1.3, 0.45, true),
            (1.50, 0.82, 0.98, 0.82, 0.98, 1, 0.35, false),
            (1.50, 0.82, 0.98, 0.82, 0.98, 1, 0.35, true),
            (1.75, 0.82, 1.20, 1.05, 1.20, 1.3, 0.35, false),
            (1.75, 0.82, 1.20, 1.05, 1.20, 1.3, 0.35, true),
            (2.00, 0.95, 0.75, 0.60, 0.75, 0.7, 0.60, false),
            (2.00, 0.95, 0.75, 0.60, 0.75, 0.7, 0.60, true)
        ] {
            let measurements = ParametricBody.Measurements(
                height: height, weight: 70, shoulderWidth: shoulder, chest: chest, waist: waist, hip: hip,
                inseam: inseam, armSize: limbScale, legSize: limbScale, feminine: feminine)
            let fitted = try #require(template.fitted(to: measurements))
            #expect(abs(fitted.profile.chest.circumference - chest) < 0.005)
            #expect(abs(fitted.profile.waist.circumference - waist) < 0.005)
            #expect(abs(fitted.profile.hip.circumference - hip) < 0.005)
            #expect(fitted.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.y >= -0.001 })
            #expect(fitted.indices.allSatisfy { Int($0) < fitted.positions.count })
            #expect(abs(fitted.headHeight + 0.218 - height) < 0.0001)
            let skeleton = fitted.skeleton
            for (start, end): (BodySkeleton.Joint, BodySkeleton.Joint) in [
                (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
                (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist)
            ] {
                let length = simd_distance(skeleton.position(of: start), skeleton.position(of: end))
                let referenceLength = simd_distance(BodySkeleton.referencePositions[start.rawValue], BodySkeleton.referencePositions[end.rawValue])
                #expect(abs(length - referenceLength * pow(height / 1.75, 0.9)) < 0.00001)
            }
            for (joint, origin, scale): (BodySkeleton.Joint, SIMD3<Float>, Float) in [
                (.rightWrist, BodySkeleton.referencePositions[BodySkeleton.Joint.rightPalm.rawValue], fitted.handScale),
                (.leftWrist, BodySkeleton.referencePositions[BodySkeleton.Joint.leftPalm.rawValue], fitted.handScale),
                (.rightAnkle, [0.085, 0, 0], fitted.footScale), (.leftAnkle, [-0.085, 0, 0], fitted.footScale)
            ] {
                let local = SIMD3<Float>(0.01, -0.02, 0.01)
                let attachment = skeleton.attachmentTransform(at: origin, joint: joint, radialScale: scale) * SIMD4<Float>(local, 1)
                let skin = skeleton.deform(origin + local, influences: [.init(joint: joint, weight: 1)], radialScale: scale)
                #expect(simd_distance(SIMD3<Float>(attachment.x, attachment.y, attachment.z), skin) < 0.00001)
            }
        }
    }

}
