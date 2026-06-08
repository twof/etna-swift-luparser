// swift-tools-version: 6.2
import PackageDescription

// PropertyTestingKit requires the patched Swift toolchain (parameter packs) and
// macOS 26. Build via ./scripts/swift-toolchain.sh, not system `swift`.
//
// `-sanitize-coverage=edge,pc-table` instruments the code under test so PTK's
// SanCovHooks can observe edge coverage; `-sanitize=undefined` matches PTK's own
// build. Any product linking the instrumented `LuParser` module must also link
// PTK (which provides the SanitizerCoverage callbacks).
let sanitize: [SwiftSetting] = [
    .unsafeFlags(["-sanitize=undefined", "-sanitize-coverage=edge,pc-table"])
]

let package = Package(
    name: "etna-swift-luparser",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "luparser", targets: ["Solve"]),
        .executable(name: "luparser-sampler", targets: ["luparser-sampler"]),
        .executable(name: "luparser-diff", targets: ["luparser-diff"]),
    ],
    dependencies: [
        .package(path: "../PropertyTestingKit"),
    ],
    targets: [
        // System under test: Lu syntax, the applicative parser-combinator lib,
        // the parser, the pretty-printer, the round-trip spec, the wire
        // (de)serializer, and the marauder mutants. Instrumented for coverage.
        .target(
            name: "LuParser",
            swiftSettings: sanitize
        ),
        // PTK-backed bespoke parsable-AST generator + coverage-guided strategy.
        .target(
            name: "LuParserGen",
            dependencies: [
                "LuParser",
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
        // Target dir is `Solve` (not `luparser`) to avoid a case-insensitive
        // filesystem clash with the `LuParser` library; the product is `luparser`.
        .executableTarget(
            name: "Solve",
            dependencies: ["LuParserGen"],
            swiftSettings: sanitize
        ),
        .executableTarget(
            name: "luparser-sampler",
            dependencies: ["LuParserGen"],
            swiftSettings: sanitize
        ),
        // Differential-oracle helper: stdin AST -> pretty / reparse, for
        // cross-checking against the independent Haskell reference parser+printer.
        .executableTarget(
            name: "luparser-diff",
            dependencies: [
                "LuParser",
                // Provides the SanitizerCoverage runtime for instrumented LuParser.
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
        .testTarget(
            name: "LuParserTests",
            dependencies: [
                "LuParser",
                "LuParserGen",
                // Provides the SanitizerCoverage runtime for instrumented LuParser.
                .product(name: "PropertyTestingKit", package: "PropertyTestingKit"),
            ],
            swiftSettings: sanitize
        ),
    ]
)
