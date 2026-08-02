# frontend/ — Legacy .tfvars generator

A single static page (`index.html` + `app.js` + `styles.css`) that turns a form
into Terraform variable files for this repository's **legacy in-repo pipeline**
(`terraform/live/*` deployed by the numbered GitHub Actions workflows). No
backend, no build step, no framework, and **zero network requests** — the CSP
in `index.html` (`default-src 'none'`) enforces that; everything runs in the
browser and downloads are in-memory `data:` URIs.

## Relationship to `site/` (read this first)

**`site/` is the primary path.** The Landing Zone Factory wizard
(`site/index.html`) collects the full configuration (subscription IDs,
identity, environments, backend, budgets), validates it against
`factory/schema/lz-config.schema.json`, and exports eight artifacts including
`lz-config.json` — the contract the whole factory pipeline (discovery →
bootstrap → render → scaffold) is driven by.

This page predates the factory and feeds **only** the legacy self-deploy
pipeline: the `terraform/live/*` stacks committed in this repository. It emits
two `.tfvars` files and nothing else. If you are onboarding a customer, use the
wizard; use this page only when working the legacy stacks directly.

## Usage: fill form → download → place files

1. Open the page: either `frontend/index.html` directly from disk in any
   modern browser (local checkout), or `/frontend/` on the published GitHub
   Pages site (see "Hosting" below). Both flows are supported.
2. Fill the form. Controls that no Terraform stack consumes are disabled and
   badged (see "What is emitted" below); they exist to record roadmap intent.
3. Click **Generate .tfvars files**, review the preview, then
   **Download both .tfvars files**. Two files land in your download folder:

   | File | Copy to | Consumed by |
   | --- | --- | --- |
   | `terraform.auto.tfvars` | `terraform/live/global/` | `terraform/live/global/variables.tf` |
   | `connectivity.auto.tfvars` | `terraform/live/platform-connectivity/` | `terraform/live/platform-connectivity/variables.tf` |

   `*.auto.tfvars` files are loaded automatically by `terraform plan`/`apply`
   in the stack directory they sit in — no `-var-file` flag needed.
4. Fill the commented placeholders before the first plan:
   - **Subscription IDs** (both files) — this page does not collect them.
   - **`management_ip_ranges`** (connectivity) — required; the plan fails until
     set, and `*`/`0.0.0.0/0` are rejected. Deliberately never collected by any
     generator (see `factory/renderer/variable-map.json` and contract #4 in
     `.claude/CROSS-DOMAIN-CONTRACTS.md`).
   - **`log_analytics_workspace_id`** (connectivity) — fill **after** the
     platform-management layer applies, then re-plan connectivity so firewall
     diagnostics and threat-intel alerts are created.
5. The spoke CIDR you enter is emitted only as a **comment**: copy it by hand
   into the `terraform/live/workloads-prod` tfvars as
   `primary_spoke_address_space`.

## What is emitted (and what deliberately is not)

The generated files contain **only** variables declared in the two
`variables.tf` files above. Reconciled 2026-08-02 against
`terraform/modules/policy-baseline/` and every `terraform/live/*` stack:

- **Emitted**: `org_prefix`, `allowed_locations`; `primary_region`/`_code`,
  `dr_region`/`_code`, `primary_hub_address_space`, `firewall_type`,
  `azfw_tier`, `deploy_bastion`, `deploy_dns`, `default_tags`.
- **Enforced policy is not configurable**: `policy-baseline` deploys its
  definitions unconditionally (required tags, allowed locations, NSG audit,
  TLS 1.2 initiative, sandbox guardrails). There is no per-policy variable, so
  the page emits no policy map.
- **Roadmap only, never emitted**: the 44 official ALZ catalog assignments
  shown disabled in section 4 — no policy definition exists for them in
  `terraform/modules/policy-baseline/`.
- **Available, not auto-deployed**: Microsoft Defender for Cloud — the
  `defender-baseline` module is implemented but no `terraform/live` layer
  calls it. Enabling it is a deliberate follow-up in Terraform, not a form
  toggle.
- **No wiring exists**: DDoS Protection, VNet gateways, AMA, AMBA, custom
  management group names, custom resource naming — no variable or module input
  consumes these, so the controls are disabled and nothing is emitted.

## Hosting

`.github/workflows/deploy-pages.yml` publishes one GitHub Pages artifact with
`site/` at the root and this page as a sibling subdirectory:

| Page | Published URL | Local checkout path |
| --- | --- | --- |
| Landing Zone Factory wizard (primary) | `https://<owner>.github.io/<repo>/` | `site/index.html` |
| This legacy generator | `https://<owner>.github.io/<repo>/frontend/` | `frontend/index.html` |

Opening `frontend/index.html` from a local clone remains fully supported.
Because the wizard sits at a different relative path in the two layouts
(`../index.html` when published, `../site/index.html` on disk), the
"Landing Zone Factory wizard" links on this page default to the published
target and are rewritten to `../site/index.html` at load time when the page
is opened over the `file:` protocol. With JavaScript disabled the links
resolve correctly only on the published site — from a local checkout, open
`site/index.html` directly.
