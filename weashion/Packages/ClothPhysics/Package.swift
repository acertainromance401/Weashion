// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClothPhysics",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ClothPhysics", targets: ["ClothPhysics"])],
    targets: [
        .target(
            name: "ClothPhysics",
            path: ".",
            exclude: ["README.md", "LICENSE.txt"],
            sources: [
                "ClothPhysics.cpp", "src/LinearMath", "src/BulletCollision"
            ],
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("src")]
        )
    ],
    cxxLanguageStandard: .cxx17
)