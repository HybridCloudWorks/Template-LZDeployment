# Decision 0014 — Delivery authentication (App / PAT / interactive) and per-client template instantiation

- **Status**: **Accepted** — operator-decided 2026-08-15, as part of the
  generator-only refactor directive
  ([decision 0013](0013-generator-only-avm-architecture.md)). **Amends
  [decision 0004](0004-factory-copy-is-a-disposable-installer.md)** — it
  does not replace it.
- **Date**: 2026-08-15
- **Deciders**: operator (2026-08-15); recorded by `docs-knowledge-curator`
- **Technical depth**: L300 (environment variables, token mechanics, App
  permission sets)

## Context and Problem Statement

Decision 0004 ratified the execution model: the client runs the factory
copy on their own machine, and it is the client's own `gh` and `az`
sessions that create the estate. Delivery of the generated repository
(push-or-PR via `Publish-LzScaffoldRepository` in
`factory/scaffold/LZFactory.Scaffold.psm1`) therefore *assumed* an
interactive `gh` session. The refactor directive requires delivery to also
work non-interactively — automated or App-brokered runs where no human is
present to complete a device-code flow — without weakening the
least-privilege posture of the estate.

## Decision

Delivery authentication is established by `Initialize-LzDeliveryAuth`
(`factory/scaffold/LZFactory.Scaffold.psm1`), called at the top of
`Publish-LzScaffoldRepository`, in **preference order**:

1. **GitHub App installation token.** Set `LZ_GITHUB_APP_ID`,
   `LZ_GITHUB_APP_INSTALLATION_ID`, and
   `LZ_GITHUB_APP_PRIVATE_KEY_PATH`. A short-lived RS256 App JWT is minted
   **locally** (no key leaves the machine) and exchanged for an
   installation token, exported as `GH_TOKEN` so every subsequent `gh`
   invocation uses it. Required App permissions: **Contents RW, Pull
   requests RW, Metadata R** — plus **Administration RW only when the App
   must create the repository**.
2. **Fine-grained PAT.** Set `GH_TOKEN` (or `GITHUB_TOKEN`) to a
   fine-grained token carrying the same permissions; `gh` honors it
   natively.
3. **The operator's interactive `gh` session** — decision 0004's
   client-runs-it-locally model, fully supported as the fallback.

No path found means a hard failure with remediation guidance
(`docs/USER-CHECKLIST.md`), never a silent downgrade.

**What this amends in decision 0004, and what it does not.** The
disposable-installer model and client-local execution stay ratified
verbatim. What changes is one word of the old assumption: delivery no
longer **requires** an interactive session. An automated pipeline holding
App credentials (or a PAT) can now run render → validate → scaffold →
deliver end-to-end; a human at a keyboard remains equally supported.

**Per-client template instantiation.** Alongside the existing private-copy
mechanic ([decision 0001](0001-private-copy-over-public-fork.md) /
[decision 0007](0007-retire-client-copy-hardening.md)'s
`Initialize-ClientFork.ps1 -CreatePrivateCopy`), the factory may be
instantiated per client as a **GitHub template repository**:

```bash
gh repo create <client>-gen --template HybridCloudWorks/Template-LZDeployment
```

The operator marks `is_template` on the factory repository after the
refactor branch merges. Properties of template instantiation the operator
accepted: template copies carry the **default branch only**, produce
**unrelated histories** (no fork relationship), inherit **no settings or
secrets**, and do not carry LFS objects. None of these conflict with the
disposable-installer model — the instantiated copy is still deleted after
its one run.

## Consequences

- **Positive**: delivery works headlessly; the App path issues short-lived
  installation tokens instead of long-lived credentials, and the private
  key never transits the network; the permission floor is explicit and
  minimal, with repo-creation rights (Administration RW) required only
  when the App actually creates the repository.
- **Negative**: two more credential shapes to document and support
  (`docs/USER-CHECKLIST.md` owns the operator guidance); a mis-scoped PAT
  fails at delivery time rather than at configuration time — the error
  message names the required permissions.
- **Unchanged**: the copy mechanic remains the operator's indifference
  point ("forks (or clones, whatever is better)") — template
  instantiation is an *additional* option, and no tooling may depend on
  the copy being a fork, a template copy, or a clone.
- **Follow-ups**: marking `is_template` is an operator-local,
  post-merge repository setting, not automatable from the sandbox (same
  access shape as the Pages/branch-protection settings in
  [REVIEW.md](../../REVIEW.md)).
