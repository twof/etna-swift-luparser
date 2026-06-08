// Wire (de)serialization for ASTs — an S-expression form used by witnesses,
// counterexamples, the unit tests, and the differential oracle. String payloads
// (VarName text, StringVal contents) are base64-encoded and `#`-prefixed so they
// survive the whitespace/paren tokenizer untouched (empty string → bare `#`).
//
//   value  := (NilVal) | (IntVal <int>) | (BoolVal true|false) | (StringVal #<b64>)
//   uop    := Neg | Not | Len
//   bop    := Plus | Minus | Times | Divide | Modulo | Eq | Gt | Ge | Lt | Le | Concat
//   vname  := (VarName #<b64>)
//   var    := (Name <vname>) | (Dot <expr> <vname>) | (Proj <expr> <expr>)
//   field  := (FieldName <vname> <expr>) | (FieldKey <expr> <expr>)
//   expr   := (Var <var>) | (Val <value>) | (Op1 <uop> <expr>)
//           | (Op2 <expr> <bop> <expr>) | (TableConst (<field>...))
//   stat   := (Assign <var> <expr>) | (If <expr> <block> <block>)
//           | (While <expr> <block>) | (Empty) | (Repeat <block> <expr>)
//   block  := (Block (<stat>...))
//
// Both this port and the Haskell `diff-oracle` use exactly this form.

import Foundation

// MARK: - S-expression parser

public enum SExpr: Equatable {
    case atom(String)
    case list([SExpr])
}

public enum DecodeError: Error, CustomStringConvertible {
    case malformed(String)
    public var description: String {
        if case let .malformed(m) = self { return "malformed S-expr: \(m)" }
        return "malformed S-expr"
    }
}

private func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    var cur = ""
    func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
    for ch in s {
        switch ch {
        case "(", ")": flush(); tokens.append(String(ch))
        case " ", "\t", "\n", "\r": flush()
        default: cur.append(ch)
        }
    }
    flush()
    return tokens
}

private func parseTokens(_ tokens: inout ArraySlice<String>) throws -> SExpr {
    guard let head = tokens.first else { throw DecodeError.malformed("unexpected end") }
    tokens = tokens.dropFirst()
    switch head {
    case "(":
        var elems: [SExpr] = []
        while let next = tokens.first, next != ")" { elems.append(try parseTokens(&tokens)) }
        guard tokens.first == ")" else { throw DecodeError.malformed("missing )") }
        tokens = tokens.dropFirst()
        return .list(elems)
    case ")":
        throw DecodeError.malformed("unexpected )")
    default:
        return .atom(head)
    }
}

public func parseSExpr(_ s: String) throws -> SExpr {
    var toks = tokenize(s)[...]
    let r = try parseTokens(&toks)
    guard toks.isEmpty else { throw DecodeError.malformed("trailing tokens") }
    return r
}

// MARK: - base64 string payloads

private func encStr(_ s: String) -> String { "#" + Data(s.utf8).base64EncodedString() }

private func decStr(_ e: SExpr) throws -> String {
    guard case let .atom(a) = e, a.hasPrefix("#") else { throw DecodeError.malformed("not a #string: \(e)") }
    let b64 = String(a.dropFirst())
    if b64.isEmpty { return "" }
    guard let data = Data(base64Encoded: b64), let s = String(data: data, encoding: .utf8) else {
        throw DecodeError.malformed("bad base64: \(a)")
    }
    return s
}

private func decInt(_ e: SExpr) throws -> Int {
    guard case let .atom(a) = e, let n = Int(a) else { throw DecodeError.malformed("not an int: \(e)") }
    return n
}

private func decAtom(_ e: SExpr) throws -> String {
    guard case let .atom(a) = e else { throw DecodeError.malformed("not an atom: \(e)") }
    return a
}

// MARK: - Encoders

public func encodeValue(_ v: Value) -> String {
    switch v {
    case .NilVal: return "(NilVal)"
    case let .IntVal(i): return "(IntVal \(i))"
    case let .BoolVal(b): return "(BoolVal \(b ? "true" : "false"))"
    case let .StringVal(s): return "(StringVal \(encStr(s)))"
    }
}

private func encVarName(_ n: VarName) -> String { "(VarName \(encStr(n.raw)))" }

public func encodeVar(_ v: Var) -> String {
    switch v {
    case let .Name(n): return "(Name \(encVarName(n)))"
    case let .Dot(e, k): return "(Dot \(encodeExpr(e)) \(encVarName(k)))"
    case let .Proj(e1, e2): return "(Proj \(encodeExpr(e1)) \(encodeExpr(e2)))"
    }
}

private func encField(_ f: TableField) -> String {
    switch f {
    case let .FieldName(n, e): return "(FieldName \(encVarName(n)) \(encodeExpr(e)))"
    case let .FieldKey(e1, e2): return "(FieldKey \(encodeExpr(e1)) \(encodeExpr(e2)))"
    }
}

public func encodeExpr(_ e: Expression) -> String {
    switch e {
    case let .Var(v): return "(Var \(encodeVar(v)))"
    case let .Val(v): return "(Val \(encodeValue(v)))"
    case let .Op1(o, e1): return "(Op1 \(o.rawValue) \(encodeExpr(e1)))"
    case let .Op2(e1, b, e2): return "(Op2 \(encodeExpr(e1)) \(b.rawValue) \(encodeExpr(e2)))"
    case let .TableConst(fs): return "(TableConst (\(fs.map(encField).joined(separator: " "))))"
    }
}

public func encodeStatement(_ s: Statement) -> String {
    switch s {
    case let .Assign(v, e): return "(Assign \(encodeVar(v)) \(encodeExpr(e)))"
    case let .If(g, b1, b2): return "(If \(encodeExpr(g)) \(encodeBlock(b1)) \(encodeBlock(b2)))"
    case let .While(g, b): return "(While \(encodeExpr(g)) \(encodeBlock(b)))"
    case .Empty: return "(Empty)"
    case let .Repeat(b, e): return "(Repeat \(encodeBlock(b)) \(encodeExpr(e)))"
    }
}

public func encodeBlock(_ b: Block) -> String {
    "(Block (\(b.statements.map(encodeStatement).joined(separator: " "))))"
}

// MARK: - Decoders

private func tagged(_ e: SExpr) throws -> (String, [SExpr]) {
    guard case let .list(items) = e, let first = items.first, case let .atom(tag) = first else {
        throw DecodeError.malformed("not a tagged list: \(e)")
    }
    return (tag, items)
}

public func decodeValue(_ e: SExpr) throws -> Value {
    let (tag, items) = try tagged(e)
    switch tag {
    case "NilVal": return .NilVal
    case "IntVal": return .IntVal(try decInt(items[1]))
    case "BoolVal": return .BoolVal(try decAtom(items[1]) == "true")
    case "StringVal": return .StringVal(try decStr(items[1]))
    default: throw DecodeError.malformed("unknown value tag: \(tag)")
    }
}

private func decVarName(_ e: SExpr) throws -> VarName {
    let (tag, items) = try tagged(e)
    guard tag == "VarName" else { throw DecodeError.malformed("not a VarName: \(e)") }
    return VarName(try decStr(items[1]))
}

public func decodeVar(_ e: SExpr) throws -> Var {
    let (tag, items) = try tagged(e)
    switch tag {
    case "Name": return .Name(try decVarName(items[1]))
    case "Dot": return .Dot(try decodeExpr(items[1]), try decVarName(items[2]))
    case "Proj": return .Proj(try decodeExpr(items[1]), try decodeExpr(items[2]))
    default: throw DecodeError.malformed("unknown var tag: \(tag)")
    }
}

private func decField(_ e: SExpr) throws -> TableField {
    let (tag, items) = try tagged(e)
    switch tag {
    case "FieldName": return .FieldName(try decVarName(items[1]), try decodeExpr(items[2]))
    case "FieldKey": return .FieldKey(try decodeExpr(items[1]), try decodeExpr(items[2]))
    default: throw DecodeError.malformed("unknown field tag: \(tag)")
    }
}

public func decodeExpr(_ e: SExpr) throws -> Expression {
    let (tag, items) = try tagged(e)
    switch tag {
    case "Var": return .Var(try decodeVar(items[1]))
    case "Val": return .Val(try decodeValue(items[1]))
    case "Op1":
        guard let o = Uop(rawValue: try decAtom(items[1])) else { throw DecodeError.malformed("bad uop") }
        return .Op1(o, try decodeExpr(items[2]))
    case "Op2":
        guard let b = Bop(rawValue: try decAtom(items[2])) else { throw DecodeError.malformed("bad bop") }
        return .Op2(try decodeExpr(items[1]), b, try decodeExpr(items[3]))
    case "TableConst":
        guard case let .list(fs) = items[1] else { throw DecodeError.malformed("TableConst fields") }
        return .TableConst(try fs.map(decField))
    default: throw DecodeError.malformed("unknown expr tag: \(tag)")
    }
}

public func decodeStatement(_ e: SExpr) throws -> Statement {
    let (tag, items) = try tagged(e)
    switch tag {
    case "Assign": return .Assign(try decodeVar(items[1]), try decodeExpr(items[2]))
    case "If": return .If(try decodeExpr(items[1]), try decodeBlock(items[2]), try decodeBlock(items[3]))
    case "While": return .While(try decodeExpr(items[1]), try decodeBlock(items[2]))
    case "Empty": return .Empty
    case "Repeat": return .Repeat(try decodeBlock(items[1]), try decodeExpr(items[2]))
    default: throw DecodeError.malformed("unknown stat tag: \(tag)")
    }
}

public func decodeBlock(_ e: SExpr) throws -> Block {
    let (tag, items) = try tagged(e)
    guard tag == "Block", case let .list(ss) = items[1] else { throw DecodeError.malformed("not a Block: \(e)") }
    return Block(try ss.map(decodeStatement))
}

// MARK: - Kinded dispatch (for witnesses / property evaluation)

/// Evaluate a named round-trip property against a wire-encoded input.
/// Returns `nil` on discard (non-parsable input).
public func evaluate(property: String, input: String) throws -> Bool? {
    let e = try parseSExpr(input)
    switch property {
    case "roundtrip_val": return prop_roundtrip_val(try decodeValue(e))
    case "roundtrip_exp": return prop_roundtrip_exp(try decodeExpr(e))
    case "roundtrip_stat": return prop_roundtrip_stat(try decodeStatement(e))
    default: throw DecodeError.malformed("unknown property: \(property)")
    }
}
