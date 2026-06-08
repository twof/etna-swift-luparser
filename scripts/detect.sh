#!/bin/bash
# Reproduce mutant detection via ETNA's source-swap model: for each mutant,
# activate the marauder variant, rebuild, and run every round-trip property,
# printing (mutant/property -> status, counterexample). Used both to confirm
# detection and to harvest witnesses for the catchable (mutant, property) tasks.
#   ./scripts/detect.sh [duration_seconds]   (default 8)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUR="${1:-8}"
export MARAUDER_CONFIG="${MARAUDER_CONFIG:-$ROOT/marauder.toml}"

reset() { etna mutation reset -p "$ROOT" >/dev/null 2>&1 || true; }
build() { "$ROOT/scripts/swift-toolchain.sh" build >/dev/null 2>&1; }
run()   { "$ROOT/scripts/run-luparser.sh" ptk "$1" "$DUR" 2>/dev/null | tail -1; }
field() { echo "$1" | sed -E "s/.*\"$2\":(\"?[^\"]*\"?).*/\1/" | sed -E 's/^"|"$//g'; }

trap reset EXIT

PROPS="roundtrip_val roundtrip_exp roundtrip_stat"

echo "# clean baselines (a mutant is only genuinely detected where clean passes)"
reset; build
for prop in $PROPS; do echo "clean / $prop -> $(field "$(run "$prop")" status)"; done

echo "# mutants"
for mut in wsP_1 stringP_1 boolValP_1 stringValP_1 stringValP_2 stringValP_3 stringValP_4 \
           bofP_1 nameP_2 statementP_1 ppNot_1; do
  reset; etna mutation set "$mut" -p "$ROOT" >/dev/null 2>&1; build
  for prop in $PROPS; do
    line=$(run "$prop")
    st=$(echo "$line" | sed -E 's/.*"status":"([^"]*)".*/\1/')
    cex=$(echo "$line" | sed -E 's/.*"counterexample":(null|"([^"]*)").*/\2/')
    printf "%-14s / %-15s -> %-8s cex=%s\n" "$mut" "$prop" "$st" "$cex"
  done
done
