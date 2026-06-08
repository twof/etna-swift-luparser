import Testing
import LuParser
import LuParserGen
import PropertyTestingKit

// The bespoke generator must produce parsable ASTs (its whole reason for
// existing) and the wire (de)serialization must round-trip.

@Suite struct GeneratorTests {

    @Test func generated_inputs_are_parsable() {
        var rng = FastRNG()
        var discards = 0
        for _ in 0..<6000 {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: if prop_roundtrip_val(genValueTop(&rng)) == nil { discards += 1 }
            case 1: if prop_roundtrip_exp(genExpTop(&rng)) == nil { discards += 1 }
            default: if prop_roundtrip_stat(genStatementTop(&rng)) == nil { discards += 1 }
            }
        }
        // The generator is designed to satisfy the precondition by construction;
        // discards should be negligible.
        #expect(discards < 60, "too many discards: \(discards)/6000")
    }

    @Test func wire_roundtrips_for_generated_values() throws {
        var rng = FastRNG()
        for _ in 0..<2000 {
            let v = genValueTop(&rng)
            #expect(try decodeValue(parseSExpr(encodeValue(v))) == v)
        }
    }

    @Test func wire_roundtrips_for_generated_expressions() throws {
        var rng = FastRNG()
        for _ in 0..<2000 {
            let e = genExpTop(&rng)
            #expect(try decodeExpr(parseSExpr(encodeExpr(e))) == e)
        }
    }

    @Test func wire_roundtrips_for_generated_statements() throws {
        var rng = FastRNG()
        for _ in 0..<2000 {
            let s = genStatementTop(&rng)
            #expect(try decodeStatement(parseSExpr(encodeStatement(s))) == s)
        }
    }

    @Test func wire_handles_special_string_payloads() throws {
        // base64-prefixed atoms must survive spaces, parens, empties, and the
        // operator-spelling characters that appear in Lu source.
        let strs = ["", "a b c", "(){}[]", "// % .. >= <=", "_under 0 1", "tab\there"]
        for s in strs {
            let v = Value.StringVal(s)
            #expect(try decodeValue(parseSExpr(encodeValue(v))) == v, "\(s)")
        }
    }
}
