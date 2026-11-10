import RealityKit
import simd

nonisolated struct BodySurfaceMesh: Sendable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]

    func prepared() -> Prepared {
        var normals = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let first = Int(indices[triangle])
            let second = Int(indices[triangle + 1])
            let third = Int(indices[triangle + 2])
            let normal = simd_cross(vertices[second] - vertices[first], vertices[third] - vertices[first])
            normals[first] += normal
            normals[second] += normal
            normals[third] += normal
        }
        for index in normals.indices {
            let magnitude = simd_length(normals[index])
            normals[index] = magnitude > 1e-12 ? normals[index] / magnitude : [0, 1, 0]
        }
        return Prepared(surface: self, normals: normals)
    }

    @MainActor
    func model(material: SimpleMaterial) -> ModelComponent? {
        guard let mesh = try? MeshResource.generate(from: [prepared().descriptor()]) else { return nil }
        return ModelComponent(mesh: mesh, materials: [material])
    }

    nonisolated struct Prepared: Sendable {
        let surface: BodySurfaceMesh
        let normals: [SIMD3<Float>]

        @MainActor
        func descriptor() -> MeshDescriptor {
            var descriptor = MeshDescriptor(name: "WEASHION_BodySurface")
            descriptor.positions = MeshBuffers.Positions(surface.vertices)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(surface.indices)
            return descriptor
        }

        @MainActor
        func model(material: SimpleMaterial) async throws -> ModelComponent {
            let mesh = try await MeshResource(from: [descriptor()])
            try Task.checkCancellation()
            return ModelComponent(mesh: mesh, materials: [material])
        }
    }
}