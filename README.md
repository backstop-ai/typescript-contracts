# backstop/contracts for TypeScript

TypeScript implementation of Backstop's contract-signature and forbidden-symbol
capability. The pack compiles one declared TypeScript declaration into an
ast-grep pattern and converts structural or textual matches to SARIF.

Supported signature forms are one `function`, `type`, `interface`, `const`, or
`class` declaration per `provides` entry. Grouped symbol lists and namespace
projections are rejected rather than silently interpreted as source patterns.

## Verification

```sh
backstop pack check .
backstop pack test .
sh scripts/test-contracts.sh
```
