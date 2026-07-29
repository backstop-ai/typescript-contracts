#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
present="$root/testdata/fixtures/sig-kinds-present.ts"
mismatch="$root/testdata/fixtures/sig-kinds-mismatch.ts"

assert_match() {
  pattern=$(sh "$root/scripts/compile-signature.sh" "$1")
  matches=$(ast-grep run --json --pattern "$pattern" "$present")
  printf '%s' "$matches" | jq -e 'length == 1' >/dev/null
  sarif=$(printf '%s' "$matches" | sh "$root/ast-grep/to-sarif.sh")
  printf '%s' "$sarif" | jq -e '.version == "2.1.0" and (.runs[0].results | length) == 1' >/dev/null

  misses=$(ast-grep run --json --pattern "$pattern" "$mismatch" || true)
  printf '%s' "$misses" | jq -e 'length == 0' >/dev/null
}

assert_match 'function present(x: number): number'
assert_match 'type CheckType = unknown'
assert_match 'interface Stringer {}'
assert_match 'const CheckTypeFindings = unknown'
assert_match 'class Registry {}'

for supported in \
  'type X = string;' \
  'interface X { a: string; }' \
  'class X { a = 1; }'
do
  sh "$root/scripts/compile-signature.sh" "$supported" >/dev/null
done

service_pattern=$(sh "$root/scripts/compile-signature.sh" 'class Service extends unknown {}')
service_matches=$(ast-grep run --json --pattern "$service_pattern" "$root/testdata/fixtures/service-present.ts")
printf '%s' "$service_matches" | jq -e 'length == 1' >/dev/null

nested_pattern=$(sh "$root/scripts/compile-signature.sh" 'const Nested = { nested: { a: 1 } };')
[ "$nested_pattern" = 'const Nested = $$$' ]
nested_matches=$(ast-grep run --json --pattern "$nested_pattern" "$root/testdata/fixtures/const-object-present.ts")
printf '%s' "$nested_matches" | jq -e 'length == 1' >/dev/null

# Bare-const variable idiom (typescript-contracts#1): `const name // prose` — the RHS is
# prose-documented, not signature-checked (drizzle-table contracts in the wild). Compiles
# to the name-presence pattern and matches regardless of initializer. This REVERSES the
# earlier deliberate rejection of bare `const x` (it was an established consumer idiom);
# garbage after the name that is not a comment stays rejected below.
bare_pattern=$(sh "$root/scripts/compile-signature.sh" 'const CheckTypeFindings // prose-documented table, no initializer')
[ "$bare_pattern" = 'const CheckTypeFindings = $$$' ]
assert_match 'const CheckTypeFindings // prose-documented table, no initializer'

# Re-export alias idiom (typescript-contracts#1): `export { A as b } from "…"` is a
# legitimate contract surface (Next.js route-segment config MUST be a static re-export).
# The signature compiles to itself as an exact pattern; single quotes normalize to double.
reexport_pattern=$(sh "$root/scripts/compile-signature.sh" "export { SCHEDULED_MAX as maxDuration } from '../../reconcile/cron-route.js'")
[ "$reexport_pattern" = 'export { SCHEDULED_MAX as maxDuration } from "../../reconcile/cron-route.js"' ]

for unsupported in \
  'CheckType | Stringer' \
  'function broken(' \
  'const x garbage' \
  'const x = 1; const y = 2' \
  'const x=1;const y=2' \
  'const x = 1; garbage' \
  'const x = 1 garbage' \
  'type X = string garbage' \
  'function x(): number garbage' \
  'interface X {} interface Y {}' \
  'interface X {};interface Y {}' \
  'type X=string;type Y=number'
do
  if sh "$root/scripts/compile-signature.sh" "$unsupported" >/dev/null 2>&1; then
    printf '%s\n' "unsupported signature unexpectedly compiled: $unsupported" >&2
    exit 1
  fi
done

grep_output=$(grep -rn -e legacyProbeSymbol "$root/testdata/fixtures/absence-present.ts")
grep_sarif=$(printf '%s\n' "$grep_output" | sh "$root/grep/to-sarif.sh")
printf '%s' "$grep_sarif" | jq -e '.runs[0].results[0].ruleId == "contract-absence"' >/dev/null

printf '%s\n' "contract compiler and converter fixtures passed"
