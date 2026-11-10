import Foundation

actor BodyPreviewRenderer {
    static let shared = BodyPreviewRenderer()

    nonisolated struct Request: Hashable, Sendable {
        let base: String
        let measurements: [Double]
        let scales: [Double]
        let shapeProfile: BodyShapeProfile?

        @MainActor
        init(body: UserBody, base: MannequinBase) {
            self.base = base.rawValue
            measurements = [body.height, body.weight, body.shoulderWidth,
                            body.measurementValue(.chest, base: base), body.measurementValue(.waist, base: base),
                            body.measurementValue(.hip, base: base), body.legLength,
                            body.armSize, body.legSize, body.footLength ?? 0]
            scales = BodyAnatomy.Part.allCases.map { body.partScale(for: $0) }
                + BodyAnatomy.ShapeAdjustment.allCases.map {
                    $0.isFemaleOnly && base != .female ? 1 : body.shapeScale(for: $0)
                }
            shapeProfile = body.shapeProfile(for: base)
        }

        var bodyMeasurements: ParametricBody.Measurements {
            ParametricBody.Measurements(
                height: Float(measurements[0] / 100), weight: Float(measurements[1]),
                shoulderWidth: Float(measurements[2] / 100), chest: Float(measurements[3] / 100),
                waist: Float(measurements[4] / 100), hip: Float(measurements[5] / 100),
                inseam: Float(measurements[6] / 100), armSize: Float(measurements[7]),
                legSize: Float(measurements[8]), feminine: base == "female")
        }

        var partScales: [String: Double] {
            let keys = BodyAnatomy.Part.allCases.map(\.rawValue)
                + BodyAnatomy.ShapeAdjustment.allCases.map(\.rawValue)
            return Dictionary(uniqueKeysWithValues: zip(keys, scales).filter { $0.1 != 1 })
        }
    }

    private var meshes: [String: MannequinMesh] = [:]
    private var cachedBase: String?
    private var cachedMeasurements: [Double] = []
    private var cachedProfile: BodyShapeProfile?
    private var cachedSurface: BodySurfaceMesh?
    private var cachedDeformation: BodyAnatomy.Deformation?
    private var fittingRequest: Request?
    private var fittingResult: FittingResult?
    private(set) var fittingPreparationCount = 0

    func releaseCachedResources() {
        meshes.removeAll()
        cachedBase = nil
        cachedMeasurements = []
        cachedProfile = nil
        cachedSurface = nil
        cachedDeformation = nil
        fittingRequest = nil
        fittingResult = nil
    }

    nonisolated struct FittingResult: Sendable {
        let fitted: MannequinMesh.Fitted
        let surface: BodySurfaceMesh.Prepared
    }

    func prepareFitting(_ request: Request) throws -> FittingResult {
        try Task.checkCancellation()
        if fittingRequest == request, let fittingResult { return fittingResult }
        if meshes[request.base] == nil {
            meshes[request.base] = MannequinMesh.load(resource: request.base + "_body_40k")
        }
        guard let fitted = meshes[request.base]?.fitted(
            to: request.bodyMeasurements,
            footLength: request.measurements[9] > 0 ? Float(request.measurements[9] / 1000) : nil,
            partScales: request.partScales, shapeProfile: request.shapeProfile
        ) else { throw PreparationError.invalidBody }
        try Task.checkCancellation()
        let result = FittingResult(fitted: fitted, surface: fitted.surface.prepared())
        try Task.checkCancellation()
        fittingRequest = request
        fittingResult = result
        fittingPreparationCount += 1
        return result
    }

    enum PreparationError: Error {
        case invalidBody
    }

    func render(_ request: Request) throws -> BodySurfaceMesh.Prepared? {
        try Task.checkCancellation()
        if cachedBase != request.base || cachedMeasurements != request.measurements || cachedProfile != request.shapeProfile {
            if meshes[request.base] == nil {
                meshes[request.base] = MannequinMesh.load(resource: request.base + "_body_40k")
            }
            let values = request.measurements
                guard let fitted = meshes[request.base]?.fitted(to: request.bodyMeasurements,
                    footLength: values[9] > 0 ? Float(values[9] / 1000) : nil, includeGarmentFit: false,
                    shapeProfile: request.shapeProfile) else { return nil }
            let deformation = meshes[request.base]?.prepareDeformation(in: fitted.surface.vertices,
                                                                       feminine: request.bodyMeasurements.feminine)
            try Task.checkCancellation()
            cachedSurface = fitted.surface
            cachedDeformation = deformation
            cachedBase = request.base
            cachedMeasurements = values
            cachedProfile = request.shapeProfile
        }
        guard let surface = cachedSurface else { return nil }
        let vertices = cachedDeformation?.vertices(scales: request.partScales) ?? surface.vertices
        try Task.checkCancellation()
        let prepared = BodySurfaceMesh(vertices: vertices, indices: surface.indices).prepared()
        try Task.checkCancellation()
        return prepared
    }
}