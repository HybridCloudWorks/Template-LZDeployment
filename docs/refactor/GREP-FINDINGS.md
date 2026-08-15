# Refactor gate 2 — Grep sweep findings

Whole-tree sweep (excluding `.git/` and the vendored third-party `.claude/skills/`
content), run 2026-08-15 on `claude/repo-alignment-review-5ita4y`. Each class lists
total hits, what they actually are, and the disposition in this refactor. Raw hit
lists were generated with the exact patterns from the refactor prompt.

## 1. GUIDs — 80 hits, zero real tenant/subscription identifiers

Pattern: `[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`
(lock files excluded — they contain only provider hashes).

| Class | Hits | Representative citations | Disposition |
| --- | --- | --- | --- |
| Synthetic test fixtures (`11111111-2222-…`, `aaaaaaaa-0000-…`) | 41 (`factory/tests/`) | `factory/tests/fixtures/sample-config.json`, `Test-Bootstrap.ps1:187-535`, `test.js:23-29` | Keep — deliberately fake, documented as such. |
| Placeholder zeros (`00000000-0000-…`) | 15 | `terraform/live/global/terraform.tfvars.example:7-12`, `frontend/app.js:429-433`, `site/index.html:106` | Live-tree copies deleted with `terraform/` (Phase 3); UI placeholders keep. |
| Azure built-in policy/role definition IDs | 10 | `terraform/modules/policy-baseline/main.tf:56,71` (Allowed-locations built-ins), Contributor `b24988ac-…` in `factory/bootstrap/LZFactory.Bootstrap.psm1:392` | Policy built-ins vanish with the bespoke policy module (ALZ library replaces them). Role-definition GUIDs in the broker are Azure well-known constants — keep. |
| PowerShell module manifest GUIDs | 2 | `factory/renderer/LZFactory.Renderer.psd1:4`, `factory/discovery/LZFactory.Discovery.psd1:4` | Keep — module identity, not tenant data. |
| Docstring examples | 2 | `scripts/Add-PlanFederatedCredential.ps1:70` | Keep. |

**Gate verdict: PASS today** — no real tenant/subscription GUID exists in Repo A.
The Phase 9 proof re-runs this sweep over *generated output*.

## 2. Example names — `contoso` 131 hits, `hcw`/`hybridcloudworks` 60 hits

- All `contoso` hits are UI `placeholder=` attributes (`site/index.html`, ~17), schema
  examples (`factory/schema/lz-config.schema.json:108`), docstrings, and test fixtures.
  None are config values. **Keep** — example values in a generator's own UI/docs are
  the correct place for them; the Phase 9 proof asserts none survive into output.
- `hcw`/`HybridCloudWorks` hits are docs/changelog history, the org name of this
  repository itself, and **one real default**: `org_prefix = "hcw"` at
  `terraform/backend-bootstrap/variables.tf:9` — an actual footgun (an unset run names
  real resources `sthcwtfstate…`). **Deleted with the backend-bootstrap tree** (Phase 3).
  The broker's state-bootstrap replacement takes the prefix from `lz-config.json` with
  no default.

## 3. Terraform Cloud remnants — 191 hits, the render path is the live problem

Decision 0011 (2026-08-15) already standardized the *live tree* on azurerm and fixed
workflow `010`. What remains, and what this refactor does with it:

| Location | What | Disposition |
| --- | --- | --- |
| `factory/templates/terraform/live/_layer/backend.tf.tmpl:14-21` | Emits a literal `cloud {}` block when `computed.backendIsHcp` | **Removed** (Phase 2 rebuilds the backend template azurerm-only: empty block + `backend.hcl`). |
| `factory/templates/.github/workflows/terraform-plan.yml.tmpl:131-133`, `terraform-apply.yml.tmpl:98-100` | Emit `cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}` under HCP conditional | **Removed** (Phase 2/4). |
| `factory/schema/lz-config.schema.json:248` | `"enum": ["hcp-terraform", "azurerm"]` | **azurerm-only** (Phase 4). |
| `factory/renderer/private/TokenEngine.ps1:139-142` | `computed.backendIsHcp` | **Removed**; replaced by topology computeds (Phase 2). |
| `factory/renderer/public/Test-LzRenderGuards.ps1:344-364` | HCP org guard; Sentinel engine requires `hcp-terraform` | **Removed/reworked** (Phase 4). |
| `factory/discovery/public/Get-LzTerraformInventory.ps1:166,198` | `app.terraform.io` default hostname | **Removed** (Phase 4). |
| `factory/bootstrap/LZFactory.Bootstrap.psm1:58-60,927` | `TFE_TOKEN` check; `Set-LzHcpBackend` | **Removed** (Phase 4). |
| `factory/tests/fixtures/sample-config.json` (+ tests pinned to it) | Canonical fixture is `hcp-terraform` | **Rebuilt azurerm-only** (Phase 4). |
| `site/index.html:287`, `site/app.js` (21 hits) | Wizard backend step offers HCP branch | **Removed** — backend step becomes azurerm-only (Phase 6). |
| `.github/workflows/dogfood-instance.yml:121,177` | `TF_API_TOKEN` secrets passthrough | **Deleted with the workflow** (Phase 3). |
| `scripts/Start-LandingZoneBootstrap.ps1:408-429,1531-1611` | Interactive TFC setup phase (incl. `app.terraform.io` at `:1579`) | **Removed** (Phase 4). |
| `scripts/Dispose-Engagement.ps1:35,271,389,430` | TFC residue cleanup | Cleanup of *legacy* engagements' secrets is intentionally retained for one release (disposal must handle estates generated before this refactor); annotated as legacy-only (Phase 4). |
| `docs/decisions/0011-…`, `CHANGELOG.md`, `REVIEW.md`, `TODO.md` | Historical record | Keep — history is not a remnant. ADR 0015 supersedes 0011's render-path scope-out. |
| `terraform/modules/sandbox/README.md:156,255,271` | "State versioned in Terraform Cloud" prose | Deleted with the module tree (Phase 3). |

`backend "remote"` — **0 hits** anywhere.

## 4. Hardcoded state storage / resource-group names — 74 hits

- `rg-tfstate-scus-prod-01` hardcoded in all five `terraform/live/*/backend.hcl:1` and
  mirrored docs — **deleted with the live tree**; the emitted `backend.hcl` template
  takes every value from the answer record.
- `<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>` placeholders (5) — same disposition.
- Composed names `stflowlogs…` in `terraform/live/platform-connectivity/main.tf:285,325`
  and `modules/nsg-flow-logs/main.tf:87` — deleted with the bespoke corpus.
- Remaining hits are docs/changelog history and test expectations — rebuilt or kept as
  history accordingly.

## 5. Stale documentation contradicting current state

Found during the sweep; fixed in Phase 8:

- `README.md:248` still says the bootloader and workflow `010` assume Terraform Cloud
  (fixed by decision 0011 before this refactor; statement is stale).
- `README.md:261` says "migrating to Terraform Cloud" — the direction that no longer
  exists.
- `factory-version.json:2` claims the stamp file "is written into the generated
  repository root by scaffold-copy" — false before this refactor, true after Phase 2.
