// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastVLMRuntime",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "FastVLMRuntime", targets: ["FastVLMRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.2.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19")
    ],
    targets: [
        .target(
            name: "FastVLMRuntime",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "app/FastVLM",
            exclude: ["FastVLM.h"]
        )
    ]
)
