// Round-trip spec — ported from alpaylan/etna-haskell-luparser `src/Spec.hs`.
//
// Property: for every *parsable* AST, `parse(pretty(ast)) == ast`. The
// "parsable" precondition excludes ASTs the grammar can't represent (names that
// are empty / start with a digit / contain a reserved word, strings with quotes
// or non-printable characters). Properties return `Bool?`:
//   - `true`  → round-trip held
//   - `false` → counterexample (a mutant broke parse/print)
//   - `nil`   → discarded (input not parsable; precondition false)

import Foundation

// MARK: - Preconditions

private func isPrintable(_ c: Character) -> Bool {
    c.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
}

func doesNotContainQuotes(_ s: String) -> Bool {
    !s.contains("\"") && s.allSatisfy { isPrintable($0) || $0.isWhitespace }
}

func doesNotContainReservedWords(_ s: String) -> Bool {
    !reserved.contains { s.contains($0) }
}

func containsOnlyAlphaNumeralsOrUnderscore(_ s: String) -> Bool {
    s.allSatisfy { $0.isLetter || ($0.isASCII && $0.isNumber) || $0 == "_" }
}

func startsWithLowerUpperOrUnderscore(_ s: String) -> Bool {
    guard let c = s.first else { return false }
    return c.isLowercase || c.isUppercase || c == "_"
}

func nameIsParsable(_ n: VarName) -> Bool {
    !n.raw.isEmpty
        && startsWithLowerUpperOrUnderscore(n.raw)
        && containsOnlyAlphaNumeralsOrUnderscore(n.raw)
        && doesNotContainReservedWords(n.raw)
}

func valueIsParsable(_ v: Value) -> Bool {
    if case let .StringVal(s) = v { return doesNotContainQuotes(s) }
    return true
}

func varIsParsable(_ v: Var) -> Bool {
    switch v {
    case let .Name(n): return nameIsParsable(n)
    case let .Dot(e, n): return expressionIsParsable(e) && nameIsParsable(n)
    case let .Proj(e1, e2): return expressionIsParsable(e1) && expressionIsParsable(e2)
    }
}

func expressionIsParsable(_ e: Expression) -> Bool {
    switch e {
    case let .Var(v): return varIsParsable(v)
    case let .Val(v): return valueIsParsable(v)
    case let .Op1(_, e1): return expressionIsParsable(e1)
    case let .Op2(e1, _, e2): return expressionIsParsable(e1) && expressionIsParsable(e2)
    case let .TableConst(fs):
        return fs.allSatisfy { f in
            switch f {
            case let .FieldName(n, e1): return nameIsParsable(n) && expressionIsParsable(e1)
            case let .FieldKey(e1, e2): return expressionIsParsable(e1) && expressionIsParsable(e2)
            }
        }
    }
}

func blockIsParsable(_ b: Block) -> Bool {
    b.statements.allSatisfy(statementIsParsable)
}

func statementIsParsable(_ s: Statement) -> Bool {
    switch s {
    case let .Assign(v, e): return varIsParsable(v) && expressionIsParsable(e)
    case let .If(e, b1, b2): return expressionIsParsable(e) && blockIsParsable(b1) && blockIsParsable(b2)
    case let .While(e, b): return expressionIsParsable(e) && blockIsParsable(b)
    case let .Repeat(b, e): return blockIsParsable(b) && expressionIsParsable(e)
    case .Empty: return true
    }
}

// MARK: - Properties

public func prop_roundtrip_val(_ v: Value) -> Bool? {
    guard valueIsParsable(v) else { return nil }
    return parse(valueP, prettyValue(v)) == .ok(v)
}

public func prop_roundtrip_exp(_ e: Expression) -> Bool? {
    guard expressionIsParsable(e) else { return nil }
    return parse(expP, prettyExpression(e)) == .ok(e)
}

public func prop_roundtrip_stat(_ s: Statement) -> Bool? {
    guard statementIsParsable(s) else { return nil }
    return parse(statementP, prettyStatement(s)) == .ok(s)
}

/// Property names this workload understands (matches `etna.toml`).
public let luparserProperties = ["roundtrip_val", "roundtrip_exp", "roundtrip_stat"]
