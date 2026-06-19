import LuParser
import PropertyTestingKit
import Foundation
import os

/// Thrown by the fuzz closure when a round-trip fails; carries the failing AST in
/// wire form so `solve` can report it as the counterexample.
struct PropertyViolation: Error { let wire: String }

/// Outcome of one solve run, shaped for ETNA's result JSON.
public struct SolveOutcome: Sendable {
    public let status: String          // "passed" | "failed" | "aborted"
    public let tests: Int
    public let discards: Int
    public let counterexample: String?
    public let error: String?
    public let timeNs: UInt64

    public init(status: String, tests: Int, discards: Int, counterexample: String?, error: String?, timeNs: UInt64) {
        self.status = status
        self.tests = tests
        self.discards = discards
        self.counterexample = counterexample
        self.error = error
        self.timeNs = timeNs
    }
}

private func jsonEscape(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default: out.append(c)
        }
    }
    return out
}

extension SolveOutcome {
    public var json: String {
        let cex = counterexample.map { "\"\(jsonEscape($0))\"" } ?? "null"
        let err = error.map { "\"\(jsonEscape($0))\"" } ?? "null"
        return """
        {"status":"\(status)","tests":\(tests),"discards":\(discards),"counterexample":\(cex),"error":\(err),"time":"\(timeNs)ns","execution_time":null,"generation_time":null,"shrinking_time":null}
        """
    }
}

/// Parallel fuzz engines (default: core count). The stop-at-first-counterexample
/// plugin halts the finding engine and PTK cancels its siblings, so `solve` still
/// returns at the first counterexample with time-to-find. Override with
/// `LUPARSER_PARALLELISM`.
let enginesParallelism: Int = {
    if let v = ProcessInfo.processInfo.environment["LUPARSER_PARALLELISM"], let n = Int(v), n > 0 { return n }
    return ProcessInfo.processInfo.processorCount
}()

/// Run the coverage-guided fuzzer over `Input`, checking `check` (false =
/// counterexample, nil = discard, true = pass). `wire` serializes a failing input.
private func runFuzz<Input: MutatorProviding & Codable & Hashable>(
    duration: Duration,
    coverageStrategy: CoverageStrategy,
    check: @escaping @Sendable (Input) -> Bool?,
    wire: @escaping @Sendable (Input) -> String
) async -> SolveOutcome {
    let discards = OSAllocatedUnfairLock(initialState: 0)
    let start = DispatchTime.now()
    func elapsed() -> UInt64 { DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds }

    do {
        let result = try await fuzz(
            duration: duration,
            persistence: .ephemeral,
            coverageStrategy: coverageStrategy,
            // PTK_SCHEDULER selects the pool configuration. The DEFAULT (bare
            // MutationScheduler.weightedPool()) is now feature-ownership culling, matching PTK's
            // flipped library default. "entropic" swaps in PTK's Entropic energy
            // scheduler (rare-feature entropy weighting); "everydiscovery"
            // restores the old keep-everything behavior.
            scheduler: {
                switch ProcessInfo.processInfo.environment["PTK_SCHEDULER"] {
                case "entropic": return MutationScheduler.weightedPool(policies: { [EntropicWeightPolicy()] })
                case "everydiscovery": return MutationScheduler.weightedPool(admission: .everyDiscovery)
                default: return MutationScheduler.weightedPool()
                }
            }(),
            parallelism: enginesParallelism,
            plugins: { [
                .stopOnFirstFailure(reason: .custom("counterexample_found")),
            ] }
        ) { (input: Input) in
            switch check(input) {
            case .some(false): throw PropertyViolation(wire: wire(input))
            case .none: discards.withLock { $0 += 1 }
            case .some(true): break
            }
        }
        return SolveOutcome(status: "passed", tests: result.stats.totalInputs,
                            discards: discards.withLock { $0 }, counterexample: nil, error: nil, timeNs: elapsed())
    } catch let e as FuzzError {
        guard case let .testFailed(_, underlying, _, stats) = e else {
            return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                                counterexample: nil, error: "\(e)", timeNs: elapsed())
        }
        return SolveOutcome(status: "failed", tests: stats.totalInputs,
                            discards: discards.withLock { $0 },
                            counterexample: (underlying as? PropertyViolation)?.wire, error: nil, timeNs: elapsed())
    } catch {
        return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                            counterexample: nil, error: "\(error)", timeNs: elapsed())
    }
}

public enum SolveError: Error { case unknownProperty(String), unknownStrategy(String) }

/// The PTK coverage strategies this workload exposes as ETNA strategy names.
/// `ptk` stays as a back-compat alias for the default (`.pathTrie`).
public func coverageStrategy(named name: String) throws -> CoverageStrategy {
    switch name {
    case "ptk", "ptk-pathtrie": return .pathTrie
    case "ptk-signaturematch": return .signatureMatch
    case "ptk-newedge": return .newEdge
    case "ptk-hitcountbuckets": return .hitCountBuckets
    default: throw SolveError.unknownStrategy(name)
    }
}

/// Coverage-guided solve: fuzz `property` for `duration` judging novelty with
/// `coverageStrategy`. The active mutant is whichever marauder variant is
/// compiled into `LuParser`.
public func solve(
    property: String,
    duration: Duration,
    coverageStrategy: CoverageStrategy = .pathTrie
) async throws -> SolveOutcome {
    switch property {
    case "roundtrip_val":
        return await runFuzz(duration: duration, coverageStrategy: coverageStrategy,
                             check: { prop_roundtrip_val($0) }, wire: { encodeValue($0) })
    case "roundtrip_exp":
        return await runFuzz(duration: duration, coverageStrategy: coverageStrategy,
                             check: { prop_roundtrip_exp($0) }, wire: { encodeExpr($0) })
    case "roundtrip_stat":
        return await runFuzz(duration: duration, coverageStrategy: coverageStrategy,
                             check: { prop_roundtrip_stat($0) }, wire: { encodeStatement($0) })
    default:
        throw SolveError.unknownProperty(property)
    }
}

// MARK: - Sampling (cross-language `sample` capability)

public func sample(property: String, count: Int) throws -> [(timeNs: UInt64, wire: String)] {
    guard luparserProperties.contains(property) else { throw SolveError.unknownProperty(property) }
    var rng = FastRNG()
    var out: [(UInt64, String)] = []
    out.reserveCapacity(count)
    for _ in 0..<count {
        let start = DispatchTime.now()
        let w: String
        switch property {
        case "roundtrip_val": w = encodeValue(genValueTop(&rng))
        case "roundtrip_exp": w = encodeExpr(genExpTop(&rng))
        default: w = encodeStatement(genStatementTop(&rng))
        }
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        out.append((ns, w))
    }
    return out
}
