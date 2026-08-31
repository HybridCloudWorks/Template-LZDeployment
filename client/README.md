# `client/` — where your answer record goes

Put the `lz-config.json` the wizard exports here, as `client/lz-config.json`,
and commit it.

## Why not the repository root

The root `lz-config.json` is gitignored, deliberately and permanently: it
carries tenant, subscription and identity identifiers, and this repository is a
template that people copy from. An ignore rule there is what stops a factory
developer's own tenant details reaching an upstream commit.

The ignore rule is anchored (`/lz-config.json`), so it matches the root file and
nothing else. `client/lz-config.json` is therefore committable without weakening
that protection — which is the whole reason for this directory.

## What committing it does

`.github/workflows/client-config-check.yml` renders the configuration and runs
the validation gates on every push and pull request that touches this file, and
posts the gate table back to the pull request.

That run holds **no credentials at all**. Render and validate shell only
`terraform`, `tflint` and a security scanner, and validation's
`terraform init -backend=false` is what keeps it authentication-free. It never
signs in to Azure and never reads your tenant. What it tells you is whether the
answers you have written would render and pass the gates — before anything
creates anything.

## What it does not do

It does not run discovery, the bootstrap broker, or scaffold. Those need Azure
and GitHub credentials, and you run them yourself, on your own machine, under
your own `az` and `gh` sessions:

```
./scripts/Invoke-CustomerEngagement.ps1 -ConfigPath ./client/lz-config.json -Phase all
```

That is not an oversight. It is the point: the sessions that create your estate
are ones you are sitting in front of, and the tenant-confirmation step in front
of them is the last chance to notice you are pointed at the wrong tenant.

It also could not be automatic even if that were wanted — the broker *creates*
the OIDC identities that later workflows federate with, so on the first run
there is nothing to authenticate as.

## Outputs

`client-rendered/` and `client-evidence/` are written at the repository root by
the phases above and are gitignored. They carry the same tenant detail the
answer record does. The workflow uploads them as a build artifact instead, with
a 30-day retention.
