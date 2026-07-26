# Stage 10 Completion — Scaffold Builder

**Date:** 2026-07-26
**Factory version:** 0.5.0
**Config schema:** 2.0.0
**Manifest version:** 1.5.0

## Scope

Stage 10 implements the scaffold plane that promotes an approved renderer output
into a real Git working tree and, under explicit apply control, creates or
updates the configured GitHub repository.

The builder:

- consumes `lz-config.json` and `render-manifest.json`;
- verifies the rendered tree contains exactly the declared destinations;
- rejects absolute, traversal, and duplicate manifest destinations;
- hashes every managed file and the renderer manifest with SHA-256;
- emits `scaffold-plan.json` and `scaffold-audit.json`;
- plans by default and never prompts;
- refuses a non-empty target unless force was explicitly approved;
- stages the complete tree before replacing a target;
- preserves `.git` metadata and a timestamped sibling backup on forced updates;
- verifies an existing `origin` matches the configured repository;
- creates the configured private/internal repository when allowed;
- creates a versioned commit and optionally pushes the configured default
  branch for a new repository;
- pushes an update branch and opens a draft PR when the repository already
  exists, preserving protected-default-branch semantics.

## Entry points and variables

- `scaffold-copy.ps1` — canonical PowerShell entry point.
- `scaffold-copy.sh` — strict Bash launcher.
- `factory/scaffold/LZFactory.Scaffold.psm1` — inventory, plan, copy, and
  publication functions.
- `LZ_CONFIG_PATH`, `LZ_RENDERED_PATH`, `LZ_SCAFFOLD_TARGET`, and
  `LZ_SCAFFOLD_EVIDENCE` — input/output paths.
- `LZ_SCAFFOLD_APPLY` and `LZ_SCAFFOLD_FORCE` — explicit mutation controls.
- `LZ_SCAFFOLD_CREATE_REPOSITORY` and `LZ_SCAFFOLD_PUSH` — remote behavior.
- `LZ_SCAFFOLD_REMOTE_URL` and `LZ_SCAFFOLD_COMMIT_MESSAGE` — publication
  overrides.
- `LZ_SCAFFOLD_BRANCH` — existing-repository update branch override.

## Safety model

Plan-only is the default. Apply is requested only with `-Apply` or
`LZ_SCAFFOLD_APPLY=true`. The rendered tree and target may not be equal or
contain one another. Existing remote URLs are never silently changed. A
non-empty target cannot be replaced without explicit force, and a forced update
retains a timestamped backup for operator recovery.

The manifest is the managed-file contract. Extra or missing rendered files stop
the scaffold before filesystem or GitHub mutation. Publication uses the
repository slug, visibility, and default branch from the validated config.

## User-owned activities

Authentication, target approval, force approval, backup retention, remote
read-back, and first-PR acceptance are recorded in root and generated
`USER-CHECKLIST.md`. Missing user activity did not block Stage 10 code creation
or publication of the factory implementation.

## Validation status

Executable validation was intentionally skipped at the repository owner's
direction because the implementation environment was declared not to contain
the required binaries. The scaffold test file was authored but not executed.
No customer target directory or GitHub repository was created, overwritten,
committed, or pushed.

The last verified executable baseline remains Stage 8:

- Wizard: 48 passed.
- Discovery: 60 passed.
- Renderer: 175 passed.
- Total: 283 passed.

Static source review and remote Git blob comparison are publication-integrity
checks, not claims that the Stage 10 runtime executed successfully.

## Definition of done

- [x] Non-interactive, plan-only scaffold entry points implemented.
- [x] Exact renderer inventory verification implemented.
- [x] Safe target and explicit force controls implemented.
- [x] Staged copy, Git preservation, and recovery backup implemented.
- [x] Config-derived repository create/commit/push implemented.
- [x] Plan and audit evidence implemented.
- [x] Factory and generated user checklists updated.
- [x] Static scaffold coverage authored.
- [x] Version, manifest, handoff, architecture, README, TODO, and changelog
  reconciled.
- [x] Executable validation skipped and documented without claiming success.

## Next boundary

Stage 11 is brownfield import generation. It consumes discovery classifications
and emits deterministic import blocks only for explicitly adopted resources.
Live Stage 9 broker apply and Stage 10 customer-repository publication remain
operator activities in `USER-CHECKLIST.md`.
