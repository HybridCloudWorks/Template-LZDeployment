# Stage 9–14 User Checklist

The Stage 9 broker is implemented and merged as code only. No live Azure,
Entra, GitHub administration, or HCP Terraform mutation was executed while
building it.

The Stage 10 scaffold builder is also implemented as code only. No customer
repository was created, overwritten, committed, or pushed while building it.

The Stage 11 brownfield generator was implemented without running discovery,
Terraform, import commands, plans, or state operations.

The Stage 12 Factory CI workflow and runner were implemented without executing
the local validation corpus in this environment.

The Stage 13 HCW dogfood workflow and runner were implemented without executing
a render, Terraform plan/apply, Azure login, OIDC exchange, or state operation.

The Stage 14 release-readiness workflow and evaluator were implemented without
downloading or validating live evidence in this environment.

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

## Stage 11 brownfield variables

- [ ] Confirm `deploymentStrategy.mode` is `brownfield`.
- [ ] Export `LZ_DISCOVERY_PATH` with a fresh, conclusive, read-only
  `discovery-inventory.json`.
- [ ] Export `LZ_BROWNFIELD_CLASSIFICATIONS` with the operator-reviewed
  classification file.
- [ ] Export `LZ_RENDERED_PATH` with the renderer output that Stage 11 may
  augment and Stage 10 will subsequently scaffold.
- [ ] Export `LZ_IMPORT_EVIDENCE` to a protected evidence directory.
- [ ] Use `LZ_IMPORT_ALLOW_STALE=true` only with a documented owner-approved
  exception; the inventory SHA-256 pin is enforced by default.

## Stage 11 classify and generate

- [ ] Run `pwsh ./brownfield-import.ps1` without `-Apply`; it is plan-only and
  emits `brownfield-classifications.generated.json`,
  `brownfield-import-plan.json`, and `brownfield-import-audit.json`.
- [ ] Classify every resource as Adopt, Ignore, Replace, or Require-Approval.
  Missing entries inherit the configured default, which should remain Ignore.
- [ ] For every Adopt entry, provide and independently review the exact
  Terraform resource address and active layer. The generator never guesses an
  address.
- [ ] For every Replace or Require-Approval entry, provide an accountable
  `approvalReference`. Neither classification emits an import or deletion.
- [ ] Confirm all supported Azure probes are conclusive; Forbidden,
  Unavailable, and Error results must not be treated as empty.
- [ ] Review `brownfield-import-plan.json` and confirm
  `executesTerraformImport=false`.
- [ ] Set `LZ_IMPORT_APPLY=true`, then run `./brownfield-import.sh` or
  `pwsh ./brownfield-import.ps1 -Apply`. Apply only writes review artifacts and
  updates `render-manifest.json`; it does not touch Terraform state.
- [ ] Preserve the classification, plan, audit, discovery inventory, and
  updated renderer manifest as change evidence.
- [ ] Review every generated `imports.generated.tf` and
  `scripts/import-*.generated.sh` line against the approved resource ID,
  address, layer, and current state backup.
- [ ] Run a speculative plan and require zero unintended destroy/replace
  actions before approving adoption. Any destructive exception requires the
  repository's `approved-destroy` control and the recorded owner approval.
- [ ] Execute generated import commands only in an authenticated,
  change-controlled operator session; the factory never executes them.

## Stage 12 Factory CI variables

- [ ] Review repository variable `LZ_FACTORY_CI_OUTPUT`; the default evidence
  directory is `factory-ci-output`.
- [ ] Review `LZ_FACTORY_CI_FAIL_FAST`; default `false` records all failures
  before returning a failing status.
- [ ] Keep `LZ_FACTORY_CI_SKIP_TERRAFORM=false` and
  `LZ_FACTORY_CI_SKIP_STATIC=false` on protected branches. Temporary skips
  require a documented owner-approved exception.
- [ ] Review `LZ_FACTORY_CI_TERRAFORM_ROOTS`; default is
  `factory/templates/terraform`. Multiple roots are comma-separated.
- [ ] Review pinned `LZ_PSSCRIPTANALYZER_VERSION`; default is `1.24.0`.

## Stage 12 enable and verify

- [ ] Ensure GitHub Actions is enabled and allowed to use the SHA-pinned actions
  in `.github/workflows/factory-ci.yml`.
- [ ] Add the exact `Factory CI / Factory CI` context to required `main` status
  checks after its first successful run, retaining `qlty check`.
- [ ] Confirm the workflow has only `contents: read` permission and receives no
  Azure, GitHub administration, HCP, backend, or customer credentials.
- [ ] Review the uploaded `factory-ci-<run-id>` artifact and
  `factory-ci-report.json`; preserve it as release evidence.
- [ ] Confirm Wizard, Discovery, Renderer, Bootstrap, Scaffold, Import, and CI
  suites are represented in the report.
- [ ] Confirm schema-variable drift, site no-network, action pinning,
  ShellCheck, PSScriptAnalyzer, Terraform format, init-without-backend, and
  validate checks are represented.
- [ ] Resolve every failed check. Do not mark release gates true from an
  incomplete/skipped run.
- [ ] Read back branch protection/rulesets through the GitHub API and prove a
  pull request cannot merge when `Factory CI / Factory CI` fails.

## Stage 13 dogfood variables

- [ ] Store the complete approved HCW `lz-config.json` as repository variable
  `LZ_DOGFOOD_CONFIG_JSON`; confirm it targets
  `saulpatinojr/HCW-Plan_LZDeployment` and contains no token or client secret.
- [ ] Set repository variables `LZ_DOGFOOD_TENANT_ID`,
  `LZ_DOGFOOD_SUBSCRIPTION_ID`, and `LZ_DOGFOOD_PLAN_CLIENT_ID`.
- [ ] Set `LZ_DOGFOOD_TERRAFORM_VERSION`; default `1.9.8` must remain within
  the factory toolchain contract.
- [ ] Configure `AZURE_APPLY_CLIENT_ID` only on each protected apply
  environment. Keep the plan identity read-only and the apply identity bound
  only to its exact `environment:<name>` OIDC subject.
- [ ] For HCP Terraform only, configure `TF_API_TOKEN` as an environment secret
  from a secure source. Never store it in configuration or repository variables.
- [ ] For local operator execution, set `LZ_DOGFOOD_CONFIG_PATH`,
  `LZ_DOGFOOD_OUTPUT`, `LZ_DOGFOOD_EVIDENCE`, `LZ_DOGFOOD_MODE`,
  `LZ_DOGFOOD_LAYER`, and `LZ_DOGFOOD_REPOSITORY`.

## Stage 13 execute and verify

- [ ] Run `Dogfood Instance` in `Render` mode and review the generated manifest.
- [ ] Run every rendered layer in `Plan` mode with the read-only identity.
  Confirm all plans succeed and contain no unintended delete or replace.
- [ ] Review the exact apply identity, subscription routing, backend, protected
  environment reviewers, and rendered configuration before approval.
- [ ] Run each layer in dependency order through `Apply`. The workflow asserts
  `LZ_DOGFOOD_APPLY=true`, consumes its saved plan, and rejects deletes.
- [ ] Preserve every `dogfood-<run-id>-*` artifact and review
  `dogfood-report.json`, per-layer init/plan/show/apply logs, configuration
  SHA-256, and `releaseGateEligible`.
- [ ] Independently read back Azure resources, Terraform state/workspaces,
  federated credentials, exact OIDC subjects, GitHub environment protections,
  and required status checks.
- [ ] Set `dogfoodInstanceAppliesGreen=true` only in a separately reviewed PR
  after every rendered layer applies green and the read-back evidence is
  accepted. Do not infer this gate from code completion, render-only output,
  skipped layers, or plan success.

## Stage 14 release evidence variables

- [ ] Set repository variable `LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS`; default 168
  requires Factory CI, dogfood, and attestation evidence from the last seven
  days.
- [ ] Build `LZ_RELEASE_ATTESTATION_JSON` against
  `factory/release/release-attestation.schema.json`.
- [ ] Include the exact lowercase SHA-256 values of `factory-ci-report.json`
  and `dogfood-report.json`, the reviewer, approval reference, repository,
  factory version, issuance time, and every required read-back boolean.
- [ ] For local execution, set `LZ_RELEASE_FACTORY_CI_REPORT`,
  `LZ_RELEASE_DOGFOOD_REPORT`, `LZ_RELEASE_ATTESTATION_PATH`,
  `LZ_RELEASE_EVIDENCE`, and `LZ_RELEASE_EXPECTED_REPOSITORY`.
- [ ] Use `LZ_RELEASE_ALLOW_INCOMPLETE=true` only to generate diagnostic
  evidence. An incomplete report is never promotion approval.

## Stage 14 attest and promote

- [ ] Select a successful, unskipped Factory CI run for factory v0.9.0 and
  record its workflow run ID.
- [ ] Select a successful Stage 13 `Apply` run with layer `all`,
  `externalMutation=true`, and `releaseGateEligible=true`; record its run ID.
- [ ] Independently verify the complete dogfood deployment, live OIDC token
  exchange, active emitted modules, branch protection, and evidence ownership.
- [ ] Compute both report SHA-256 values before approving the attestation.
- [ ] Run `Release Readiness` with the two exact run IDs and review the retained
  `release-readiness-report.json` and `release-gates.proposed.json`.
- [ ] Require every R01–R10 finding, every proposed release gate, and
  `readyForPromotion` to pass. Skips, stale evidence, partial-layer applies,
  hash mismatches, or missing approvals fail closed.
- [ ] Open a separate pull request for any `factory-version.json` gate change.
  The Stage 14 evaluator never edits the release contract, creates a release,
  or declares v1.0.0.
- [ ] Require independent approval of the release-gate PR and preserve all
  source artifacts, hashes, attestation, and promotion reports.
