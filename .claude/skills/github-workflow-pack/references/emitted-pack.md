# Emitted pack — the workflows every generated client repo receives

Eight templates in `factory/templates/.github/workflows/*.tmpl`, rendered by
manifest entries in `factory/renderer/template-manifest.json`. Seven are
unconditional; `state-access-flip` renders only when
`backend.azurerm.privateEndpoint.enabled` is true (ADR 0019). All are
**self-contained** (decision 0016): no reusable-workflow references, nothing
pointing back at the factory.

| Template | Triggers | Identity | Purpose |
| --- | --- | --- | --- |
| `terraform-plan.yml.tmpl` | PR | **Plan** identity per layer (`vars.AZURE_PLAN_CLIENT_IDS` / `AZURE_SUBSCRIPTION_IDS` JSON maps, keyed by layer) | Matrix plan over `computed.layers`, `max-parallel: 1` (ARM throttling); destroy-count gate fails a plan containing deletes; uploads the plan artifact and comments the PR |
| `terraform-apply.yml.tmpl` | **dispatch-only** | **Apply** identity via protected environment (`vars.AZURE_APPLY_CLIENT_ID` at environment scope) | Environment + layer inputs; rejects unknown layers; enforces the layer→environment binding (broker's `Get-LzLayerEnvironment` mapping, duplicated in-shell **before** any credential is issued); checks out the trusted default branch by ref; re-plans, refuses destructive applies, applies the reviewed plan |
| `terraform-fmt-validate.yml.tmpl` | PR | **none — credential-free** | fmt + validate; deliberately carries no `id-token` (e2e gate (d) fails it in either direction) |
| `azure-auth-test.yml.tmpl` | dispatch | Plan identity | Proves the OIDC token exchange works before anything depends on it |
| `action-pinning-policy.yml.tmpl` | PR + push | none | The client repo's own copy of the pinning gate |
| `security-scan.yml.tmpl` | PR + push + schedule | none | Client-side secret/security scanning |
| `policy-diff-guardrails.yml.tmpl` | PR | none | Fails plans that weaken the policy baseline |
| `state-access-flip.yml.tmpl` (conditional) | dispatch-only, `runs-on: self-hosted`, `environment: management` | Apply identity | ADR 0019 stage-2: flips state-account public access after the state-hardening layer applies. Type-the-account-name confirmation; requires an Approved private endpoint before `disable-public`; verifies data-plane reachability after; `enable-public` kept as reviewed break-glass |

## The layer→environment contract

The apply workflow's in-shell `case` mapping, the broker's
`Get-LzLayerEnvironment`, and `Get-LzActiveLayers` (renderer) must agree.
Adding a layer means touching all three **plus** `factory-version.json`
`landingZone.layers` (guard G21) — this is a cross-domain contract; never
change one side alone. Current mapping:

| Layer | Environment |
| --- | --- |
| `global` | `bootstrap` |
| `platform-connectivity` | `connectivity` |
| `platform-management` | `management` |
| `state-hardening` | `management` |
| `platform-identity` | `identity` |
| `workloads-prod` | `prod` |
| `sandbox` | `sandbox` |
| `workloads-nonprod` | first of `dev`/`test`/`uat` |

## Template mechanics

- Config values enter via renderer tokens (`{{FACTORY:…}}`,
  `{{FACTORY-RAW:…}}`, `#{{FOREACH lyr IN computed.layers}}`), resolved at
  render time. Never hand-substitute a client value into a template.
- Terraform version renders from
  `{{FACTORY-RAW:computed.terraformVersion}}` — bump it in
  `factory-version.json`, not per-file.
- Every template needs its `template-manifest.json` entry; conditional ones
  carry a `when:` expression (tiny grammar in `TokenEngine.ps1`
  `Test-LzExpression` — bare paths throw on unknown keys by design).
- Backend init is always `terraform init -backend-config=backend.hcl`
  (azurerm-only, ADR 0015); auth is OIDC + `use_azuread_auth` — no state
  keys anywhere.
- The generated repo's hardening (branch protection, environments,
  reviewers, variables) is created by the broker with API read-back —
  workflows can assume it exists.
