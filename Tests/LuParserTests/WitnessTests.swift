import Testing
import LuParser

// The 25 harvested witnesses (one per catchable mutant/property task) must each
// be a genuine witness: a *parsable* input that round-trips `true` on the clean
// implementation. (A non-parsable input would be discarded, not a counterexample;
// this guards the etna.toml task set against discard-only "witnesses".)

@Suite struct WitnessTests {
    @Test func every_witness_is_true_on_clean() throws {
        for w in harvestedWitnesses {
            let r = try evaluate(property: "roundtrip_\(w.kind)", input: w.wire)
            #expect(r == true, "\(w.mutant)/\(w.kind): expected Some(true) on clean, got \(String(describing: r))")
        }
    }

    @Test func witness_count_matches_task_set() {
        #expect(harvestedWitnesses.count == 25)
    }
}
