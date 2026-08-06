# Wiki source-material review — 2026-08-06

Completes the TODO.md item open since the 2026-08-01 migration: the 11
single-purpose documents moved from `docs/` to the wiki, filed under "Source
Material", had never been content-reviewed against the current repository.

**Method**: each page's load-bearing claims were checked against the repo at
`main` (post-#70). The decisive facts: the repository contains **no React, no
Node.js backend, no Bicep, no MSAL, and no CSV output** — the shipped system is
the Terraform-only Landing Zone Factory (`site/` wizard → discovery → broker →
renderer → scaffold), with `frontend/` retained as the legacy generator.

## Verdicts

| Wiki page | Verdict | Decisive evidence |
| --- | --- | --- |
| `Build-README` | **Historical — never executed as written** | Plans a React + Node.js webapp with Bicep, "Phase 0 NOT STARTED"; none of it exists |
| `Build-Critical-Path` | **Historical** | Timeline/gates for that same June 2026 initiative, superseded by the factory conversion |
| `Build-Standards-Reference` | **Partially historical** | Terraform/AVM half still usable; every Bicep section inapplicable (repo is Terraform-only, azurerm `~> 5.0`) |
| `Build-Verification-Report` | **Historical snapshot** | 2026-06-30 assessment of a TODO structure that no longer exists |
| `Deployment-Flow` | **Superseded** | "65% implemented, backend missing" — the backend was deliberately never built; the factory replaced the model |
| `Expanded-Scope` | **Historical / ancestry** | Describes `frontend/` scope growth; `site/` is primary (`frontend/README.md`) |
| `Fix-Login-Error` | **Obsolete** | The MSAL code it patched was later removed entirely; `frontend/` has no auth code at all |
| `Quick-Start` | **Historical / ancestry** | Quick start for `frontend/`; the current path is `site/index.html` |
| `Static-Generator-Design` | **Stale premise** | Specifies CSV output; the generator emits `.tfvars` and always has in shipped form |
| `Static-Generator-Implementation` | **Historical / ancestry** | Build guide for `frontend/` as originally constructed |
| `Testing-Static-Generator` | **Historical / ancestry** | Manual test guide for `frontend/`; `site/` has an automated suite (`factory/tests/test.js`) |

**Index mislabel found**: the wiki `Home.md` filed the Build set as
"(reference)" and the generator set as "(reference; …)". "Reference" implies
reliability; the content is planning history. Both section labels are
corrected to "(historical …)" in the prepared commit.

## Publication status

The wiki edits — a `HISTORICAL — reviewed 2026-08-06` banner on each of the 11
pages plus the `Home.md` relabels — are **authored and committed locally but
not yet pushed**: the git proxy injects credentials only for repositories in
this session's authorized set, `Template-LZDeployment.wiki` is not in it, and
adding it (`add_repo`) requires interactive approval unavailable to an
autonomous session.

The complete change is preserved here as
[`2026-08-06-historical-banners.patch`](2026-08-06-historical-banners.patch)
(12 files, +25/−3). To publish, either:

```bash
git clone https://github.com/HybridCloudWorks/Template-LZDeployment.wiki.git
cd Template-LZDeployment.wiki
git am ../path/to/2026-08-06-historical-banners.patch
git push
```

or approve `add_repo` for the wiki in an interactive Claude session and ask it
to push. Tracked as REVIEW.md item 15 until published.
