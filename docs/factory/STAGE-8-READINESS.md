# Stage 8 Completion — Generated Documentation Corpus

**Date:** 2026-07-26  
**Factory version:** 0.3.0  
**Config schema:** 2.0.0  
**Manifest version:** 1.3.0

## Scope

Stage 8 makes every rendered landing-zone repository self-documenting. It adds
nine always-emitted Markdown templates under `factory/templates/docs/`:

1. operating model;
2. governance;
3. threat model;
4. observability;
5. FinOps;
6. Terraform state management;
7. disaster recovery;
8. upgrade guide;
9. end-to-end phase model.

The existing identity trust matrix remains the authoritative generated identity
document.

## Design constraints

- Documents render from the validated `lz-config.json`; they do not invent
  organization-specific owners, RTO/RPO values, budgets, contacts, or approvals.
- Every generated document carries factory version and render provenance.
- Unknown paths and unresolved factory tokens remain hard renderer failures.
- Conditional backend and regional guidance follows the same context used by
  Terraform templates.
- Generated files tell operators to re-render rather than hand-edit.
- Stage 8 performs no tenant, repository-administration, backend, or Terraform
  mutation. Stage 9 remains the first external write boundary.

## Manifest contract

All nine documents are declared as `mode: render`, `when: always` entries in
`factory/renderer/template-manifest.json`. Destinations are stable lowercase
paths under the generated repository's `docs/` directory.

## Acceptance evidence

- All nine source templates exist and are registered.
- A representative dual-region HCP configuration emits all nine destinations.
- No emitted document contains unresolved `{{FACTORY...}}` tokens.
- Every document identifies generated provenance and factory version 0.3.0.
- Assertions verify platform ownership, allowed regions, exact PR OIDC subject,
  log retention, FinOps owner/cost center, HCP workspace contract, both recovery
  regions, schema version, and active layer order.
- Renderer suite: 175 passed, 0 failed.
- Wizard suite: 48 passed, 0 failed.
- Discovery suite: 60 passed, 0 failed.
- Total local baseline: 283 passed, 0 failed.

## Definition of done

- [x] Nine-document corpus authored.
- [x] Manifest version advanced to 1.3.0.
- [x] Factory and landing-zone versions advanced to 0.3.0.
- [x] Wizard and fixtures stamp factory version 0.3.0.
- [x] Generated repository README links every operational document.
- [x] Renderer inventory and semantic assertions added.
- [x] Handoff, design, renderer README, and changelog reconciled.
- [x] No Stage 9 external mutation performed.

## Next boundary

Stage 9 is the bootstrap broker. It consumes discovery output and is the first
stage authorized to reconcile Entra applications, federated credentials, GitHub
environments/secrets/settings, and backend prerequisites. Live Entra and
required-status-check verification remain tracked in `TODO.md`.

