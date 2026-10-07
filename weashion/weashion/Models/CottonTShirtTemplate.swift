import Foundation
import simd

nonisolated enum CottonTShirtTemplate {
    static func makePattern(_ specification: SampleTShirtSpecification) -> GarmentMeshAsset {
        let depthRatio: Float = 0.80
        let perimeter = GarmentFitSection.ellipseCircumference(halfWidth: 1, halfDepth: depthRatio)
        let halfWidth = specification.chestCircumference / perimeter
        let halfDepth = halfWidth * depthRatio
        let shoulder = specification.shoulderWidth / 2
        let shoulderDrop: Float = 0.065
        let armholeHeight = specification.sleeveOpening * 0.64
        let armholeDepth = specification.sleeveOpening * 0.24
        let segments = 64
        let halfSegments = segments / 2
        let bodyRows = 24
        let shoulderRows = 12
        let sleeveRows = 14
        let sleeveSegments = shoulderRows * 2
        let cuffRadius = specification.sleeveOpening / (2 * .pi)
        let cuffAxis = simd_normalize(SIMD3<Float>(0.96, 0.28, 0))
        let rightCuffCenter = SIMD3<Float>(0.195 + shoulder * 0.30, -shoulderDrop - specification.sleeveLength * 0.92, 0)
        let neckHalfWidth: Float = 0.090
        let chestY = -armholeHeight
        let torsoSpan = specification.length - armholeHeight
        let hipY = min(max(-0.5902, -specification.length + torsoSpan * 0.05), chestY - torsoSpan * 0.35)
        let waistY = min(max(-0.4316, hipY + torsoSpan * 0.10), chestY - torsoSpan * 0.10)
        let hipRow = 4
        let waistRow = 13
        var surface = GarmentSurface()
        var weights: [GarmentVertexFitWeight] = []

        func bodyHeight(_ row: Int) -> Float {
            if row <= hipRow {
                return -specification.length + (hipY + specification.length) * Float(row) / Float(hipRow)
            }
            if row <= waistRow {
                return hipY + (waistY - hipY) * Float(row - hipRow) / Float(waistRow - hipRow)
            }
            return waistY + (chestY - waistY) * Float(row - waistRow) / Float(bodyRows - waistRow)
        }

        func bodyPoint(_ height: Float, _ angle: Float, _ regions: SIMD4<Float>) -> SIMD3<Float> {
            let circumference = (specification.hipCircumference ?? specification.chestCircumference) * regions.x
                + (specification.waistCircumference ?? specification.chestCircumference) * regions.y
                + specification.chestCircumference * regions.z
            let width = circumference / perimeter
            return [width * cos(angle), height, width * depthRatio * sin(angle)]
        }

        func necklinePoint(_ across: Float, front: Bool) -> SIMD3<Float> {
            let horizontal = shoulder * across
            if abs(horizontal) >= neckHalfWidth {
                let distance = (abs(horizontal) - neckHalfWidth) / (shoulder - neckHalfWidth)
                return [horizontal, -shoulderDrop * distance, 0]
            }
            let arc = sqrt(max(0, 1 - pow(horizontal / neckHalfWidth, 2)))
            return [horizontal, -(front ? Float(0.045) : 0.010) * arc, (front ? Float(0.087) : -0.061) * arc]
        }

        func shoulderPoint(_ progress: Float, _ angle: Float, front: Bool) -> SIMD3<Float> {
            let across = cos(angle)
            let top = necklinePoint(across, front: front)
            let lower = SIMD3<Float>(halfWidth * across, -armholeHeight, halfDepth * sin(angle))
            var point = lower + (top - lower) * progress
            point.z += (front ? Float(1) : -1) * armholeDepth * sin(.pi * progress) * pow(abs(across), 8)
            point.z += 0.035 * sin(.pi * progress) * sin(angle)
            point.z += 0.00012 * sin(angle * 10) * sin(progress * .pi) * sin(angle)
            return point
        }

        for row in 0...bodyRows {
            let height = bodyHeight(row)
            let regions = GarmentFitProfile.torsoWeights(height: height, hip: hipY, waist: waistY, chest: chestY)
            for segment in 0..<segments {
                surface.vertices.append(bodyPoint(height, Float(segment) * 2 * .pi / Float(segments), regions))
                weights.append(GarmentVertexFitWeight(regions: regions))
            }
        }
        func measuredRing(_ row: Int) -> GarmentFitSection {
            GarmentFitSection(vertices: Array(surface.vertices[(row * segments)..<((row + 1) * segments)]))
        }
        let hipSection = measuredRing(hipRow)
        let waistSection = measuredRing(waistRow)
        let chestSection = measuredRing(bodyRows)
        surface.connectRings(start: 0, rows: bodyRows, columns: segments)
        var shoulderEdges: [[Int]] = []
        for front in [true, false] {
            let start = surface.vertices.count
            for row in 0...shoulderRows {
                let progress = Float(row) / Float(shoulderRows)
                for segment in 0...halfSegments {
                    let angle = Float(segment) * .pi / Float(halfSegments) + (front ? 0 : .pi)
                    surface.vertices.append(shoulderPoint(progress, angle, front: front))
                    let blend = GarmentFitProfile.smoothBlend(progress)
                    weights.append(GarmentVertexFitWeight(regions: [0, 0, 1 - blend, blend]))
                }
            }
            surface.connectGrid(start: start, rows: shoulderRows, columns: halfSegments + 1)
            for segment in 0...halfSegments {
                let bodySegment = (segment + (front ? 0 : halfSegments)) % segments
                surface.smoothPairs.append((bodyRows * segments + bodySegment, start + segment))
            }
            shoulderEdges.append((0...shoulderRows).map { start + $0 * (halfSegments + 1) })
            shoulderEdges.append((0...shoulderRows).map { start + $0 * (halfSegments + 1) + halfSegments })
        }
        let frontTop = (bodyRows + 1) * segments + shoulderRows * (halfSegments + 1)
        let backTop = frontTop + (shoulderRows + 1) * (halfSegments + 1)
        for segment in 0...halfSegments {
            if abs(shoulder * cos(Float(segment) * .pi / Float(halfSegments))) >= neckHalfWidth {
                surface.smoothPairs.append((frontTop + segment, backTop + halfSegments - segment))
            }
        }
        var cuffs: [[Int]] = []
        for side: Float in [1, -1] {
            let start = surface.vertices.count
            let frontEdge = shoulderEdges[side > 0 ? 0 : 1]
            let backEdge = shoulderEdges[side > 0 ? 3 : 2]
            let cuffCenter = rightCuffCenter * SIMD3<Float>(side, 1, 1)
            let cuffUp = cuffAxis * SIMD3<Float>(side, 1, 1)
            for row in 0...sleeveRows {
                let progress = Float(row) / Float(sleeveRows)
                for segment in 0..<sleeveSegments {
                    let angle = Float(segment) * 2 * .pi / Float(sleeveSegments)
                    let edgeIndex = segment <= shoulderRows
                        ? frontEdge[shoulderRows - segment]
                        : backEdge[segment - shoulderRows]
                    let source = surface.vertices[edgeIndex]
                    let destination = cuffCenter + cuffUp * (cuffRadius * cos(angle))
                        + SIMD3<Float>(0, 0, cuffRadius * sin(angle))
                    var point = source + (destination - source) * progress
                    let fold = 0.00016 * sin(progress * .pi) * sin(angle * 6 + progress * 2)
                    point += (cuffUp * cos(angle) + SIMD3<Float>(0, 0, sin(angle))) * fold
                    surface.vertices.append(point)
                    weights.append(GarmentVertexFitWeight(
                        regions: weights[edgeIndex].regions, sleeveProgress: progress, sleeveAngle: angle
                    ))
                    if row == 0 { surface.smoothPairs.append((edgeIndex, start + segment)) }
                }
            }
            surface.connectRings(start: start, rows: sleeveRows, columns: sleeveSegments, reversed: side > 0)
            cuffs.append((0..<sleeveSegments).map { start + sleeveRows * sleeveSegments + $0 })
        }
        let neckSegments = (0...halfSegments).filter {
            abs(shoulder * cos(Float($0) * .pi / Float(halfSegments))) < neckHalfWidth
        }
        let neckStart = max((neckSegments.first ?? 1) - 1, 0)
        let neckEnd = min((neckSegments.last ?? halfSegments - 1) + 1, halfSegments)
        let neck = (neckStart...neckEnd).map { frontTop + $0 }
            + ((neckStart + 1)..<neckEnd).map { backTop + $0 }
        let mapping = surface.weldSeams()
        var weldedWeights = Array(repeating: GarmentVertexFitWeight(regions: .zero), count: surface.vertices.count)
        for index in mapping.indices where weldedWeights[mapping[index]].regions == .zero {
            weldedWeights[mapping[index]] = weights[index]
        }
        var trims = [
            GarmentTrim(vertices: (0..<segments).map { mapping[$0] }, radius: 0.0018, ribbonWidth: 0),
            GarmentTrim(vertices: (0..<segments).map { mapping[segments + $0] }, radius: 0.0006, ribbonWidth: 0),
            GarmentTrim(vertices: neck.map { mapping[$0] }, radius: 0.0014, ribbonWidth: 0.011)
        ]
        trims += cuffs.map { GarmentTrim(vertices: $0.map { mapping[$0] }, radius: 0.0016, ribbonWidth: 0) }
        let fitting = GarmentFitProfile(
            hip: hipSection, waist: waistSection, chest: chestSection,
            shoulderWidth: specification.shoulderWidth, shoulderHeight: -shoulderDrop,
            referenceCircumferences: [0.98, 0.82, 0.98], weights: weldedWeights,
            sleeve: GarmentSleeveFit(center: rightCuffCenter, radialAxis: cuffAxis,
                                    length: specification.sleeveLength, radius: cuffRadius)
        )
        return GarmentMeshAsset(vertices: surface.vertices, indices: surface.indices, trims: trims, fitting: fitting)
    }
}