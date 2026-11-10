import simd

nonisolated enum LowerGarmentFitter {
    static func center(at height: Float, chain: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let first = chain.first, let last = chain.last else { return [0, height, 0] }
        if height <= first.y { return [first.x, height, first.z] }
        for (lower, upper) in zip(chain, chain.dropFirst()) where height <= upper.y {
            let fraction = (height - lower.y) / (upper.y - lower.y)
            return lower + (upper - lower) * fraction
        }
        return [last.x, height, last.z]
    }

    static func frame(at distance: Float, along chain: [SIMD3<Float>]) -> (center: SIMD3<Float>, direction: SIMD3<Float>)? {
        var remaining = distance
        for (lower, upper) in zip(chain, chain.dropFirst()) {
            let delta = upper - lower
            let span = simd_length(delta)
            guard span > 0.00001 else { continue }
            if remaining <= span { return (lower + delta * (remaining / span), delta / span) }
            remaining -= span
        }
        guard chain.count >= 2 else { return nil }
        let last = chain[chain.count - 1]
        let delta = last - chain[chain.count - 2]
        guard simd_length_squared(delta) > 1e-10 else { return nil }
        let direction = simd_normalize(delta)
        return (last + direction * remaining, direction)
    }

    static func resized(_ asset: GarmentMeshAsset, to target: TrouserSpecification) -> GarmentMeshAsset? {
        guard target.isValid, let binding = asset.trousers else { return nil }
        let source = binding.reference
        let waist = target.waistCircumference / source.waistCircumference
        let hip = target.hipCircumference / source.hipCircumference
        func height(_ value: Float) -> Float {
            value >= -source.rise ? value * target.rise / source.rise
                : -target.rise + (value + source.rise) * target.inseam / source.inseam
        }
        let positions = asset.vertices.indices.map { index in
            let point = asset.vertices[index]
            let side: Float = point.x < 0 ? -1 : 1
            let hipBlend = GarmentFitProfile.smoothBlend(-point.y / (source.rise * 0.55))
            let trunkScale = waist + (hip - waist) * hipBlend
            let progress = GarmentFitProfile.smoothBlend((-point.y - source.rise) / source.inseam)
            let thigh = target.effectiveThighCircumference / source.effectiveThighCircumference
            let hem = target.effectiveHemCircumference / source.effectiveHemCircumference
            let radius = thigh + (hem - thigh) * progress
            let original = center(at: point.y, chain: binding.rightLegCenters) * SIMD3<Float>(side, 1, 1)
            let trunk = SIMD3<Float>(point.x * trunkScale, height(point.y), point.z * trunkScale)
            let leg = SIMD3<Float>(original.x * hip + (point.x - original.x) * radius,
                                   height(point.y), original.z * hip + (point.z - original.z) * radius)
            return trunk + (leg - trunk) * binding.legWeights[index]
        }
        let chain = binding.rightLegCenters.map { SIMD3<Float>($0.x * hip, height($0.y), $0.z * hip) }
        return GarmentMeshAsset(vertices: positions, indices: asset.indices, trims: asset.trims,
                                trousers: .init(reference: target, rightLegCenters: chain, legWeights: binding.legWeights))
    }

    static func resized(_ asset: GarmentMeshAsset, to target: FootwearSpecification) -> GarmentMeshAsset? {
        guard target.isValid, let binding = asset.footwear else { return nil }
        let scale = SIMD3<Float>(target.width / binding.reference.width, 1, target.length / binding.reference.length)
        let positions = asset.vertices.indices.map { index in
            let origin = binding.sides[index] > 0 ? binding.rightCenter : binding.leftCenter
            return origin + (asset.vertices[index] - origin) * scale
        }
        return GarmentMeshAsset(vertices: positions, indices: asset.indices, trims: asset.trims,
                                footwear: .init(reference: target, rightCenter: binding.rightCenter,
                                                leftCenter: binding.leftCenter, sides: binding.sides,
                                                soleThickness: binding.soleThickness))
    }

    static func trousers(_ asset: GarmentMeshAsset, binding: TrouserBinding, body: GarmentBodyFitProfile) -> [SIMD3<Float>] {
        let source = binding.reference
        let rightChain = body.rightLegSections.map(\.center)
        let leftChain = body.leftLegSections.map(\.center)
        return asset.vertices.indices.map { index in
            let point = asset.vertices[index]
            let side: Float = point.x < 0 ? -1 : 1
            let y = body.waist.center.y + point.y
            let hipBlend = GarmentFitProfile.smoothBlend(-point.y / source.rise)
            let depth = body.waist.center.z + (body.hip.center.z - body.waist.center.z) * hipBlend
            let trunk = SIMD3<Float>(point.x, y, point.z + depth)
            let original = center(at: point.y, chain: binding.rightLegCenters) * SIMD3<Float>(side, 1, 1)
            let destination = center(at: y, chain: side > 0 ? rightChain : leftChain)
            let leg = SIMD3<Float>(destination.x + point.x - original.x, y, destination.z + point.z - original.z)
            return trunk + (leg - trunk) * binding.legWeights[index]
        }
    }

    static func footwear(_ asset: GarmentMeshAsset, binding: FootwearBinding, body: GarmentBodyFitProfile) -> [SIMD3<Float>] {
        asset.vertices.indices.map { index in
            let right = binding.sides[index] > 0
            let origin = right ? binding.rightCenter : binding.leftCenter
            guard let foot = right ? body.rightFoot : body.leftFoot else { return asset.vertices[index] }
            let destination = SIMD3<Float>(foot.center.x, foot.floor - binding.soleThickness + origin.y, foot.center.z)
            let rotation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: foot.forward)
            return rotation.act(asset.vertices[index] - origin) + destination
        }
    }
}
