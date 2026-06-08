// Lu abstract syntax — ported from alpaylan/etna-haskell-luparser `src/LuSyntax.hs`
// (itself adapted from a UPenn CIS 5520 homework). A small Lua-like language:
// values, expressions with unary/binary operators and table constructors,
// statements (assign / if / while / repeat / empty), and blocks.
//
// The workload's property is a parser/pretty-printer round-trip:
//     parse(pretty(ast)) == ast
// for every *parsable* AST (see Spec.swift for the precondition).

public struct VarName: Sendable, Equatable, Hashable, Codable {
    public var raw: String
    public init(_ raw: String) { self.raw = raw }
}

public enum Value: Sendable, Equatable, Hashable, Codable {
    case NilVal
    case IntVal(Int)
    case BoolVal(Bool)
    case StringVal(String)
}

// Declaration order matters: the generator's `arbitraryBoundedEnum` analog and
// the wire encoder rely on it (mirrors Haskell's derived Enum/Bounded).
public enum Uop: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case Neg   // `-`
    case Not   // `not`
    case Len   // `#`
}

public enum Bop: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case Plus, Minus, Times, Divide, Modulo
    case Eq, Gt, Ge, Lt, Le
    case Concat
}

public indirect enum Var: Sendable, Equatable, Hashable, Codable {
    case Name(VarName)             // x
    case Dot(Expression, VarName)  // t.x
    case Proj(Expression, Expression) // t[e]
}

public enum TableField: Sendable, Equatable, Hashable, Codable {
    case FieldName(VarName, Expression) // x = e
    case FieldKey(Expression, Expression) // [e1] = e2
}

public indirect enum Expression: Sendable, Equatable, Hashable, Codable {
    case Var(Var)
    case Val(Value)
    case Op1(Uop, Expression)
    case Op2(Expression, Bop, Expression)
    case TableConst([TableField])
}

public indirect enum Statement: Sendable, Equatable, Hashable, Codable {
    case Assign(Var, Expression)
    case If(Expression, Block, Block)
    case While(Expression, Block)
    case Empty
    case Repeat(Block, Expression)
}

public struct Block: Sendable, Equatable, Hashable, Codable {
    public var statements: [Statement]
    public init(_ statements: [Statement]) { self.statements = statements }
}

/// Operator precedence level (`src/Level.hs`). NB: `Modulo` and all comparison
/// operators fall through to level 3 — only `Times/Divide` (7), `Plus/Minus`
/// (5) and `Concat` (4) are distinguished. The parser's precedence-climbing
/// layers and the pretty-printer's parenthesization both key off this.
public func level(_ b: Bop) -> Int {
    switch b {
    case .Times, .Divide: return 7
    case .Plus, .Minus: return 5
    case .Concat: return 4
    default: return 3
    }
}
