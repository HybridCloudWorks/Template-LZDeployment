# Stage 9–10 User Checklist

The Stage 9 broker is implemented and merged as code only. No live Azure,
Entra, GitHub administration, or HCP Terraform mutation was executed while
building it.

The Stage 10 scaffold builder is also implemented as code only. No customer
repository was created, overwritten, committed, or pushed while building it.

## Required variables and authentication

- [ ] Export `LZ_CONFIG_PATH` with the path to the approved `lz-config.json`.
- [ ] Export `LZ_DISCOVERY_PATH` with the path to the matching
  `discovery-inventory.json`.
- [ ] Export `LZ_BOOTSTRAP_OUTPUT` to a protected local evidence directory.
- [ ] Authenticate Azure CLI to the configured tenant with app-registration,
  federated-credential, RBAC, and backend permissions.
- [ ] Authenticate GitHub CLI with repository administration, Actions,
  environments, variables/secrets, and branch-protection permissions.
- [ ] For HCP Terraform, export `TFE_TOKEN` from a secure secret source.
- [ ] Optionally export `LZ_REQUIRED_STATUS_CHECKS` as a comma-separated list;
  the default is `qlty check`.

## Review before mutation

- [ ] Resolve all blocking discovery findings. Use
  `LZ_BOOTSTRAP_ALLOW_NOT_READY=true` only with a documented owner-approved
  exception.
- [ ] Run `pwsh ./bootstrap-broker.ps1` without `-Apply` and review
  `bootstrap-plan.json`.
- [ ] Confirm every plan identity is Reader-only.
- [ ] Confirm workload apply identities are Contributor-only at their declared
  subscription scopes and the bootstrap apply identity has only the required
  management-group/policy roles at the configured root.
- [ ] Confirm subjects are exactly `pull_request` or
  `environment:<environment>` and contain no wildcard.
- [ ] Confirm backend names, HCP organization/workspace prefix, environments,
  and branch-protection settings.

## Apply and verify

- [ ] Set `LZ_BOOTSTRAP_APPLY=true` and run `./bootstrap-broker.sh`, or run
  `pwsh ./bootstrap-broker.ps1 -Apply`.
- [ ] Preserve `bootstrap-plan.json` and `bootstrap-audit.json`.
- [ ] Read back Entra applications, service principals, federated credentials,
  RBAC assignments, GitHub environments/variables/secrets, branch protection,
  and backend resources/workspaces.
- [ ] Run the generated Azure OIDC verification workflow from a real pull
  request and confirm token exchange with the Reader plan identity.
- [ ] Confirm apply identities can be assumed only through their matching
  protected GitHub environments.
- [ ] Confirm required `main` checks and protection through GitHub API
  read-back.
- [ ] Resolve every `pendingUserActivities` entry in `bootstrap-audit.json`.

## Never store

- Azure or GitHub user tokens.
- `TFE_TOKEN`.
- Client secrets.
- Storage account keys.

## Stage 10 scaffold variables

- [ ] Export `LZ_RENDERED_PATH` with the reviewed renderer output directory.
- [ ] Export `LZ_SCAFFOLD_TARGET` with the separate local target working-tree
  path.
- [ ] Export `LZ_SCAFFOLD_EVIDENCE` to a protected evidence directory outside
  the target tree.
- [ ] Set `LZ_SCAFFOLD_CREATE_REPOSITORY=false` when the repository must
  already exist.
- [ ] Set `LZ_SCAFFOLD_PUSH=false` when the operator wants a local commit but
  no remote publication.
- [ ] Optionally set `LZ_SCAFFOLD_REMOTE_URL` and
  `LZ_SCAFFOLD_COMMIT_MESSAGE`; otherwise the config-derived HTTPS URL and
  versioned commit message are used. Set `LZ_SCAFFOLD_BRANCH` to override the
  update PR branch.

## Stage 10 review and publication

- [ ] Run `pwsh ./scaffold-copy.ps1` without `-Apply`; it is plan-only by
  default.
- [ ] Review `scaffold-plan.json`, including repository slug, visibility,
  branch, manifest SHA-256, exact file inventory, and remote URL.
- [ ] Confirm the rendered tree contains exactly the files declared by
  `render-manifest.json`, with no untracked additions.
- [ ] Confirm `LZ_SCAFFOLD_TARGET` is disposable or backed up. A non-empty
  target is refused unless `LZ_SCAFFOLD_FORCE=true`; forced replacement retains
  a timestamped sibling backup and records it in `scaffold-audit.json`.
- [ ] When the remote repository already exists, use a clean clone with its
  configured default branch checked out as `LZ_SCAFFOLD_TARGET`; updates are
  pushed to `LZ_SCAFFOLD_BRANCH` and opened as a draft PR.
- [ ] Authenticate GitHub CLI with permission to create the configured private
  or internal repository and push its default branch.
- [ ] Set `LZ_SCAFFOLD_APPLY=true` and run `./scaffold-copy.sh`, or run
  `pwsh ./scaffold-copy.ps1 -Apply`.
- [ ] Preserve `scaffold-plan.json`, `scaffold-audit.json`, and any
  `*.lz-backup-*` directory until the generated repository is accepted.
- [ ] Read back the remote default branch and compare every managed file and
  commit SHA with `scaffold-audit.json`.
- [ ] For an existing repository, review, mark ready, and merge the draft
  scaffold PR using the repository's protected-branch requirements.
- [ ] Open and approve the generated repository's first pull request checks
  before any landing-zone apply.
