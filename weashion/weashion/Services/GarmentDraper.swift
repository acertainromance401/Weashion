import Foundation
import ClothPhysics
import simd

nonisolated struct GarmentBodyKey: Hashable, Sendable {
    let id: UUID
    let revision: Int
    let anchor: SIMD3<Float>
}

nonisolated struct GarmentBodySnapshot: Sendable {
    let key: GarmentBodyKey
    let bands: [GarmentCollisionBand]
    let fitProfile: GarmentBodyFitProfile?
}

nonisolated struct GarmentDrapeResult: Sendable {
    let asset: GarmentMeshAsset
    let positions: [SIMD3<Float>]
    let maximumStrain: Float
    let remainingOverlap: Float

    var memoryCost: Int {
        asset.memoryCost + positions.count * MemoryLayout<SIMD3<Float>>.stride
    }
}

nonisolated enum GarmentDrapeError: Error, Equatable {
    case invalidAsset
    case initializationFailed
    case simulationFailed
}

actor GarmentDraper {
    static let shared = GarmentDraper()
    private var patterns = GarmentMemoryCache<GarmentPatternDescriptor, PreparedGarment>(limit: 16 * 1024 * 1024)
    private var results = GarmentMemoryCache<SimulationKey, GarmentDrapeResult>(limit: 8 * 1024 * 1024)
    private var bodyKey: GarmentBodyKey?
    private var context: OpaquePointer?

    private init() {}

    func settle(definition: GarmentDefinition, body: GarmentBodySnapshot) throws -> GarmentDrapeResult {
        try Task.checkCancellation()
        guard definition.isValid else { throw GarmentDrapeError.invalidAsset }
        let key = SimulationKey(pattern: definition.pattern, body: body.key, solverVersion: 9)
        if let cached = results.value(for: key) { return cached }
        let prepared = try prepare(definition.pattern)
        try Task.checkCancellation()
        let fitted = pack(GarmentFitter.positions(for: prepared.asset, body: body.fitProfile))
        try Task.checkCancellation()
        let simulation = try prepareBody(body)
        try Task.checkCancellation()
        let initialized = prepared.positions.withUnsafeBufferPointer { positions in
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
        for _ in 0..<12 {
            try Task.checkCancellation()
            let status = weashion_cloth_step(simulation, 1) { Task<Never, Never>.isCancelled ? 1 : 0 }
            if status == -1 { throw CancellationError() }
            guard status != 0 else { throw GarmentDrapeError.simulationFailed }
            if status == 2 { break }
        }
        try Task.checkCancellation()
        var output = Array(repeating: Float.zero, count: prepared.positions.count)
        output.withUnsafeMutableBufferPointer { weashion_cloth_copy_positions(simulation, $0.baseAddress) }
        let positions = stride(from: 0, to: output.count, by: 3).map {
            SIMD3<Float>(output[$0], output[$0 + 1], output[$0 + 2])
        }
        let strain = weashion_cloth_max_strain(simulation)
        let overlap = weashion_cloth_remaining_overlap(simulation)
        guard strain.isFinite, overlap.isFinite,
              positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw GarmentDrapeError.simulationFailed
        }
        let result = GarmentDrapeResult(asset: prepared.asset, positions: positions, maximumStrain: strain, remainingOverlap: overlap)
        results.insert(result, for: key, cost: result.memoryCost)
        return result
    }

    private func prepare(_ descriptor: GarmentPatternDescriptor) throws -> PreparedGarment {
        if let cached = patterns.value(for: descriptor) { return cached }
        let asset: GarmentMeshAsset
        switch descriptor.source {
        case .cottonTShirt:
            guard let dimensions = descriptor.dimensions, dimensions.isValid else { throw GarmentDrapeError.invalidAsset }
            asset = CottonTShirtTemplate.makePattern(dimensions)
        case .mesh:
            guard let resource = descriptor.meshResource,
                  let url = Bundle.main.url(forResource: resource, withExtension: "json"),
                  let attributes = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = attributes.fileSize, fileSize <= 16 * 1024 * 1024,
                  let data = try? Data(contentsOf: url),
                  let loaded = try? JSONDecoder().decode(GarmentMeshAsset.self, from: data) else {
                throw GarmentDrapeError.invalidAsset
            }
            asset = loaded
        }
        guard asset.isValid else { throw GarmentDrapeError.invalidAsset }
        let prepared = PreparedGarment(asset: asset, positions: pack(asset.vertices), triangles: asset.indices.map { Int32($0) })
        patterns.insert(prepared, for: descriptor, cost: prepared.memoryCost)
        return prepared
    }

    private func prepareBody(_ snapshot: GarmentBodySnapshot) throws -> OpaquePointer {
        if bodyKey == snapshot.key, let context { return context }
        guard !snapshot.bands.isEmpty else { throw GarmentDrapeError.initializationFailed }
        if let context { weashion_cloth_destroy(context) }
        context = nil
        bodyKey = nil
        var points: [Float] = []
        points.reserveCapacity(snapshot.bands.reduce(0) { $0 + $1.vertices.count * 3 })
        for band in snapshot.bands {
            for point in band.vertices { points.append(contentsOf: [point.x, point.y, point.z]) }
        }
        let counts = snapshot.bands.map { Int32($0.vertices.count) }
        let created = points.withUnsafeBufferPointer { positions in
            counts.withUnsafeBufferPointer { bands in
                weashion_cloth_create_body(positions.baseAddress, bands.baseAddress, Int32(snapshot.bands.count))
            }
        }
        guard let created else { throw GarmentDrapeError.initializationFailed }
        context = created
        bodyKey = snapshot.key
        return created
    }

    private func pack(_ vertices: [SIMD3<Float>]) -> [Float] {
        var packed: [Float] = []
        packed.reserveCapacity(vertices.count * 3)
        for point in vertices { packed.append(contentsOf: [point.x, point.y, point.z]) }
        return packed
    }

    private nonisolated struct SimulationKey: Hashable, Sendable {
        let pattern: GarmentPatternDescriptor
        let body: GarmentBodyKey
        let solverVersion: Int
    }

    private nonisolated struct PreparedGarment: Sendable {
        let asset: GarmentMeshAsset
        let positions: [Float]
        let triangles: [Int32]

        var memoryCost: Int { asset.memoryCost + positions.count * 4 + triangles.count * 4 }
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