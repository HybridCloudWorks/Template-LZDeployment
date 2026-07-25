# Renderer — Stages 5–6

Turns a validated `lz-config.json` plus the template corpus into a rendered
landing zone repository.

```powershell
Import-Module ./factory/renderer/LZFactory.Renderer.psd1

Invoke-LzRender -ConfigPath ./generated-output/contoso/lz-config.json `
                -OutputDirectory ./generated-output/contoso/repo
```

Output goes to a staging directory, never in place and never directly into a git
working tree. Moving a rendered tree into a repository is the scaffold builder's
job (stage 10) — keeping those separate means a failed render leaves nothing
half-written where a push could pick it up.

---

## Token syntax

Templates use `{{FACTORY:...}}`, **never** `${...}`. Terraform owns `${...}` for
its own interpolation; a factory token sharing that syntax would be ambiguous
inside every `.tf` file and would break `terraform fmt` on the raw template.

| Token | Renders | Example output |
|---|---|---|
| `{{FACTORY:path}}` | Quoted string | `"contoso"` |
| `{{FACTORY-RAW:path}}` | Verbatim, unquoted | `contoso` |
| `{{FACTORY-BOOL:path}}` | `true` / `false` | `true` |
| `{{FACTORY-NUM:path}}` | Numeric literal | `90` |
| `{{FACTORY-LIST:path}}` | HCL list | `["eastus", "westus"]` |
| `{{FACTORY-MAP:path}}` | HCL map body | `{ owner = "platform" }` |
| `{{FACTORY-JSON:path}}` | Compact JSON | `["eastus","westus"]` |

`path` is a dotted path into the configuration, or into the `computed.*`
namespace the renderer derives (see below).

### Why GitHub Actions expressions survive

`${{ github.ref }}` and friends pass through untouched — they are evaluated by
the Actions runner, not the factory. The residual-placeholder check uses a
negative lookbehind so `${{ ... }}` is never mistaken for a mistyped factory
token. The trade-off: a token mistyped as `${{FACTORY:x}}` is invisible to that
check. That is the correct direction — GitHub expressions are ubiquitous and
legitimate, while a leading `$` on a factory token is not a mistake anyone makes
by accident.

---

## Conditional directives

Directives are comment-prefixed, so an **unrendered** template is still valid
HCL, YAML, or Markdown. That is what lets factory CI run `terraform fmt -check`
and `terraform validate` against the raw corpus, catching a broken template
before any customer renders it.

```hcl
#{{IF connectivity.firewall.type == 'azfw'}}
azfw_tier = {{FACTORY:connectivity.firewall.azfwTier}}
#{{ELSEIF connectivity.firewall.type == 'palo'}}
primary_nva_trust_ip = {{FACTORY:connectivity.firewall.nvaTrustIpPrimary}}
#{{ELSE}}
# no firewall
#{{ENDIF}}

#{{FOREACH layer IN computed.layers}}
  - {{FACTORY-RAW:layer}}
#{{ENDFOREACH}}
```

`#`, `//`, and `<!--` prefixes are all recognised. Directives nest.

### Expression grammar

Deliberately tiny. A template language that grows an expression engine becomes a
program nobody reviews.

| Form | Meaning |
|---|---|
| `path` | Truthy test. **Throws** if the path is unknown. |
| `!path` | Negation |
| `defined path` | Existence test. Never throws. |
| `!defined path` | Absence test |
| `path == 'value'` | Equality |
| `path != 'value'` | Inequality |
| `path contains 'value'` | Array membership or substring |
| `a && b`, `a \|\| b` | Conjunction, disjunction |

**Use `defined` for optional keys.** An exported configuration *strips* optional
keys rather than emitting them empty, so a template asking "was an identity
subscription supplied?" must not fail merely because the answer is no. Use a bare
path everywhere else — a bare path keeps typos loud, which is what stops a
renamed config key from silently deleting a block of Terraform.

### Two passes, in order

Directives run **before** token substitution. A token inside a block the
conditional removes is never evaluated — otherwise a configuration that
legitimately omits, say, ExpressRoute settings would fail to render because of a
token in the excluded ExpressRoute block.

Loop bodies are the exception: their tokens are substituted *during* loop
expansion, with the loop variable in scope, because by the time the global pass
runs that variable no longer exists.

---

## Fail-closed

Every one of these is a hard error, not a warning:

- Unknown token path (with near-miss suggestions)
- Mistyped token kind — `{{FACTORY-LST:...}}`
- Any surviving `{{...}}` placeholder after rendering
- Unbalanced `IF` / `FOREACH`
- Malformed or unsupported expression
- A non-empty output directory without `-Force`

A renderer that emits an empty string for a token it does not recognise produces
Terraform that plans successfully and deploys the wrong thing — strictly worse
than not rendering at all.

---

## Render guards

`Test-LzRenderGuards` re-validates the configuration independently of the wizard,
because the renderer must be safe when driven by a hand-edited `lz-config.json`,
by CI, or by a config from an older factory version. A validation that exists
only in the UI is a suggestion, not a guarantee.

| ID | Blocks |
|---|---|
| G01 | Schema version the renderer does not implement |
| G02 | Sentinel enabled while `sentinel-siem` is scaffold-only |
| G03 | CMK enabled while `keyvault-cmk` is scaffold-only |
| G04 | `virtual-wan` — no such module exists |
| G05 | Self-hosted runners — not supported in v1 |
| G06 | A policy-required tag with no default value |
| G07 | A deployed region absent from `allowedLocations` |
| G08 | Allowed locations outside declared data residency |
| G09/G11 | A required subscription missing |
| G12 | Overlapping hub/spoke address spaces |
| G13 | Promotion path referencing an undeployed environment |
| G16 | Unknown token in a custom naming pattern |
| G17/G18 | Backend selected but not configured |
| G19 | Sentinel policy engine without the HCP backend |
| G20 | Internal visibility without Enterprise Cloud |

G10 and G14 are advisory warnings (missing sandbox subscription, prod without
reviewers) and do not block.

Scaffold-module guards read status from `factory-version.json` rather than a
hard-coded list, so implementing a module automatically lifts its guard.

---

## Schema drift detection

```powershell
Test-LzSchemaDrift -SchemaPath ./factory/schema/lz-config.schema.json `
                   -MappingPath ./factory/renderer/variable-map.json `
                   -TemplateRoot ./factory/templates
```

This is the mechanism that fixes the defect recorded in `TODO.md`, where the
static generator's 47 policy toggles were never reconciled against what
`policy-baseline` actually implements.

The failure it prevents is quiet: a wizard option with no corresponding Terraform
variable produces a `.tfvars` entry Terraform ignores. The operator sets
"enable X", the plan succeeds, and X is never deployed. Nothing reports a
problem, because from Terraform's point of view nothing is wrong.

Four checks:

| Kind | Catches |
|---|---|
| `OrphanedConfigKey` | Mapped config key → no such Terraform variable. The setting silently does nothing. |
| `UnknownConfigPath` | Terraform variable → no such schema path. |
| `UnmappedRequiredVariable` | Required variable nothing feeds. Apply prompts for input or fails in CI. |
| `ConstraintMismatch` | Schema accepts values Terraform's `validation` rejects. |

`ConstraintMismatch` reports a **concrete counterexample** rather than "these
regexes differ" — it turns an argument about regex equivalence into a fact you
can verify in one step. It found a real conflict during development: the schema
allowed a 10-character `companyShortName` while `org_prefix` validated
`^[a-z]{2,4}$`, so `contoso` would have passed the wizard and failed
`terraform plan`.

Regex equivalence is undecidable in general, so the check only analyses the
simple bounded-character-class shape `^[class]{min,max}$` — which is what
validation blocks overwhelmingly use.

---

## The `computed.*` namespace

Values derived once, centrally, so no template can invent its own:

| Path | Notes |
|---|---|
| `computed.layers` | Active layers. Drives per-layer rendering and the workflow matrix. |
| `computed.allEnvironments` | Platform + application environments |
| `computed.repositorySlug` | `owner/repo` |
| `computed.oidcSubjectPullRequest` | Plan-identity subject |
| `computed.oidcIssuer` / `computed.oidcAudience` | Federation constants |
| `computed.hasDrRegion` | Single- vs dual-region |
| `computed.generatedDate` | `generatedAt` truncated to `YYYY-MM-DD`, for variables that validate an ISO date |
| `computed.backupRedundancy` | `GeoRedundant` / `LocallyRedundant` — the config's boolean as the provider's enum |
| `computed.backendIsHcp` / `computed.backendIsAzurerm` | Backend branch |
| `computed.workspacePrefix` | HCP workspace naming |

If each template computed its own OIDC subject, one inconsistent template would
produce a federated credential that never matches — and a CI job that fails only
at the first apply.

---

## Manifest

`template-manifest.json` decides *what* is emitted and *when*. Inclusion lives
here rather than inside templates so each template file stays valid on its own.

```json
{
  "files": [
    { "source": "README.md.tmpl", "destination": "README.md", "mode": "render", "when": "always" },
    { "source": "…/variables.tf", "destination": "…/variables.tf", "mode": "copy" }
  ],
  "perLayerFiles": [
    { "source": "terraform/live/_layer/backend.tf.tmpl",
      "destination": "terraform/live/{{FACTORY-RAW:layer}}/backend.tf" }
  ],
  "directories": [
    { "source": "terraform/modules", "destination": "terraform/modules",
      "when": "always", "exclude": ["*/.terraform.lock.hcl"] }
  ]
}
```

- `mode: "copy"` emits verbatim. `variables.tf` **must** be copied, never
  templated — it is the contract the drift check validates against.
- `perLayerFiles` render once per active layer with `layer` bound.
- `directories` copy a whole tree verbatim. Use this only for content with no
  per-configuration variation: the module corpus is dozens of static files, and
  listing each one would add no decision while creating a trap where a newly
  added `.tf` is silently not shipped. Anything that *does* vary belongs in
  `files`, where its condition is visible. `exclude` patterns are matched
  against the path relative to `source`, with forward slashes.
- `when` uses the same expression grammar as directives.

---

## Formatting

After rendering, `terraform fmt -recursive` runs over the output.

This is not cosmetic. HCL alignment cannot be correct at template time:
conditionals change which lines exist, and `terraform fmt` aligns `=` across the
block that actually survives. The rendered output is the only place the final
line set is known. Without this step, every generated repository fails its own
`terraform fmt -check` on its first pull request.

Pass `-SkipFormat` to disable, or accept the warning when `terraform` is not on
PATH.

---

## Status

Stage 5 delivered the **engine**; stage 6 promoted the real Terraform into
`factory/templates/`. The corpus now emits five live layers — `global`,
`platform-connectivity`, `platform-management`, `workloads-prod`, `sandbox` —
plus `terraform/modules/**` and `terraform/scripts/` verbatim. Both a
dual-region HCP configuration and a single-region azurerm configuration render
to trees that pass `terraform fmt -check -recursive` and `terraform validate`.

Two layers `Get-LzActiveLayers` can select — `platform-identity` and
`workloads-nonprod` — have no Terraform anywhere in the repo, so there is
nothing to promote. Guard **G21** refuses to render a configuration that selects
one, reading the implemented-layer list from `factory-version.json`. Before that
guard, such a layer was emitted as a directory holding only `backend.tf`: it
initialised cleanly and planned zero resources, which reads as "nothing to do"
rather than "not implemented". `variable-map.json` keeps both in
`$pendingLayers` so the gap stays visible.

Stage 7 promotes `.github/workflows/` the same way.
