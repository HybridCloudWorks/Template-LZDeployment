# Refactor gate 4 — Placeholder convention

## The convention: `{{FACTORY[-KIND]:dotted.path}}`

This factory's placeholder token is **not** `__UPPER_SNAKE__`. The refactor
directive proposed `__UPPER_SNAKE__` as a convention; the repository's existing
convention was ratified instead (operator direction 2026-08-15: improve what is
already better, do not remove it), because it is strictly stronger:

- **Typed.** `{{FACTORY:x}}` emits a quoted HCL string; `-RAW` unquoted;
  `-BOOL`, `-NUM` unquoted literals; `-LIST` `["a", "b"]`; `-MAP` an HCL map
  body; `-JSON` compact JSON. `__UPPER_SNAKE__` cannot express type, so every
  substitution site would re-implement quoting.
- **Safe inside HCL and YAML.** Conditionals are comment-prefixed
  (`#{{IF expr}}` / `#{{ELSE}}` / `#{{ENDIF}}` / `#{{FOREACH x IN list}}`), so
  an unrendered template is still valid HCL/YAML — `terraform fmt -check` runs
  against the raw corpus in Factory CI.
- **Collision-free with GitHub Actions.** The residual check's negative
  lookbehind excludes `${{ … }}`, so workflow templates keep their runtime
  expressions. `__UPPER_SNAKE__` has no such story for `__PYTHON_DUNDERS__`.

Authoritative definition: `factory/renderer/private/TokenEngine.ps1` (token
pattern, residual pattern, directive grammar, fail-closed rules).

## The gates (what the `__UPPER_SNAKE__` proposal was actually for)

The directive's *requirement* — no unfilled placeholder may survive into
output, enforced automatically — is met in three layers:

1. **Render-time residual check** (`Resolve-LzTemplate`): any surviving
   `{{…}}` after substitution throws — catches mistyped kinds like
   `{{FACTORY-LST:…}}`. An unknown path throws with a did-you-mean hint.
2. **CI grep gate** (`.github/workflows/terraform-policy-checks.yml`): rendered
   fixture output is grepped for both `__[A-Z0-9_]+__` **and** non-GHA `{{…}}`
   tokens; either match fails the build. The `__UPPER_SNAKE__` grep is kept in
   the gate so third-party content that uses that convention is caught too.
3. **End-to-end proof** (docs/refactor/VALIDATION.md, proof (a)): the same
   zero-placeholder grep over a real wizard-driven generation, output pasted.

## Operator-supplied placeholders

Values the wizard deliberately never collects are emitted as **commented
placeholders** that fail the first plan until filled (the pattern the corpus
uses for operator-network-range style secrets-adjacent values). These are
comments in valid HCL, not tokens, and are inventoried in COVERAGE.md.
