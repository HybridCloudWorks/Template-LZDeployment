# TODO - HCW Landing Zone Platform

> **File contract (operator-defined 2026-08-06).** This file holds only
> **completable engineering work** — items that can be picked up and finished
> from a clone of this repository without operator decisions, credentials, or
> external systems. Everything that is blocked on the operator (a decision, an
> access grant, tenant confirmation) or on an external system lives in
> **[REVIEW.md](REVIEW.md)**, the official root file of record for blocked
> work. Production-motion phases and their operator activities stay in
> [PROD-TODO.md](PROD-TODO.md). Completed work is recorded in
> [CHANGELOG.md](CHANGELOG.md).
>
> An item may only sit here if an engineer could start it right now. When an
> item acquires an operator-shaped blocker, move it to REVIEW.md rather than
> annotating it in place.

**Last Updated**: August 6, 2026
**Status**: 🟢 **NO OPEN ENGINEERING DEBT**
**Completed work**: [CHANGELOG.md](CHANGELOG.md)
**Blocked work (official record)**: [REVIEW.md](REVIEW.md)
**Production-motion backlog**: [PROD-TODO.md](PROD-TODO.md)
**External tracking**: [GitHub Issues](https://github.com/HybridCloudWorks/Template-LZDeployment/issues)

---

## 📋 What This Repo Is

This repo is the **Landing Zone Factory** (see [README.md](README.md)): it
renders a self-contained, per-customer landing-zone repository from
`lz-config.json`. The legacy self-deploying path (`terraform/live/` plus the
numbered workflows) is retained for compatibility and serves as the Stage 13
dogfood instance. The end-to-end customer motion is described in
[PROD-TODO.md](PROD-TODO.md).

1. **`site/`** — the 15-step offline wizard that exports `lz-config.json` and
   its derived artifacts.
2. **`bootstrap-broker.ps1` / `.sh`** — the Stage 9 non-interactive entry
   point. It consumes config/discovery artifacts, plans by default, and
   reconciles Entra, RBAC, GitHub, and backend prerequisites in apply mode.
   Operator activities are in [USER-CHECKLIST.md](USER-CHECKLIST.md).
3. **`validate-render.ps1` / `.sh`** — the post-render validation gate between
   the renderer and the scaffold (added 2026-08-06). It runs eight read-only
   gates (inventory integrity, fmt, init, validate, workflow pinning,
   provider constraints, lint, security scan) against the rendered tree and
   writes `validate-report.json`; scaffold apply refuses a missing, failed,
   or stale report. See
   [docs/decisions/0005-post-render-validation-gate.md](docs/decisions/0005-post-render-validation-gate.md).
4. **`scaffold-copy.ps1` / `.sh`** — the Stage 10 plan-first scaffold entry
   point. It verifies the exact renderer inventory and publishes the generated
   working tree only under explicit apply controls.
5. **`brownfield-import.ps1` / `.sh`** — the Stage 11 plan-first
   classification/import artifact generator. It never runs Terraform import.
6. **Numbered GitHub Actions workflows** (`.github/workflows/010-*.yml`,
   `020-*.yml`, ...) plus `terraform-plan.yml`/`terraform-apply.yml` deliver
   the legacy in-repo deployment against `terraform/`.
7. **`frontend/`** is a separate, optional static HTML/JS page (no backend) —
   the **legacy** generator; `site/` is the primary path. See
   [`frontend/README.md`](frontend/README.md).

---

## 🟢 Open engineering debt

**None.** As of 2026-08-06 every remaining piece of work is gated on an
operator decision, operator-held access, or an external system, and is
recorded — with its specific blocker, who can unblock it, and the next
concrete action — in **[REVIEW.md](REVIEW.md)**.

Consolidated out of this file on 2026-08-06 (their sole home is now REVIEW.md):

| Former TODO item | Now | Why it moved |
| --- | --- | --- |
| Wire `Configure-DeploymentOptions.ps1` into Terraform | REVIEW.md §16 | Ordered behind the `keyvault-cmk`/`sentinel-siem` scaffolds, an operator-accepted deferral |
| Wire `nsg-flow-logs` into a live stack | REVIEW.md §11 | Needs the operator's NSG-set and cost/data-residency choice |
| Resource-provider registration strategy (azurerm 5.0) | REVIEW.md §10 | Needs the operator to pick the mechanism; load-bearing since 5.0 is permanent |
| Disposition of `scripts/Initialize-ClientFork.ps1` | REVIEW.md §12 | Retire-vs-retarget is the operator's call on an operator entry point |
| Review the 11 docs migrated to the wiki | **Done 2026-08-06** | Content review complete — verdicts in [docs/wiki-review/](docs/wiki-review/README.md); only the wiki *push* remains blocked (REVIEW.md §15) |

The full history of items completed from this file — including the 2026-08-06
sweep (provider-constraint CI, enum drift detection, schema-default seeding,
azurerm 5.0 migration, module README enforcement, azurerm fixture coverage,
`workloads-nonprod` parity control, `moved.tf` disposition) — is in
[CHANGELOG.md](CHANGELOG.md).

---

## 📚 Key Documents

- **[REVIEW.md](REVIEW.md)** — **official root file of record** for everything
  blocked on the operator or an external system
- **[PROD-TODO.md](PROD-TODO.md)** — production-readiness backlog for the customer motion
- **[CHANGELOG.md](CHANGELOG.md)** — historical record of completed work
- **[docs/plans/](docs/plans/)** — analyses of record; **[docs/decisions/](docs/decisions/)** — decision records; **[docs/runbooks/](docs/runbooks/)** — operator procedures
- **[docs/wiki-review/](docs/wiki-review/README.md)** — 2026-08-06 wiki source-material review (verdicts + prepared banners)
- **[GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki)** — operator guidebook ("How to Get Started") and source material
- **[GitHub Issues](https://github.com/HybridCloudWorks/Template-LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
