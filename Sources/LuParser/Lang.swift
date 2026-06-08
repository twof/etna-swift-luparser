// The Lu parser + pretty-printer — ported from alpaylan/etna-haskell-luparser
// `src/LuParser.hs` and `src/PrettyPrinter.hs`. This is the mutated source: ETNA's
// marauder source-swap activates one variant block and recompiles per task. All
// mutatable bodies live in this one file (matching marauder.toml's note).
//
// Mutants ported here are the *structural* parser/printer bugs — the ones a
// round-trip property can actually witness. (The reference's `reserved_*`,
// `nameP_1` and `tableConstP_1` mutants are deliberately omitted: the first three
// require a name equal-to / containing a reserved word, which the round-trip
// precondition `doesNotContainReservedWords` excludes — so they are unwitnessable;
// `tableConstP_1` does not even type-check in the Haskell reference.)
//
// Rendering note: the parser is whitespace-insensitive (every token-parser is
// `wsP`-wrapped), so this pretty-printer renders with simple single-space
// separation instead of replicating HughesPJ's width-driven layout. What it DOES
// replicate faithfully is the *parenthesization / precedence* logic — that is the
// part the round-trip depends on. The cross-parse differential oracle against the
// Haskell reference (which uses Text.PrettyPrint) confirms mutual compatibility.

import Foundation

// MARK: - Recursive-reference helper
//
// The grammar is mutually recursive (expr ↔ var ↔ block ↔ statement). Each parser
// is a lazily-initialized global; back-edges are deferred through `recur` so a
// global's initializer never touches another global mid-initialization.

func recur<A>(_ f: @escaping () -> Parser<A>) -> Parser<A> {
    Parser { s in f().doParse(s) }
}

// MARK: - Lexing helpers

/// Run `p`, then consume trailing whitespace.
func wsP<A>(_ p: Parser<A>) -> Parser<A> {
    /*| wsP */
    return p <* many(spaceChar)
    /*|| wsP_1 */
    /*|
    return p <* some(spaceChar)
    */
    /* |*/
}

/// Parse the literal string `s` (consuming trailing whitespace).
func stringP(_ s: String) -> Parser<Void> {
    /*| stringP */
    return wsP(string(s)).map { _ in () }
    /*|| stringP_1 */
    /*|
    return string(s).map { _ in () }
    */
    /* |*/
}

func constP<A>(_ s: String, _ v: A) -> Parser<A> { stringP(s).map { _ in v } }

func parens<A>(_ x: Parser<A>) -> Parser<A> { between(stringP("("), x, stringP(")")) }
func braces<A>(_ x: Parser<A>) -> Parser<A> { between(stringP("{"), x, stringP("}")) }
func brackets<A>(_ x: Parser<A>) -> Parser<A> { between(stringP("["), x, stringP("]")) }

// MARK: - Values

let intValP: Parser<Value> = wsP(int).map { Value.IntVal($0) }

let boolValP: Parser<Value> = {
    /*| boolValP */
    return wsP(string("true")).map { _ in Value.BoolVal(true) }
        <|> wsP(string("false")).map { _ in Value.BoolVal(false) }
    /*|| boolValP_1 */
    /*|
    return string("true").map { _ in Value.BoolVal(true) }
        <|> string("false").map { _ in Value.BoolVal(false) }
    */
    /* |*/
}()

let nilValP: Parser<Value> = wsP(string("nil")).map { _ in Value.NilVal }

/// A single character of string-literal content.
let anyStrChar: Parser<Character> = {
    /*| anyStrChar */
    return satisfy { $0 != "\"" }
    /*|| stringValP_4 */
    /*|
    return satisfy { _ in true }
    */
    /* |*/
}()

func quotes<A>(_ x: Parser<A>) -> Parser<A> { between(string("\""), x, stringP("\"")) }

let stringValP: Parser<Value> = {
    /*| stringValP */
    return quotes(some(anyStrChar) <|> pure([])).map { Value.StringVal(String($0)) }
    /*|| stringValP_1 */
    /*|
    return quotes(some(anyStrChar)).map { Value.StringVal(String($0)) }
    */
    /*|| stringValP_2 */
    /*|
    return quotes(some(alpha)).map { Value.StringVal(String($0)) }
    */
    /*|| stringValP_3 */
    /*|
    return (quotes(some(anyStrChar)) <|> pure([])).map { Value.StringVal(String($0)) }
    */
    /* |*/
}()

let valueP: Parser<Value> = intValP <|> boolValP <|> nilValP <|> stringValP

// MARK: - Operators

let uopP: Parser<Uop> = wsP(constP("-", Uop.Neg) <|> constP("not", Uop.Not) <|> constP("#", Uop.Len))

let bopP: Parser<Bop> = wsP(
    constP("+", Bop.Plus)
    <|> constP("-", Bop.Minus)
    <|> constP("*", Bop.Times)
    <|> constP("//", Bop.Divide)
    <|> constP("%", Bop.Modulo)
    <|> constP("==", Bop.Eq)
    // `>=` must be tried before `>` so the longer operator wins.
    /*| bopP */
    <|> constP(">=", Bop.Ge)
    <|> constP(">", Bop.Gt)
    /*|| bofP_1 */
    /*|
    <|> constP(">", Bop.Gt)
    <|> constP(">=", Bop.Ge)
    */
    /* |*/
    <|> constP("<=", Bop.Le)
    <|> constP("<", Bop.Lt)
    <|> constP("..", Bop.Concat)
)

func opAtLevel(_ l: Int) -> Parser<(Expression, Expression) -> Expression> {
    filterP({ level($0) == l }, bopP).map { bop in
        { (e1: Expression, e2: Expression) in Expression.Op2(e1, bop, e2) }
    }
}

// MARK: - Names

let reserved: Set<String> = [
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
]

let nameFirst: Parser<Character> = lower <|> upper <|> char("_")

let nameRest: Parser<[Character]> = {
    /*| nameP_rest */
    return many(choice([alpha, char("_"), digit]))
    /*|| nameP_2 */
    /*|
    return many(choice([alpha, char("_")]))
    */
    /* |*/
}()

let nameP: Parser<String> = wsP(
    filterP({ !reserved.contains($0) },
            nameFirst.flatMap { c in nameRest.map { String([c] + $0) } })
)

// MARK: - Variables

func mkVar(_ e: Expression, _ l: [(Expression) -> Var]) -> Var {
    // foldr1 (\f acc -> \u -> acc (Var (f u))) l, applied to e.
    var acc: (Expression) -> Var = l[l.count - 1]
    var i = l.count - 2
    while i >= 0 {
        let f = l[i]
        let prev = acc
        acc = { u in prev(.Var(f(u))) }
        i -= 1
    }
    return acc(e)
}

let prefixP: Parser<Expression> =
    parens(recur { expP }) <|> nameP.map { Expression.Var(.Name(VarName($0))) }

let indexP: Parser<(Expression) -> Var> =
    (string(".") *> nameP.map { VarName($0) }).map { vn in { (e: Expression) in Var.Dot(e, vn) } }
    <|> brackets(recur { expP }).map { k in { (e: Expression) in Var.Proj(e, k) } }

let varP: Parser<Var> =
    prefixP.flatMap { e in some(indexP).map { l in mkVar(e, l) } }
    <|> nameP.map { Var.Name(VarName($0)) }

// MARK: - Expressions (precedence climbing)

let baseP: Parser<Expression> =
    recur { tableConstP }
    <|> recur { varP }.map { Expression.Var($0) }
    <|> parens(recur { expP })
    <|> valueP.map { Expression.Val($0) }

// `Op1` (prefix unary) binds tighter than any binary operator.
let uopexpP: Parser<Expression> =
    baseP <|> (uopP.flatMap { o in recur { uopexpP }.map { Expression.Op1(o, $0) } })

let prodP: Parser<Expression> = chainl1(uopexpP, opAtLevel(level(.Times)))   // level 7
let sumP: Parser<Expression>  = chainl1(prodP, opAtLevel(level(.Plus)))      // level 5
let catP: Parser<Expression>  = chainl1(sumP, opAtLevel(level(.Concat)))     // level 4
let compP: Parser<Expression> = chainl1(catP, opAtLevel(level(.Gt)))         // level 3
let expP: Parser<Expression> = compP

// MARK: - Tables

let tableFieldP: Parser<TableField> =
    nameP.map { VarName($0) }.flatMap { name in
        (wsP(char("=")) *> recur { expP }).map { TableField.FieldName(name, $0) }
    }
    <|> brackets(recur { expP }).flatMap { k in
        (wsP(char("=")) *> recur { expP }).map { TableField.FieldKey(k, $0) }
    }

let tableConstP: Parser<Expression> =
    braces(sepBy(tableFieldP, wsP(char(",")))).map { Expression.TableConst($0) }

// MARK: - Statements & blocks

let statementP: Parser<Statement> = wsP(
    varP.flatMap { v in (wsP(char("=")) *> recur { expP }).map { Statement.Assign(v, $0) } }
    /*| statementP_if */
    <|> (wsP(stringP("if")) *> recur { expP }).flatMap { g in
            (wsP(stringP("then")) *> recur { blockP }).flatMap { b1 in
                (wsP(stringP("else")) *> recur { blockP } <* wsP(stringP("end"))).map { b2 in
                    Statement.If(g, b1, b2)
                }
            }
        }
    /*|| statementP_1 */
    /*|
    <|> (wsP(stringP("if")) *> recur { expP }).flatMap { g in
            (wsP(stringP("then")) *> recur { blockP }).flatMap { b1 in
                (wsP(stringP("else")) *> recur { blockP }).map { b2 in
                    Statement.If(g, b1, b2)
                }
            }
        }
    */
    /* |*/
    <|> (wsP(stringP("while")) *> recur { expP }).flatMap { g in
            (wsP(stringP("do")) *> recur { blockP } <* wsP(stringP("end"))).map { Statement.While(g, $0) }
        }
    <|> wsP(constP(";", Statement.Empty))
    <|> (wsP(stringP("repeat")) *> recur { blockP }).flatMap { b in
            (wsP(stringP("until")) *> recur { expP }).map { Statement.Repeat(b, $0) }
        }
)

let blockP: Parser<Block> = wsP(many(recur { statementP }).map { Block($0) })

// MARK: - Pretty-printer
//
// Faithful parenthesization, simple single-space layout. See file header.

func ppUop(_ u: Uop) -> String {
    switch u {
    case .Neg: return "-"
    case .Not:
        /*| ppNot */
        return "not"
        /*|| ppNot_1 */
        /*|
        return "nil"
        */
        /* |*/
    case .Len: return "#"
    }
}

func ppBop(_ b: Bop) -> String {
    switch b {
    case .Plus: return "+"
    case .Minus: return "-"
    case .Times: return "*"
    case .Divide: return "//"
    case .Modulo: return "%"
    case .Gt: return ">"
    case .Ge: return ">="
    case .Lt: return "<"
    case .Le: return "<="
    case .Eq: return "=="
    case .Concat: return ".."
    }
}

func ppValue(_ v: Value) -> String {
    switch v {
    case .NilVal: return "nil"
    case let .IntVal(i): return String(i)
    case let .BoolVal(b): return b ? "true" : "false"
    case let .StringVal(s): return "\"" + s + "\""
    }
}

func ppVarName(_ n: VarName) -> String { n.raw }

func ppVar(_ v: Var) -> String {
    switch v {
    case let .Name(n):
        return ppVarName(n)
    case let .Dot(e, k):
        if case let .Var(inner) = e { return ppVar(inner) + "." + ppVarName(k) }
        return "(" + ppExpr(e) + ")." + ppVarName(k)
    case let .Proj(e, k):
        if case let .Var(inner) = e { return ppVar(inner) + "[" + ppExpr(k) + "]" }
        return "(" + ppExpr(e) + ")[" + ppExpr(k) + "]"
    }
}

func isBase(_ e: Expression) -> Bool {
    switch e {
    case .TableConst, .Val, .Var, .Op1: return true
    default: return false
    }
}

func ppExpr(_ e: Expression) -> String {
    switch e {
    case let .Var(v): return ppVar(v)
    case let .Val(v): return ppValue(v)
    case let .Op1(o, v):
        return ppUop(o) + " " + (isBase(v) ? ppExpr(v) : "(" + ppExpr(v) + ")")
    case .Op2:
        return ppPrec(0, e)
    case let .TableConst(fs):
        return "{" + fs.map(ppField).joined(separator: ", ") + "}"
    }
}

func ppPrec(_ n: Int, _ e: Expression) -> String {
    if case let .Op2(e1, bop, e2) = e {
        let l = level(bop)
        let inner = ppPrec(l, e1) + " " + ppBop(bop) + " " + ppPrec(l + 1, e2)
        return l < n ? "(" + inner + ")" : inner
    }
    return ppExpr(e)
}

func ppField(_ f: TableField) -> String {
    switch f {
    case let .FieldName(name, e): return ppVarName(name) + " = " + ppExpr(e)
    case let .FieldKey(e1, e2): return "[" + ppExpr(e1) + "] = " + ppExpr(e2)
    }
}

func ppBlock(_ b: Block) -> String {
    b.statements.map(ppStatement).joined(separator: " ")
}

func ppStatement(_ s: Statement) -> String {
    switch s {
    case let .Assign(x, e):
        return ppVar(x) + " = " + ppExpr(e)
    case let .If(g, b1, b2):
        return "if " + ppExpr(g) + " then " + ppBlock(b1) + " else " + ppBlock(b2) + " end"
    case let .While(g, b):
        return "while " + ppExpr(g) + " do " + ppBlock(b) + " end"
    case .Empty:
        return ";"
    case let .Repeat(b, e):
        return "repeat " + ppBlock(b) + " until " + ppExpr(e)
    }
}

// MARK: - `pretty` entry points (per round-trip kind)

public func prettyValue(_ v: Value) -> String { ppValue(v) }
public func prettyExpression(_ e: Expression) -> String { ppExpr(e) }
public func prettyStatement(_ s: Statement) -> String { ppStatement(s) }

// `parse` entry points (per round-trip kind), exposed for the differential oracle.
public func parseValueString(_ s: String) -> ParseResult<Value> { parse(valueP, s) }
public func parseExpressionString(_ s: String) -> ParseResult<Expression> { parse(expP, s) }
public func parseStatementString(_ s: String) -> ParseResult<Statement> { parse(statementP, s) }
