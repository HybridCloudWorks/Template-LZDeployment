# Stage 9 User Checklist

The Stage 9 broker is implemented and merged as code only. No live Azure,
Entra, GitHub administration, or HCP Terraform mutation was executed while
building it.

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
