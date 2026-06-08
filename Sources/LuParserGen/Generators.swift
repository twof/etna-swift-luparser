import LuParser
import PropertyTestingKit

// MARK: - Bespoke parsable-AST generator (the crux)
//
// Ported from the ETNA reference's `Strategy/Correct.hs`: a size-controlled
// generator that produces ASTs satisfying the round-trip precondition *by
// construction* — names drawn from a fixed reserved-word-free set, string
// literals built from printable non-quote characters. A naive "arbitrary AST"
// generator (the reference's `Random`/`Hybrid`) almost never produces a parsable
// term, so the round-trip property discards ~everything and finds nothing. This
// generator is what makes the workload tractable; PTK layers edge-coverage
// feedback on top of it.

// MARK: QuickCheck-style combinators over FastRNG

func elements<T>(_ xs: [T], _ rng: inout FastRNG) -> T {
    xs[Int.random(in: 0..<xs.count, using: &rng)]
}

func oneof<T>(_ gs: [(inout FastRNG) -> T], _ rng: inout FastRNG) -> T {
    gs[Int.random(in: 0..<gs.count, using: &rng)](&rng)
}

/// Weighted choice; weights must sum to > 0.
func frequency<T>(_ gs: [(Int, (inout FastRNG) -> T)], _ rng: inout FastRNG) -> T {
    let total = gs.reduce(0) { $0 + $1.0 }
    let n = Int.random(in: 1...total, using: &rng)
    var acc = 0
    for (w, g) in gs {
        acc += w
        if n <= acc { return g(&rng) }
    }
    return gs[gs.count - 1].1(&rng)
}

// MARK: Leaves

/// Names guaranteed not to be / contain reserved words. Includes digit-bearing
/// names (`x0`, `X0`) so the `nameP_2` mutant (no digits in names) is witnessed.
let namePool = ["_", "_G", "x", "X", "y", "x0", "X0", "xy", "XY", "_x"]

func genName(_ rng: inout FastRNG) -> VarName { VarName(elements(namePool, &rng)) }

/// Printable, non-quote string-literal content (satisfies `doesNotContainQuotes`).
let strAlphabet: [Character] = (0x20...0x7E).compactMap { code -> Character? in
    let c = Character(UnicodeScalar(code)!)
    return c == "\"" ? nil : c
}

func genStringLit(_ rng: inout FastRNG) -> String {
    let len = Int.random(in: 0...6, using: &rng)
    return String((0..<len).map { _ in elements(strAlphabet, &rng) })
}

func genValue(_ rng: inout FastRNG) -> Value {
    oneof([
        { r in .IntVal(Int.random(in: -1000...1000, using: &r)) },
        { r in .BoolVal(Bool.random(using: &r)) },
        { _ in .NilVal },
        { r in .StringVal(genStringLit(&r)) },
    ], &rng)
}

func genUop(_ rng: inout FastRNG) -> Uop { elements(Uop.allCases, &rng) }
func genBop(_ rng: inout FastRNG) -> Bop { elements(Bop.allCases, &rng) }

// MARK: Size-controlled recursion

func genVar(_ n: Int, _ rng: inout FastRNG) -> Var {
    if n <= 0 { return .Name(genName(&rng)) }
    let h = n / 2
    return frequency([
        (1, { r in .Name(genName(&r)) }),
        (n, { r in .Dot(genExp(h, &r), genName(&r)) }),
        (n, { r in .Proj(genExp(h, &r), genExp(h, &r)) }),
    ], &rng)
}

func genTableField(_ n: Int, _ rng: inout FastRNG) -> TableField {
    let h = n / 2
    return oneof([
        { r in .FieldName(genName(&r), genExp(h, &r)) },
        { r in .FieldKey(genExp(h, &r), genExp(h, &r)) },
    ], &rng)
}

func genTableFields(_ n: Int, _ rng: inout FastRNG) -> [TableField] {
    let len = Int.random(in: 0...3, using: &rng)
    return (0..<len).map { _ in genTableField(n, &rng) }
}

func genExp(_ n: Int, _ rng: inout FastRNG) -> Expression {
    if n <= 0 {
        return oneof([
            { r in .Var(genVar(0, &r)) },
            { r in .Val(genValue(&r)) },
        ], &rng)
    }
    let h = n / 2
    return frequency([
        (1, { r in .Var(genVar(n, &r)) }),
        (1, { r in .Val(genValue(&r)) }),
        (n, { r in .Op1(genUop(&r), genExp(h, &r)) }),
        (n, { r in .Op2(genExp(h, &r), genBop(&r), genExp(h, &r)) }),
        (max(1, h), { r in .TableConst(genTableFields(h, &r)) }),
    ], &rng)
}

func genBlock(_ n: Int, _ rng: inout FastRNG) -> Block {
    func genStmts(_ n: Int, _ rng: inout FastRNG) -> [Statement] {
        if n <= 0 { return [] }
        let h = n / 2
        return frequency([
            (1, { _ in [] }),
            (n, { r in [genStatement(h, &r)] + genStmts(h, &r) }),
        ], &rng)
    }
    return Block(genStmts(n, &rng))
}

func genStatement(_ n: Int, _ rng: inout FastRNG) -> Statement {
    if n <= 1 {
        return oneof([
            { r in .Assign(genVar(0, &r), genExp(0, &r)) },
            { _ in .Empty },
        ], &rng)
    }
    let h = n / 2
    return frequency([
        (1, { r in .Assign(genVar(h, &r), genExp(h, &r)) }),
        (1, { _ in .Empty }),
        (n, { r in .If(genExp(h, &r), genBlock(h, &r), genBlock(h, &r)) }),
        (max(1, h), { r in .While(genExp(h, &r), genBlock(h, &r)) }),
        (max(1, h), { r in .Repeat(genBlock(h, &r), genExp(h, &r)) }),
    ], &rng)
}

// MARK: - Top-level generators (random size, like QC.sized)

func randomSize(_ rng: inout FastRNG) -> Int { Int.random(in: 1...10, using: &rng) }

public func genValueTop(_ rng: inout FastRNG) -> Value { genValue(&rng) }
public func genExpTop(_ rng: inout FastRNG) -> Expression { genExp(randomSize(&rng), &rng) }
public func genStatementTop(_ rng: inout FastRNG) -> Statement { genStatement(randomSize(&rng), &rng) }

// MARK: - Point mutations (input-derived, structure-preserving)
//
// Each `mutate` returns a handful of small variations of its input, keeping it
// parsable: tweak a leaf, regenerate one subtree, or swap an operator. PTK's
// coverage-guided loop walks these from the corpus.

private func tweakValue(_ v: Value, _ rng: inout FastRNG) -> Value {
    switch v {
    case let .IntVal(i): return .IntVal(i + (Bool.random(using: &rng) ? 1 : -1))
    case let .BoolVal(b): return .BoolVal(!b)
    case let .StringVal(s): return .StringVal(s + String(elements(strAlphabet, &rng)))
    case .NilVal: return genValue(&rng)
    }
}

public func mutateValue(_ v: Value) -> [Value] {
    var rng = FastRNG()
    return [tweakValue(v, &rng), genValue(&rng)]
}

public func mutateExpr(_ e: Expression) -> [Expression] {
    var rng = FastRNG()
    var out: [Expression] = []
    switch e {
    case let .Var(v): out.append(.Var(v))
    case let .Val(v): out.append(.Val(tweakValue(v, &rng)))
    case let .Op1(o, inner):
        out.append(inner)                                   // unwrap
        out.append(.Op1(elements(Uop.allCases, &rng), inner)) // swap operator
    case let .Op2(l, b, r):
        out.append(l); out.append(r)                        // each side
        out.append(.Op2(l, elements(Bop.allCases, &rng), r)) // swap operator
    case let .TableConst(fs):
        if let f = fs.first, case let .FieldName(_, fe) = f { out.append(fe) }
        out.append(.TableConst(fs + [.FieldName(genName(&rng), genExp(2, &rng))]))
    }
    out.append(genExp(randomSize(&rng), &rng))              // fresh
    return out
}

public func mutateStatement(_ s: Statement) -> [Statement] {
    var rng = FastRNG()
    var out: [Statement] = []
    switch s {
    case let .Assign(v, e): out.append(.Assign(v, .Op1(.Neg, e)))
    case let .If(g, b1, b2):
        out.append(.If(g, b2, b1))                          // swap branches
        out.append(.While(g, b1))
    case let .While(g, b): out.append(.If(g, b, Block([])))
    case .Empty: break
    case let .Repeat(b, e): out.append(.While(e, b))
    }
    out.append(genStatement(randomSize(&rng), &rng))        // fresh
    return out
}

// MARK: - MutatorProviding conformances + seeds
//
// Seeds directly exercise the mutated code paths so the structural bugs surface
// in the first handful of inputs: an empty string (stringValP), a `not`/unary
// expression (ppNot), a `>=` comparison (bofP), a digit-bearing name (nameP_2),
// an `if`/parenthesized form (statementP / stringP / wsP).

extension Value: MutatorProviding {
    public static var defaultMutator: Mutator<Value> {
        Mutator(
            seeds: [.IntVal(0), .StringVal(""), .StringVal("a0_"), .BoolVal(true), .BoolVal(false), .NilVal],
            mutate: { mutateValue($0) },
            generate: { genValueTop(&$0) }
        )
    }
}

extension Expression: MutatorProviding {
    public static var defaultMutator: Mutator<Expression> {
        Mutator(
            seeds: [
                .Op1(.Not, .Val(.BoolVal(true))),                                  // ppNot, isBase
                .Op2(.Val(.IntVal(1)), .Ge, .Val(.IntVal(2))),                     // bofP (>=)
                .Var(.Name(VarName("x0"))),                                        // nameP_2 (digit)
                .Val(.StringVal("")),                                              // stringValP_1
                .Op2(.Val(.IntVal(1)), .Plus, .Op2(.Val(.IntVal(2)), .Times, .Val(.IntVal(3)))), // precedence
                .TableConst([.FieldName(VarName("x"), .Val(.IntVal(1)))]),         // braces (stringP)
                .Var(.Proj(.Var(.Name(VarName("t"))), .Val(.IntVal(1)))),          // indexing
            ],
            mutate: { mutateExpr($0) },
            generate: { genExpTop(&$0) }
        )
    }
}

extension Statement: MutatorProviding {
    public static var defaultMutator: Mutator<Statement> {
        Mutator(
            seeds: [
                .If(.Val(.BoolVal(true)), Block([.Empty]), Block([.Empty])),       // statementP_1, stringP
                .Assign(.Name(VarName("x")), .Op2(.Val(.IntVal(1)), .Ge, .Val(.IntVal(2)))), // bofP via stat
                .Assign(.Name(VarName("x0")), .Op1(.Not, .Val(.BoolVal(false)))),  // nameP_2 + ppNot
                .While(.Val(.BoolVal(true)), Block([.Assign(.Name(VarName("y")), .Val(.IntVal(0)))])),
                .Repeat(Block([.Empty]), .Val(.StringVal(""))),                    // stringValP via stat
            ],
            mutate: { mutateStatement($0) },
            generate: { genStatementTop(&$0) }
        )
    }
}
