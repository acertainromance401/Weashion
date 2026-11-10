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
            cxxSettings: [
                .headerSearchPath("src"),
                // The solver is too slow to use at -O0 when the app runs in Debug.
                .unsafeFlags(["-O2"], .when(configuration: .debug))
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)