import LuParser
import Foundation

// Differential-oracle helper (mirrors the Haskell reference `diff-oracle`). Three
// modes, each reading one record per line from stdin:
//
//   luparser-diff pretty   <kind>   wire AST        -> base64(pretty(ast))
//   luparser-diff reparse  <kind>   base64(string)  -> wire AST  | "FAIL"
//   luparser-diff roundtrip <kind>  wire AST        -> "true" | "false" | "discard"
//
// where <kind> ∈ {val, exp, stat}. The cross-parse oracle uses `pretty` on one
// implementation and `reparse` on the other: if the Haskell parser recovers the
// AST from this port's rendering (and vice versa), both the parser and the
// pretty-printer are validated against the independent reference.

func b64e(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
func b64d(_ s: String) -> String? {
    guard let d = Data(base64Encoded: s) else { return nil }
    return String(data: d, encoding: .utf8)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: luparser-diff <pretty|reparse|roundtrip> <val|exp|stat>\n".utf8))
    exit(2)
}
let mode = args[1], kind = args[2]

func prettyWire(_ wire: String) -> String {
    do {
        let e = try parseSExpr(wire)
        switch kind {
        case "val": return b64e(prettyValue(try decodeValue(e)))
        case "exp": return b64e(prettyExpression(try decodeExpr(e)))
        default: return b64e(prettyStatement(try decodeStatement(e)))
        }
    } catch { return "ERR \(error)" }
}

func reparse(_ b64: String) -> String {
    guard let s = b64d(b64) else { return "FAIL" }
    switch kind {
    case "val":
        if case let .ok(v) = parseValueString(s) { return encodeValue(v) }
    case "exp":
        if case let .ok(e) = parseExpressionString(s) { return encodeExpr(e) }
    default:
        if case let .ok(st) = parseStatementString(s) { return encodeStatement(st) }
    }
    return "FAIL"
}

func roundtrip(_ wire: String) -> String {
    do {
        let r = try evaluate(property: "roundtrip_\(kind == "val" ? "val" : kind == "exp" ? "exp" : "stat")", input: wire)
        return r.map { $0 ? "true" : "false" } ?? "discard"
    } catch { return "ERR \(error)" }
}

while let line = readLine(strippingNewline: true) {
    let s = line.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { continue }
    switch mode {
    case "pretty": print(prettyWire(s))
    case "reparse": print(reparse(s))
    case "roundtrip": print(roundtrip(s))
    default:
        FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8)); exit(2)
    }
}
