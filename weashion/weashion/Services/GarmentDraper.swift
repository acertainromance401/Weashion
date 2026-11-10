import Foundation
import ClothPhysics
import simd

nonisolated struct GarmentBodyKey: Hashable, Sendable {
    let body: BodyPreviewRenderer.Request
    let anchor: SIMD3<Float>
}

nonisolated struct GarmentBodySnapshot: Sendable {
    let key: GarmentBodyKey
    let collision: GarmentCollisionMesh?
    let fitProfile: GarmentBodyFitProfile?
    var layers: [GarmentCollisionLayer] = []
}

nonisolated struct GarmentLayerKey: Hashable, Sendable {
    let pattern: GarmentPatternDescriptor
    let fabric: GarmentFabricSettings
}

nonisolated struct GarmentCollisionLayer: Sendable {
    let key: GarmentLayerKey
    let surface: GarmentCollisionMesh
}

nonisolated struct GarmentDrapeResult: Sendable {
    let asset: GarmentMeshAsset
    let positions: [SIMD3<Float>]
    let displayVertices: [SIMD3<Float>]
    let displayIndices: [UInt32]
    let maximumStrain: Float
    let remainingOverlap: Float
    let summary: GarmentFitSummary?
    var displayBodyOverlap: Float = 0

    var memoryCost: Int {
        asset.memoryCost + (positions.count + displayVertices.count) * MemoryLayout<SIMD3<Float>>.stride
            + displayIndices.count * 4
    }
}

nonisolated enum GarmentDrapeError: Error, Equatable {
    case invalidAsset
    case initializationFailed
    case simulationFailed
}

nonisolated struct GarmentDrapePreview: Sendable {
    let asset: GarmentMeshAsset
    let positions: [SIMD3<Float>]
    let surface: GarmentSurface
}

actor GarmentDraper {
    static let shared = GarmentDraper()
    private var patterns = GarmentMemoryCache<GarmentPatternDescriptor, PreparedGarment>(limit: 16 * 1024 * 1024)
    private var results = GarmentMemoryCache<SimulationKey, GarmentDrapeResult>(limit: 16 * 1024 * 1024)
    private var sources: [String: GarmentMeshAsset] = [:]
    private var bodyKey: CollisionKey?
    private var context: OpaquePointer?

    private init() {}

    func releaseCachedResources() {
        patterns = .init(limit: patterns.limit)
        results = .init(limit: results.limit)
        sources.removeAll()
        if let context { weashion_cloth_destroy(context) }
        context = nil
        bodyKey = nil
    }

    func preview(definition: GarmentDefinition, body: GarmentBodySnapshot) throws -> GarmentDrapePreview {
        try Task.checkCancellation()
        guard definition.isValid, let profile = body.fitProfile else { throw GarmentDrapeError.initializationFailed }
        let prepared = try prepare(definition.pattern)
        let positions = GarmentFitter.placement(for: prepared.asset, body: profile,
            preservingShape: definition.pattern.fittingMode == .shapePreserving).positions
        return .init(asset: prepared.asset, positions: positions,
                     surface: GarmentSurface(vertices: positions, indices: prepared.asset.indices).smoothed())
    }

    func settle(definition: GarmentDefinition, body: GarmentBodySnapshot) throws -> GarmentDrapeResult {
        try Task.checkCancellation()
        guard definition.isValid else { throw GarmentDrapeError.invalidAsset }
        let fabric = definition.material.fabricSettings
        let key = SimulationKey(pattern: definition.pattern, body: body.key, fabric: fabric,
                                layers: body.layers.map(\.key), solverVersion: 33)
        if let cached = results.value(for: key) { return cached }
        let started = ContinuousClock.now
        let prepared = try prepare(definition.pattern)
        let preparedAt = ContinuousClock.now
        if prepared.asset.sleeves != nil {
            guard let profile = body.fitProfile,
                  profile.rightArmSections.count >= 2 || profile.rightArm.count >= 2,
                  profile.rightWrist?.isValid == true, profile.rightHandSections.count >= 2 else {
                throw GarmentDrapeError.initializationFailed
            }
        }
        if prepared.asset.trousers != nil {
            guard let profile = body.fitProfile, profile.rightLegSections.count >= 2,
                  profile.leftLegSections.count >= 2,
                  profile.inseamHeight != nil else { throw GarmentDrapeError.initializationFailed }
        }
        if prepared.asset.footwear != nil {
            guard let profile = body.fitProfile, profile.rightFoot != nil, profile.leftFoot != nil else {
                throw GarmentDrapeError.initializationFailed
            }
            let positions = GarmentFitter.positions(for: prepared.asset, body: profile)
            let simulation = try prepareBody(body)
            let (display, bodyOverlap) = try makeDisplay(asset: prepared.asset, positions: positions, simulation: simulation)
            let summary = GarmentFitSummary(asset: prepared.asset, positions: positions, body: profile,
                                            maximumStrain: 0, remainingOverlap: bodyOverlap)
            let result = GarmentDrapeResult(asset: prepared.asset, positions: positions,
                                           displayVertices: display.vertices, displayIndices: display.indices,
                                           maximumStrain: 0, remainingOverlap: bodyOverlap, summary: summary,
                                           displayBodyOverlap: bodyOverlap)
            try Task.checkCancellation()
            results.insert(result, for: key, cost: result.memoryCost)
            return result
        }
        let regionStretch = prepared.asset.fitting.flatMap { garment in
            body.fitProfile.map { body in
                zip([garment.hip, garment.waist, garment.chest], [body.hip, body.waist, body.chest])
                    .map { max($1.circumference / $0.circumference - 1, 0) }
            }
        } ?? [0, 0, 0]
        var sleeveStretch: Float = 0
        if let sizing = prepared.asset.sizing, let profile = body.fitProfile {
            let cuffHeight = profile.shoulderHeight - sizing.reference.sleeveLength * 0.92
            if let arm = profile.rightArmSections.min(by: {
                abs($0.center.y - cuffHeight) < abs($1.center.y - cuffHeight)
            }) {
                sleeveStretch = max(arm.circumference / sizing.reference.effectiveSleeveOpening - 1, 0)
            }
        }
        try Task.checkCancellation()
        let preservingShape = definition.pattern.fittingMode == .shapePreserving
        var restPositions = prepared.positions
        let placement = GarmentFitter.placement(for: prepared.asset, body: body.fitProfile,
                                               preservingShape: preservingShape)
        var fittedVertices = placement.positions
        if !preservingShape, let fitting = prepared.asset.fitting,
           let offsets = Self.lengthwiseShortening(asset: prepared.asset, fitting: fitting, stretch: regionStretch,
                                                   sleeveStretch: sleeveStretch) {
            for index in offsets.indices {
                for axis in 0..<3 { restPositions[index * 3 + axis] += offsets[index][axis] }
                fittedVertices[index].y += offsets[index].y
            }
        }
        let fitted = pack(fittedVertices)
        let armpit = body.fitProfile.map { profile in
            min(profile.chest.center.y + (profile.shoulderHeight - profile.chest.center.y) * 0.4,
                prepared.asset.fitting?.chest.center.y ?? profile.chest.center.y)
        }
        let torsoOnly: [UInt8] = fittedVertices.indices.map { index in
            guard let armpit, let weights = prepared.asset.fitting?.weights else { return 0 }
            if weights[index].sleeveProgress >= 0.5 {
                return UInt8(WEASHION_CLOTH_LAYER_ARMS_ONLY)
            }
            guard fittedVertices[index].y < armpit else { return 0 }
            return UInt8(WEASHION_CLOTH_EXCLUDE_LAYER_ARMS)
        }
        // A rigid mannequin forces stretch only where it is larger than the garment; elsewhere the fabric limit applies.
        let extensionLimits: [Float] = fittedVertices.indices.map { index in
            if let binding = prepared.asset.trousers, let body = body.fitProfile {
                let reference = binding.reference
                let point = prepared.asset.vertices[index]
                let hipBlend = GarmentFitProfile.smoothBlend(-point.y / (reference.rise * 0.55))
                let waist = max(body.waist.circumference / reference.waistCircumference - 1, 0)
                let hip = max(body.hip.circumference / reference.hipCircumference - 1, 0)
                let trunk = waist + (hip - waist) * hipBlend
                let progress = GarmentFitProfile.smoothBlend((-point.y - reference.rise) / reference.inseam)
                let legCircumference = reference.effectiveThighCircumference
                    + (reference.effectiveHemCircumference - reference.effectiveThighCircumference) * progress
                let sections = point.x > 0 ? body.rightLegSections : body.leftLegSections
                let section = sections.min {
                    abs($0.center.y - fittedVertices[index].y) < abs($1.center.y - fittedVertices[index].y)
                }
                let leg = max((section?.circumference ?? 0) / legCircumference - 1, 0)
                let required = trunk + (leg - trunk) * binding.legWeights[index]
                return min(max(fabric.estimatedMaximumExtension, required + 0.03), 0.5)
            }
            guard let binding = prepared.asset.fitting?.weights[index] else { return fabric.estimatedMaximumExtension }
            let torso = binding.regions.x * regionStretch[0] + binding.regions.y * regionStretch[1]
                + binding.regions.z * regionStretch[2]
            let required = torso + (sleeveStretch - torso) * binding.sleeveProgress
            return min(max(fabric.estimatedMaximumExtension, required + 0.03), 0.5)
        }
        try Task.checkCancellation()
        let simulation = try prepareBody(body)
        let placedAt = ContinuousClock.now
        try Task.checkCancellation()
        let initialized = restPositions.withUnsafeBufferPointer { positions in
            prepared.triangles.withUnsafeBufferPointer { faces in
                fitted.withUnsafeBufferPointer { initialPositions in
                    weashion_cloth_set_garment(
                        simulation, positions.baseAddress, Int32(prepared.asset.vertices.count),
                        faces.baseAddress, Int32(prepared.triangles.count / 3), initialPositions.baseAddress
                    )
                }
            }
        }
        guard initialized != 0 else { throw GarmentDrapeError.initializationFailed }
        defer { weashion_cloth_clear_garment(simulation) }
        let configured = torsoOnly.withUnsafeBufferPointer { torsoOnly in
            extensionLimits.withUnsafeBufferPointer { limits in
                weashion_cloth_configure(simulation, torsoOnly.baseAddress, limits.baseAddress,
                                         Int32(prepared.asset.vertices.count),
                                         fabric.estimatedBendingCompliance, fabric.estimatedSurfaceDensity)
            }
        }
        guard configured != 0 else { throw GarmentDrapeError.initializationFailed }
        if !body.layers.isEmpty, let profile = body.fitProfile {
            let guides = GarmentFitter.contactGuides(for: prepared.asset, positions: fittedVertices, body: profile)
            let origins = pack(guides.origins)
            let axes = pack(guides.axes)
            let guided = origins.withUnsafeBufferPointer { origins in
                axes.withUnsafeBufferPointer { axes in
                    weashion_cloth_set_contact_guides(simulation, origins.baseAddress, axes.baseAddress,
                                                       Int32(fittedVertices.count))
                }
            }
            guard guided != 0 else { throw GarmentDrapeError.initializationFailed }
        }
        let pinned = placement.pins.withUnsafeBufferPointer {
            weashion_cloth_pin_vertices(simulation, $0.baseAddress, Int32($0.count))
        }
        guard pinned != 0 else { throw GarmentDrapeError.initializationFailed }
        if preservingShape {
            guard let fitting = prepared.asset.fitting, prepared.asset.sizing != nil else {
                throw GarmentDrapeError.invalidAsset
            }
            let limits = fitting.weights.indices.map { index in
                let weight = fitting.weights[index]
                let point = prepared.asset.vertices[index]
                return weight.preservesNeckShape(at: point) ? Float.zero
                    : 0.040 * sqrt(1 - weight.hoodShapeWeight(at: point))
            }
            let status = limits.withUnsafeBufferPointer {
                weashion_cloth_project_shape(simulation, $0.baseAddress, Int32(limits.count), 12) {
                    Task<Never, Never>.isCancelled ? 1 : 0
                }
            }
            if status == -1 { throw CancellationError() }
            guard status == 2 else { throw GarmentDrapeError.simulationFailed }
        } else {
            for _ in 0..<72 {
                try Task.checkCancellation()
                let status = weashion_cloth_step(simulation, 1) { Task<Never, Never>.isCancelled ? 1 : 0 }
                if status == -1 { throw CancellationError() }
                guard status != 0 else { throw GarmentDrapeError.simulationFailed }
                if status == 2 { break }
            }
        }
        try Task.checkCancellation()
        var output = Array(repeating: Float.zero, count: prepared.positions.count)
        output.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(simulation, $0.baseAddress) }
        let positions = stride(from: 0, to: output.count, by: 3).map {
            SIMD3<Float>(output[$0], output[$0 + 1], output[$0 + 2])
        }
        let strain = weashion_cloth_max_strain(simulation)
        let rawOverlap = weashion_cloth_remaining_overlap(simulation)
        let physicsAt = ContinuousClock.now
        let (display, bodyOverlap) = try makeDisplay(asset: prepared.asset, positions: positions, simulation: simulation)
        let overlap = max(rawOverlap, bodyOverlap)
        guard strain.isFinite, overlap.isFinite,
              positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw GarmentDrapeError.simulationFailed
        }
        let summary = body.fitProfile.map {
            GarmentFitSummary(asset: prepared.asset, positions: positions, body: $0,
                              maximumStrain: strain, remainingOverlap: overlap)
        }
        #if DEBUG
        print("GARMENT_PHASE \(definition.pattern.id) layers=\(body.layers.count) finalPasses=\(weashion_cloth_final_contact_passes(simulation)) overlap=\(overlap) displayBody=\(bodyOverlap) prepare=\(started.duration(to: preparedAt)) placement=\(preparedAt.duration(to: placedAt)) physics=\(placedAt.duration(to: physicsAt)) display=\(physicsAt.duration(to: .now))")
        #endif
        try Task.checkCancellation()
        let result = GarmentDrapeResult(asset: prepared.asset, positions: positions,
                                       displayVertices: display.vertices, displayIndices: display.indices,
                                       maximumStrain: strain, remainingOverlap: overlap, summary: summary,
                                       displayBodyOverlap: bodyOverlap)
        results.insert(result, for: key, cost: result.memoryCost)
        return result
    }

    private func makeDisplay(asset: GarmentMeshAsset, positions: [SIMD3<Float>],
                             simulation: OpaquePointer) throws -> (GarmentSurface, Float) {
        var invalidSample = false
        let surface = GarmentSurface(vertices: positions, indices: asset.indices).smoothed { point in
            let depth = [point.x, point.y, point.z].withUnsafeBufferPointer {
                weashion_cloth_body_depth(simulation, $0.baseAddress)
            }
            if !depth.isFinite { invalidSample = true }
            return depth
        }
        guard !invalidSample else { throw GarmentDrapeError.simulationFailed }
        var overlap: Float = 0
        let packed = pack(surface.vertices)
        let indices = surface.indices.map { Int32($0) }
        let measured = packed.withUnsafeBufferPointer { points in
            indices.withUnsafeBufferPointer { indices in
                weashion_cloth_measure_body_overlap(simulation, points.baseAddress, Int32(surface.vertices.count),
                    indices.baseAddress, Int32(surface.indices.count / 3), &overlap,
                    { Task<Never, Never>.isCancelled ? 1 : 0 })
            }
        }
        if measured == -1 { throw CancellationError() }
        guard measured == 1, overlap.isFinite else { throw GarmentDrapeError.simulationFailed }
        return (surface, overlap)
    }

    private func prepare(_ descriptor: GarmentPatternDescriptor) throws -> PreparedGarment {
        if let cached = patterns.value(for: descriptor) { return cached }
        let asset: GarmentMeshAsset
        switch descriptor.source {
        case .mesh:
            guard let resource = descriptor.meshResource else { throw GarmentDrapeError.invalidAsset }
            let sourceKey = "\(resource)#\(descriptor.version)"
            let loaded: GarmentMeshAsset
            if let cached = sources[sourceKey] {
                loaded = cached
            } else {
                guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
                      let attributes = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let fileSize = attributes.fileSize, fileSize <= 16 * 1024 * 1024,
                      let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(GarmentMeshAsset.self, from: data),
                      decoded.isValid else {
                    throw GarmentDrapeError.invalidAsset
                }
                sources[sourceKey] = decoded
                loaded = decoded
            }
            if let dimensions = descriptor.dimensions {
                guard let sizing = loaded.sizing,
                      let resized = sizing.resized(loaded, to: dimensions,
                          preservingNeckShape: descriptor.fittingMode == .shapePreserving) else {
                    throw GarmentDrapeError.invalidAsset
                }
                asset = resized
            } else if let dimensions = descriptor.trouserDimensions {
                guard let resized = LowerGarmentFitter.resized(loaded, to: dimensions) else {
                    throw GarmentDrapeError.invalidAsset
                }
                asset = resized
            } else if let dimensions = descriptor.footwearDimensions {
                guard let resized = LowerGarmentFitter.resized(loaded, to: dimensions) else {
                    throw GarmentDrapeError.invalidAsset
                }
                asset = resized
            } else {
                asset = loaded
            }
        }
        guard asset.isValid else { throw GarmentDrapeError.invalidAsset }
        if descriptor.fittingMode == .shapePreserving {
            guard asset.fitting != nil, asset.sizing != nil, asset.sleeves != nil else {
                throw GarmentDrapeError.invalidAsset
            }
        }
        let prepared = PreparedGarment(asset: asset, positions: pack(asset.vertices),
                                      triangles: asset.indices.map { Int32($0) })
        patterns.insert(prepared, for: descriptor, cost: prepared.memoryCost)
        return prepared
    }

    private func prepareBody(_ snapshot: GarmentBodySnapshot) throws -> OpaquePointer {
        let key = CollisionKey(body: snapshot.key, layers: snapshot.layers.map(\.key))
        if bodyKey == key, let context { return context }
        guard var mesh = snapshot.collision, !mesh.indices.isEmpty,
              mesh.armTriangles.count == mesh.indices.count / 3 else { throw GarmentDrapeError.initializationFailed }
        guard snapshot.layers.count <= 3 else { throw GarmentDrapeError.initializationFailed }
        var groups = Array(repeating: UInt8(0), count: mesh.indices.count / 3)
        for (index, layer) in snapshot.layers.enumerated() {
            let base = UInt32(mesh.vertices.count)
            mesh.vertices += layer.surface.vertices
            mesh.indices += layer.surface.indices.map { $0 + base }
            mesh.armTriangles += layer.surface.armTriangles
            groups += Array(repeating: UInt8(index + 1), count: layer.surface.indices.count / 3)
        }
        if let context { weashion_cloth_destroy(context) }
        context = nil
        bodyKey = nil
        let points = pack(mesh.vertices)
        let indices = mesh.indices.map { Int32($0) }
        let created = points.withUnsafeBufferPointer { positions in
            indices.withUnsafeBufferPointer { triangles in
                mesh.armTriangles.withUnsafeBufferPointer { arms in
                    groups.withUnsafeBufferPointer { groups in
                        weashion_cloth_create_layered_body(positions.baseAddress, Int32(mesh.vertices.count), triangles.baseAddress,
                                                          Int32(indices.count / 3), arms.baseAddress, groups.baseAddress)
                    }
                }
            }
        }
        guard let created else { throw GarmentDrapeError.initializationFailed }
        context = created
        bodyKey = key
        return created
    }

    private func pack(_ vertices: [SIMD3<Float>]) -> [Float] {
        var packed: [Float] = []
        packed.reserveCapacity(vertices.count * 3)
        for point in vertices { packed.append(contentsOf: [point.x, point.y, point.z]) }
        return packed
    }

    // Knit stretched across the body shortens lengthwise; 0.4 is an estimated ratio, not a measured value.
    private nonisolated static func lengthwiseShortening(asset: GarmentMeshAsset, fitting: GarmentFitProfile,
                                                         stretch: [Float], sleeveStretch: Float) -> [SIMD3<Float>]? {
        let bottom = asset.vertices.map(\.y).min() ?? 0
        guard stretch.contains(where: { $0 > 0.001 }) || sleeveStretch > 0.001, bottom < -0.01 else { return nil }
        let heights = [fitting.hip.center.y, fitting.waist.center.y, fitting.chest.center.y, fitting.shoulderHeight]
        let values = stretch + [0]
        func tension(at height: Float) -> Float {
            if height <= heights[0] { return values[0] }
            for index in 1..<heights.count where height <= heights[index] {
                let progress = (height - heights[index - 1]) / max(heights[index] - heights[index - 1], 0.001)
                return values[index - 1] + (values[index] - values[index - 1]) * progress
            }
            return 0
        }
        let samples = 128
        let step = bottom / Float(samples)
        var rise: [Float] = [0]
        for sample in 1...samples {
            rise.append(rise[sample - 1] - step * 0.4 * tension(at: step * (Float(sample) - 0.5)))
        }
        let sleeve = asset.sizing.map { sizing in
            (axis: simd_normalize(sizing.rightCuff - sizing.rightShoulder),
             shift: 0.4 * sleeveStretch * sizing.reference.sleeveLength)
        }
        return asset.vertices.indices.map { index in
            let point = asset.vertices[index]
            let progress = fitting.weights[index].sleeveProgress
            let position = min(max(point.y / step, 0), Float(samples))
            let lower = min(Int(position), samples - 1)
            let lift = rise[lower] + (rise[lower + 1] - rise[lower]) * (position - Float(lower))
            var offset = SIMD3<Float>(0, lift * (1 - progress), 0)
            if let sleeve, progress > 0 {
                offset -= sleeve.axis * SIMD3<Float>(point.x < 0 ? -1 : 1, 1, 1) * (sleeve.shift * progress)
            }
            return offset
        }
    }

    private nonisolated struct SimulationKey: Hashable, Sendable {
        let pattern: GarmentPatternDescriptor
        let body: GarmentBodyKey
        let fabric: GarmentFabricSettings
        let layers: [GarmentLayerKey]
        let solverVersion: Int
    }

    private nonisolated struct CollisionKey: Hashable, Sendable {
        let body: GarmentBodyKey
        let layers: [GarmentLayerKey]
    }
    private nonisolated struct PreparedGarment: Sendable {
        let asset: GarmentMeshAsset
        let positions: [Float]
        let triangles: [Int32]

        var memoryCost: Int { asset.memoryCost + (positions.count + triangles.count) * 4 }
    }
}

private nonisolated struct GarmentMemoryCache<Key: Hashable, Value> {
    private nonisolated struct Entry {
        let value: Value
        let cost: Int
        var accessed: UInt64
    }

    let limit: Int
    private var entries: [Key: Entry] = [:]
    private var cost = 0
    private var clock: UInt64 = 0

    init(limit: Int) { self.limit = limit }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.accessed = clock
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, cost entryCost: Int) {
        let payloadCost = max(entryCost, 64)
        guard payloadCost <= limit else { return }
        if let previous = entries.removeValue(forKey: key) { cost -= previous.cost }
        while cost + payloadCost > limit, let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed }) {
            cost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: payloadCost, accessed: clock)
        cost += payloadCost
    }
}