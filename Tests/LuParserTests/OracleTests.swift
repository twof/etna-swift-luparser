import Testing
import LuParser
import LuParserGen
import PropertyTestingKit

// The clean implementation must round-trip every *parsable* AST. These tests
// pin that down on hand-written cases and on a large batch of generated ASTs.

@Suite struct OracleTests {

    @Test func value_roundtrips_on_examples() {
        let vs: [Value] = [.NilVal, .IntVal(0), .IntVal(-42), .IntVal(1000),
                           .BoolVal(true), .BoolVal(false), .StringVal(""), .StringVal("abc"),
                           .StringVal("a b_c 0"), .StringVal("// % .. >=")]
        for v in vs { #expect(prop_roundtrip_val(v) == true, "\(v)") }
    }

    @Test func expression_roundtrips_on_examples() {
        let es: [Expression] = [
            .Var(.Name(VarName("x0"))),
            .Op1(.Not, .Val(.BoolVal(true))),
            .Op1(.Neg, .Val(.IntVal(2))),
            .Op2(.Val(.IntVal(1)), .Ge, .Val(.IntVal(2))),
            .Op2(.Val(.IntVal(1)), .Plus, .Op2(.Val(.IntVal(2)), .Times, .Val(.IntVal(3)))),
            .Op2(.Op2(.Val(.IntVal(1)), .Plus, .Val(.IntVal(2))), .Times, .Val(.IntVal(3))),
            .TableConst([.FieldName(VarName("x"), .Val(.IntVal(1))),
                         .FieldKey(.Val(.IntVal(2)), .Val(.BoolVal(true)))]),
            .Var(.Proj(.Var(.Name(VarName("t"))), .Val(.IntVal(1)))),
            .Var(.Dot(.Var(.Name(VarName("t"))), VarName("k"))),
        ]
        for e in es { #expect(prop_roundtrip_exp(e) == true, "\(e)") }
    }

    @Test func statement_roundtrips_on_examples() {
        let ss: [Statement] = [
            .Empty,
            .Assign(.Name(VarName("x")), .Val(.IntVal(1))),
            .If(.Val(.BoolVal(true)), Block([.Empty]), Block([.Assign(.Name(VarName("y")), .Val(.IntVal(0)))])),
            .While(.Val(.BoolVal(true)), Block([.Empty, .Empty])),
            .Repeat(Block([.Assign(.Name(VarName("z")), .Val(.IntVal(3)))]), .Val(.BoolVal(false))),
        ]
        for s in ss { #expect(prop_roundtrip_stat(s) == true, "\(s)") }
    }

    @Test func generated_values_roundtrip() {
        var rng = FastRNG()
        var checked = 0
        for _ in 0..<5000 {
            let v = genValueTop(&rng)
            if let r = prop_roundtrip_val(v) { #expect(r == true, "\(v)"); checked += 1 }
        }
        #expect(checked > 4000)
    }

    @Test func generated_expressions_roundtrip() {
        var rng = FastRNG()
        var checked = 0
        for _ in 0..<5000 {
            let e = genExpTop(&rng)
            if let r = prop_roundtrip_exp(e) { #expect(r == true, "\(e)"); checked += 1 }
        }
        #expect(checked > 4000)
    }

    @Test func generated_statements_roundtrip() {
        var rng = FastRNG()
        var checked = 0
        for _ in 0..<5000 {
            let s = genStatementTop(&rng)
            if let r = prop_roundtrip_stat(s) { #expect(r == true, "\(s)"); checked += 1 }
        }
        #expect(checked > 4000)
    }
}
