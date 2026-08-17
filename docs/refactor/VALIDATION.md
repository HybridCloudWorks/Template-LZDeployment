# Refactor gate 7 — End-to-end validation and final report card

Executed 2026-08-15 on branch `claude/repo-alignment-review-5ita4y` (the
designated working branch for this refactor; the directive's
`refactor/generator-only` branch name was superseded by the session's assigned
branch). Harness: `factory/e2e/Invoke-E2EGenerationProof.ps1` +
`factory/e2e/drive-wizard.js`; CI equivalent:
`.github/workflows/e2e-generation-proof.yml` (both topologies, on runners with
Terraform Registry access).

## The generation was driven by the REAL UI — never hand-authored

`drive-wizard.js` loads `site/index.html` in headless Chromium, fills the form
through the DOM (real `input`/`change` events, so the wizard's own binding
layer writes the config), asserts the wizard's `validate()` reports zero
blocking errors and the Export button is enabled, then captures the wizard's
own `exportArtifacts()` pipeline — the same code path the Export button runs.

```
== Driving the wizard headlessly (hub-spoke) ==
  warn  observability: Platform health alerts are enabled but no action group recipients are configured, so alerts will fire into nothing.
  warn  finops: No budgets defined. Nothing will alert on cost overrun.
UI-driven export complete: 8 artifact(s) -> .../e2e-run/answers
  lz-config.json
  terraform.auto.tfvars
  connectivity.auto.tfvars
  backend.hcl
  environments.json
  deployment-metadata.json
  CONFIGURATION.md
  NEXT-STEPS.md
```

Notably, the first run of this proof **failed at render gate G00**: the real
UI exported `null` for untouched number inputs and empty strings for untouched
format-checked fields, which the schema rejects. That wizard export defect was
fixed (`buildConfig` feature-block stripping) — exactly the class of bug this
proof exists to catch, and evidence the proof is real.

## The six proofs (hub-and-spoke run; the virtual-wan run passes identically)

```
[PASS] zeroResidualPlaceholders — __UPPER_SNAKE__ hits: 0; factory-token hits: 0
[PASS] manifestMatch — V01 inventory-integrity: pass; generator files leaked: 0
[FAIL] terraformInitValidatePassed — V02 fmt: pass; V03 init: fail; V04 validate: fail — environment-limited: registry.terraform.io blocked by egress proxy; re-run where the registry is reachable
[PASS] workflowsPinnedWithIdToken — V05 pinning: pass; federating workflows: 3, all with id-token: True; credential-free workflows carrying a needless token: 0
[PASS] alzlibIgnoredNoState — .alzlib/ in .gitignore: True; state files: 0
[PASS] zeroGuids — distinct GUIDs: 4 (all synthetic driver identities); unexpected: 0
```

### (a) Zero unfilled placeholders — the strongest end-to-end proof

```
$ grep -rn '__[A-Z0-9_]\+__' .        # over the generated tree
exit=1 (no matches)
```

The factory-token sweep (`{{…}}` excluding GitHub's `${{ … }}`) also returns
zero. Both are additionally CI gates (terraform-policy-checks.yml).

### (b) Generated tree matches the output manifest exactly

Validation gate V01 inventory-integrity: **pass**. 42 files, byte-for-byte
the manifest's declared set — workflows (7), docs (10), three Terraform
layers × 6 files, `.gitignore`, `renovate.json`, `lz-config.json` answer
record, `factory-version.json` stamp, `README.md`, `USER-CHECKLIST.md`,
`render-manifest.json`. Zero generator machinery (no `factory/`, `site/`,
PowerShell modules, or node_modules anywhere in the output).

### (c) terraform fmt / init / validate — fmt proven here; init is CI's gate

```
$ terraform fmt -check -recursive .    # generated tree
fmt: clean (exit 0)
$ terraform init -backend=false        # each of the three layers
Error: Error accessing remote module registry
```

**UNRESOLVED (environment):** this sandbox's egress proxy returns HTTP 403
for `registry.terraform.io`, so module download cannot run here — a
limitation of the execution environment, not of the generated code (V02 fmt
and V06 provider-constraint gates pass; the failure text is purely the
registry connection). The proof is completed by
`.github/workflows/e2e-generation-proof.yml` and
`terraform-policy-checks.yml`, which run `terraform init -backend=false &&
terraform validate` per layer on GitHub-hosted runners with registry access —
this is also the execution-time re-verification of every AVM pin that the
pins table mandates. Operator-local equivalent:

```
pwsh ./factory/e2e/Invoke-E2EGenerationProof.ps1 -OutputDirectory ./e2e-output
```

### (d) Deploy workflows: 40-char SHA pins + `id-token: write`

Gate V05 workflow-pinning-policy: **pass** (every `uses:` matches
`@[0-9a-f]{40}`). All 3 federating workflows (plan, apply, auth-test) set
`permissions: id-token: write`; the 4 credential-free workflows carry no
token permission at all — least privilege in both directions.

### (e) `.alzlib/` gitignored; no state files

`.gitignore` contains `.alzlib/`; zero `*.tfstate*` / `*.tfplan` files exist
in the output.

### (f) GUID hygiene

The 4 distinct GUIDs in the generated tree are exactly the synthetic driver
identities (`11111111-2222-…` tenant, `aaaaaaaa-0000-…-01/02/03`
subscriptions) — the values typed into the wizard, which an estate's tfvars
must necessarily carry. No real tenant or subscription identifier exists in
the repository or its output (see GREP-FINDINGS.md for the repo-side sweep).

### Emitted pins (pasted from generated `main.tf` files)

```
source  = "Azure/avm-ptn-alz/azurerm"                              version = "0.21.0"
source  = "Azure/avm-ptn-alz-management/azurerm"                   version = "0.9.0"
source  = "Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm"  version = "0.17.3"
# virtual-wan run: Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm  version = "0.17.1"
```

`renovate.json` (terraform manager, terraform-module + terraform-provider
datasources) is in the output; pins update inside the generated repository
forever with no factory dependency.

## Test-suite state after the refactor

| Suite | Result |
| --- | --- |
| `factory/tests/Test-Renderer.ps1` | 100 passed, 0 failed |
| `factory/tests/Test-Bootstrap.ps1` | 85 passed, 0 failed |
| `factory/tests/Test-CI.ps1` | 12 passed, 0 failed |
| `factory/tests/test.js` (site harness) | 74 passed, 0 failed |
| Schema↔variable drift (`Test-LzSchemaDrift`) | InSync: true, 0 findings |
| Template coverage (`Test-TemplateCoverage.ps1`) | 37 sources, no orphans |

## FINAL REPORT CARD

The pre-refactor scorecard (2026-08-15 alignment audit), re-scored after the
refactor. "Was" is the audited state; "Now" is this branch.

| Requirement | Was | Now |
| --- | --- | --- |
| Repo A = website + tooling only, no terraform/ architecture | Not met | **Met** — `terraform/` deleted (11 modules, 5 layers, backend-bootstrap); self-deploy workflows deleted; state bootstrap lives in the broker |
| Emit root-modules referencing AVM by pinned registry source+version | Not met (inverse: vendored corpus) | **Met** — three layers, four pins, ALZ library `platform/alz @ 2026.04.2`; nothing vendored (proof above) |
| Q&A site asks all LZ questions | Met | **Met** — unchanged breadth; Virtual WAN now exportable; consumption classes recorded (COVERAGE.md, ADR 0017) |
| Machine-readable output manifest, fail-closed | Met (exceeded) | **Met, strengthened** — manifest 2.0.0 is the contract; new template-coverage CI check closes the orphaned-template gap |
| Placeholder coverage gate | Mostly met | **Met** — residual-token render gate + CI grep (both conventions) + bidirectional drift check; convention ratified in PLACEHOLDERS.md |
| Automated push-or-PR delivery | Met mechanically, wrong auth | **Met** — `Initialize-LzDeliveryAuth`: GitHub App installation token (preferred) → fine-grained PAT → interactive gh session |
| Repo B hardening | Met (ahead) | **Met, extended** — + `ref:refs/heads/<default-branch>` plan subjects, container-scope state RBAC |
| Workflows SHA-pinned + id-token | Met | **Met** — proof (d) |
| Workflows are thin callers | Not met | **Deliberately not adopted** — ADR 0016: thin callers would recreate the factory dependency the directive forbids; self-contained SHA-pinned workflows ratified |
| renovate.json in emitted output | Not met | **Met** — emitted, terraform manager, module+provider datasources |
| Answer record + version stamp committed to Repo B | Not met | **Met** — `lz-config.json` + `factory-version.json` are manifest-tracked emissions (modes config-snapshot / version-stamp) |
| Empty backend + per-layer backend.hcl, use_oidc | Not met | **Met** — proof (e) + backend.hcl with `use_oidc = true`, `use_azuread_auth = true` |
| `.gitignore` with `.alzlib/` | Not met | **Met** — proof (e) |
| No TFC remnants | Partially met | **Met** — render path, schema, wizard, tooling, fixtures all azurerm-only (ADR 0015); disposal keeps legacy-estate cleanup notes only |
| Template-repo instantiation | Not met | **Met (documented)** — ADR 0014; operator marks `is_template` post-merge (`gh api -X PATCH repos/HybridCloudWorks/Template-LZDeployment -F is_template=true`) |
| GUID hygiene | Met | **Met** — proof (f) |
| docs/refactor/ gate documents | Not met | **Met** — all seven present (CLASSIFICATION, GREP-FINDINGS, OUTPUT-CONTRACT, COVERAGE, PLACEHOLDERS, UI-SELFCONTAINMENT, VALIDATION) |

## UNRESOLVED (recorded, not guessed)

1. **AVM module input surfaces** for `avm-ptn-alz-management@0.9.0` and both
   connectivity modules at 0.17.x could not be verified against the registry
   from this environment (proxy 403). The composed inputs follow the modules'
   documented interfaces and are localized in each layer's `main.tf` locals;
   `terraform validate` in the e2e-generation-proof workflow is the
   authoritative execution-time check. If it reports an input mismatch, the
   fix is confined to the affected `main.tf.tmpl` locals block.
2. **`brownfield-import`** remains quarantined pending AVM re-targeting
   (CLASSIFICATION.md UNRESOLVED-2). **RESOLVED 2026-08-17:** removed under
   the exclude-and-create redefinition
   ([ADR 0018](../decisions/0018-brownfield-exclude-and-create.md)).
3. **State-bootstrap private-endpoint option**: the deleted
   `terraform/backend-bootstrap` supported an optional private endpoint for
   the state account; the broker's state reconciliation does not yet. Operator
   call whether to add it (CLASSIFICATION.md UNRESOLVED-1).
   **RESOLVED 2026-08-17:** WAF-validated day-0 posture + gated stage-2
   overlay ([ADR 0019](../decisions/0019-state-storage-hardening.md)).
