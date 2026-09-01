# Decision 0027 — `[]` is the encoding for "no compliance frameworks", and `"none"` is deprecated

- **Status**: **Accepted** — plan-approved 2026-08-31, choosing to keep the
  `"none"` enum member for now and queue its removal for the next schema major,
  over narrowing the enum immediately as a 5.0.0.
- **Date**: 2026-08-31
- **Deciders**: operator (keep the enum member, record the deprecation, fold the
  default correction into the unreleased 4.1.0 rather than bumping again)
- **Technical depth**: L200 (JSON Schema contract, renderer default seeding,
  schema versioning)

## Context and Problem Statement

`governance.complianceFrameworks` declared `"default": ["none"]`. Every consumer
already assumed `[]`:

- `site/app.js` `defaultConfig()` initialises it to `[]`, and it is bound as a
  checkbox group over `COMPLIANCE_FRAMEWORKS` — **seven** entries, `"none"` not
  among them. The wizard cannot produce the schema's own declared default, and a
  loaded config carrying `["none"]` renders as *all boxes unchecked*, so the
  first click silently drops it.
- `estimateRum()` costs the list as `.length * policyPerFramework` (12). So
  `["none"]` billed twelve phantom managed resources for having chosen *no*
  framework — and that estimate is not cosmetic, it gates the HCP Terraform
  500-resource free-tier export block.
- The generated `CONFIGURATION.md` renders the array literally and only takes its
  `_none declared_` branch when the array is empty, so `["none"]` would have put
  the bare token `none` into the frameworks list of a delivered document.
- All eight `factory/tests/fixtures/*-config.json` carry `[]`.

The default is not inert. `Add-LzSchemaDefault`
(`factory/renderer/private/TokenEngine.ps1`, called from `New-LzRenderContext`)
reads `default` out of the schema at render time and seeds any path the config
omits. It seeds only when the key is absent, so an explicit `[]` always wins —
which is exactly why every fixture masked the defect and no CI stage caught it.

Underneath the wrong default sits a second question the fix forces: if `[]` is
how "no frameworks" is expressed, then `["none"]` and `[]` are **two encodings of
one state**, and `uniqueItems` does not stop a config saying `["none", "soc2"]`.

### Why neither existing checker sees this class

`Test-LzSchemaDrift` catches enum drift by set-diffing schema enums against the
Terraform `contains([...], var.<name>)` validation lists — that is how the
identical `connectivity.firewall.type = "none"` sentinel was found and narrowed
out (`CHANGELOG.md`). It cannot see this key, because **no Terraform variable
exists for it**. `Test-SchemaCoverage.ps1` is satisfied by the single
`cfg.governance.complianceFrameworks` mention in `site/app.js`, so the path
counts as "consumed" and never lands in `recordedNotDeployed`.

## Decision

**`[]` is the canonical and only intended encoding for "no compliance frameworks
declared".** The schema default is corrected from `["none"]` to `[]`.

**`"none"` stays in `items.enum` for now, deprecated.** It is retained for input
tolerance only: nothing in the factory emits it, and the schema description now
says so and says not to write it.

*Narrow the enum now instead.* Rejected. Per
[decision 0022](0022-management-group-names-not-shape.md) and
[decision 0025](0025-schema-4-caf-minimal-real-and-policy-baseline-retired.md),
narrowing an enum is a schema **major**. Decision 0025 landed two breaking
changes together specifically so "a client migrating does it once"; issuing a
5.0.0 directly behind an unreleased 4.1.0, to delete a sentinel no wizard can
emit, is the back-to-back major that argument rules out. **The removal is queued
for the next schema major** and tracked at TODO 6.12 — deferred deliberately, not
forgotten.

*Add a conditional constraint forbidding `"none"` alongside a real framework.*
Rejected. It would suppress `["none", "soc2"]` without retiring the second
encoding, buying conditional-schema complexity for a key nothing consumes.

**No version bump.** The correction folds into the **unreleased** 4.1.0 rather
than taking a 4.2.0 of its own. 4.1.0 landed in #128 but has not shipped —
`factory-version.json` is `factoryVersion 0.11.0` / `status: pre-release` with
every release gate still false — so no client has ever seen a `4.1.0` schema and
there is no version boundary to migrate across.
`schemaVersion.const`, `site/app.js`'s `SCHEMA_VERSION` and
`factory-version.json`'s `configSchemaVersion` all stay at `4.1.0`; the running
changelog in the `schemaVersion` description carries the correction under its
4.1.0 entry.

## Consequences

- **No rendered output changes.** Every fixture states the key explicitly, so
  `Add-LzSchemaDefault` never seeded it; and no template, no Terraform variable
  and no policy assignment reads the path. The change is visible only to a
  hand-authored config that omits the key, which now seeds `[]` instead of
  `["none"]`.
- **The wizard/schema default gate now covers the whole contract.** Test section
  22 carried exactly one exception, `governance.complianceFrameworks`. That
  exception and its filtering are deleted rather than emptied — an allowlist left
  in place is a schema defect made permanent. The walk compares 75 declared
  defaults with zero drift.
- **A config carrying `["none"]` still validates**, and will keep validating
  until the next major. It is wrong, and both the schema description and the
  wizard's own behaviour say so, but it is not refused.
- **`"none"` is now on a clock.** The next schema major must drop it from
  `items.enum`. Because guard **G01** compares `schemaVersion` by exact equality,
  every version bump already forces a re-export from the wizard, and the wizard's
  seven-item list cannot produce `"none"` — so that removal costs a client
  nothing beyond the re-export the bump demands anyway.

## What this does not do

- **It does not make the answer deploy anything.** The key remains
  documentation-only under
  [decision 0017](0017-wizard-scope-vs-emitted-architecture.md). The schema
  description previously claimed it "drives which built-in Azure Policy
  initiatives are assigned"; that was never true, and the description is
  corrected here to say what the key actually reaches.
- **It does not close the checker gap that hid the defect.** A sentinel in an
  enum with no Terraform variable behind it is still invisible to
  `Test-LzSchemaDrift`, and still counts as "consumed" for
  `Test-SchemaCoverage.ps1` on the strength of one `site/app.js` mention. Section
  22 now gates *declared defaults* against the wizard, which is what would have
  caught this one; it does not gate enum membership.
- **It does not touch the other two `"none"` sentinels.** `connectivity.model`
  and `finops.chargebackModel` are scalar enums, not arrays, so neither carries
  the two-encodings-for-one-state ambiguity that motivated this record.
