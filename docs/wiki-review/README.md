# Wiki source-material review — 2026-08-06

Completes the backlog item open since the 2026-08-01 migration: the 11
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
(12 files, +25/−3).

---

# Second review — 2026-08-27, post-refactor reconciliation

**Re-probed 2026-08-27: the push block is unchanged.** A fresh clone of the
wiki succeeds (read works anonymously); `git push --dry-run` is refused by
the git proxy — *"HybridCloudWorks/Template-LZDeployment.wiki is not in this
session's authorized repository set, so the proxy will not inject a
credential for it."* Third confirmation, now across three separate sessions.
Publication remains a local run of the commands below.

**What this review found.** The wiki's last commit is **2026-08-01**, so it
predates the 2026-08-15 generator-only refactor
([ADR 0013](../decisions/0013-generator-only-avm-architecture.md)) and
everything after it. **30 of 61 pages** name `terraform/live/*`,
`terraform/modules/*`, the numbered workflows, or the Stage 13 dogfood —
all deleted. Two problems were worth fixing at the source rather than
banner-only:

- **14 links across 10 pages pointed at the wrong repository**
  (`saulpatinojr/HCW-Plan_LZDeployment`), and two named files that have
  since moved or been retired (`USER-CHECKLIST.md` → `docs/USER-CHECKLIST.md`;
  `PROD-TODO.md` → `TODO.md`). Dead links on the wiki's own landing page.
- **`Getting-Started`, the live operator guidebook, described a fork-first
  motion performed by a third-party consultancy.** Both premises are wrong:
  the copy need not be a fork ([decision 0004](../decisions/0004-factory-copy-is-a-disposable-installer.md)),
  and there is no intermediary — the operator runs it on their own machine
  ([decision 0010](../decisions/0010-generated-repo-ownership-policy.md)).
  This is the most load-bearing page in the wiki and it was misdescribing
  step 1.

Preserved as
[`2026-08-27-post-refactor-reconciliation.patch`](2026-08-27-post-refactor-reconciliation.patch)
(10 files, +43/−19).

## Publishing — apply in this order

Both patches are built against wiki HEAD `7286806`. Apply the 2026-08-06
patch first — it adds per-page `HISTORICAL` banners to 11 source-material
pages, which the 2026-08-27 `Home.md` section banner then complements.

```bash
git clone https://github.com/HybridCloudWorks/Template-LZDeployment.wiki.git
cd Template-LZDeployment.wiki
git am ../path/to/2026-08-06-historical-banners.patch
git am ../path/to/2026-08-27-post-refactor-reconciliation.patch
git push
```

**Verified 2026-08-27**: both patches were applied in this order against a
fresh clone of wiki HEAD and **both applied cleanly, no conflicts** — the
resulting `Home.md` carries the section banner. The sequence above is tested,
not assumed.

Alternatively, approve `add_repo` for the wiki in an interactive Claude
session and ask it to push. Tracked as REVIEW.md §15 until published.

## Known remaining wiki debt (not in either patch)

- **Per-page banners on the ~19 source-material pages** the 2026-08-06 patch
  does not cover. The 2026-08-27 `Home.md` section banner governs them from
  the index, which is why they were not duplicated per page — but a reader
  arriving at a deep link bypasses the index.
- **`Bootstrap-Walkthrough` and `Generate-and-Deploy`** (guidebook pages 3
  and 4) have not been re-verified line-by-line against the post-refactor
  motion. Their links are fixed; their procedures are not audited.
- **The Factory-Stage-11/12/13/14 readiness pages** describe stages whose
  artifacts were deleted or replaced (Stage 11 brownfield import removed by
  ADR 0018; Stage 13 dogfood replaced by the end-to-end generation proof).
