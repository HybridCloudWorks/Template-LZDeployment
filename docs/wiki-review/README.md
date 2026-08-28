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

**All three** patches are built against wiki HEAD `7286806`, and all three
must be applied, in the order below. Apply the 2026-08-06 patch first — it
adds per-page `HISTORICAL` banners to 11 source-material pages, which the
2026-08-27 `Home.md` section banner then complements; the 2026-08-28 patch
re-syncs the two repository mirrors last, over the reconciled pages.

These are plain `git` commands with no line continuations, so they run
unchanged in PowerShell, bash, or zsh. Run them from the directory that
*contains* your `Template-LZDeployment` checkout — the clone lands beside it,
which is what the `../` in each patch path assumes.

```shell
git clone https://github.com/HybridCloudWorks/Template-LZDeployment.wiki.git
cd Template-LZDeployment.wiki
git am ../Template-LZDeployment/docs/wiki-review/2026-08-06-historical-banners.patch
git am ../Template-LZDeployment/docs/wiki-review/2026-08-27-post-refactor-reconciliation.patch
git am ../Template-LZDeployment/docs/wiki-review/2026-08-28-mirror-resync.patch
git push
```

**Verified 2026-08-28**: all three patches were applied in this order against a
fresh clone of wiki HEAD and **all applied cleanly, no conflicts**. The
sequence above is tested, not assumed.

Alternatively, approve `add_repo` for the wiki in an interactive Claude
session and ask it to push. Tracked as REVIEW.md §15 until published.

---

# Third review — 2026-08-28, mirror re-sync

`Home.md` states that two documents "live in the repository because tests and
tools read them from disk (the wiki carries mirrors)". Those mirrors had
drifted badly:

| Page | Repository | Wiki (2026-08-01) |
| --- | --- | --- |
| Cross-Domain-Contracts | **371 lines** | 123 |
| User-Checklist | **355 lines** | 268 |

The contracts page was a third the size of the real one, missing the entire
post-refactor reconciliation.

**The sources were validated before syncing, not just copied.** That mattered:
`docs/CROSS-DOMAIN-CONTRACTS.md` was itself carrying a `STALE — pending
post-refactor reconciliation` banner and was **not fit to mirror**. It has been
reconciled in the repository first — every contract re-verified file by file:

- **#5, #8, #9 → VOID** — they coordinated `spoke-network`, `nsg-flow-logs`,
  `hub-network` and the `workloads-*` layers, all deleted by ADR 0013 and all
  confirmed absent.
- **#6 → SUPERSEDED** — its lock-file rule named paths that no longer exist;
  the corpus now commits no lock files at all (gitignored, verified zero).
- **#1, #3, #4 → corrected** — their file inventories named deleted paths
  (`scripts/New-BackendConfig.ps1`, `terraform/live/*`) and, in #1's case, a
  layer that never declared `org_prefix` while omitting one that does.
- **#2, #7 → verified unchanged.**

**Contracts were deliberately not renumbered.** They are cited *by number* in
`factory/bootstrap/LZFactory.Bootstrap.psm1`,
`scripts/Start-LandingZoneBootstrap.ps1`, and asserted in
`factory/tests/Test-Bootstrap.ps1`. Renumbering would silently break those
citations, so void entries keep their headings and are marked in place.

`docs/USER-CHECKLIST.md` validated clean: every `LZ_*` variable it instructs
the operator to set is read by real code, and the 12 `LZ_DOGFOOD_*` names that
match nothing are correctly fenced behind its ⛔ SUPERSEDED Stage 13 banner.

Each synced page carries a provenance header naming its source path, the
commit it was synced from, and the rule that **the repository wins** on any
disagreement.

Preserved as
[`2026-08-28-mirror-resync.patch`](2026-08-28-mirror-resync.patch)
(2 files).

## Publication re-probe — 2026-08-28 (fourth confirmation)

Re-run with the operator's refreshed session permissions. **Read is now fully
open; write is not.**

- A full (non-shallow) `git clone` of the wiki succeeds.
- `git push --dry-run origin HEAD:master` is refused by the git proxy:
  *"HybridCloudWorks/Template-LZDeployment.wiki is not in this session's
  authorized repository set … To fix, add the repository to the session's
  sources."*
- That fix was attempted. `add_repo` for
  `HybridCloudWorks/Template-LZDeployment.wiki` returns *"not found on
  github.com, or this session's GitHub credential doesn't have access to it"*,
  and re-attaching the parent repository with `access: push` does not extend
  to the wiki. **A GitHub wiki is not a first-class repository**, so it cannot
  be added to a session's sources at all — the route the error message
  suggests does not exist for wikis.

**Provenance defect found and fixed 2026-08-28.** Both mirror banners cited
`9c820b5` as the commit they were synced from. For `User-Checklist` that was
harmless — the file is byte-identical at that commit — but for
`Cross-Domain-Contracts` it was **wrong**: the file was 371 lines at `9c820b5`
and the mirrored content is the 228-line post-reconciliation version from
`f1d37c0` (#113). Since the banner's whole purpose is to let a reader check for
drift, citing the pre-reconciliation commit would have shown 143 lines of
phantom drift to anyone who followed it. Each banner now names the commit that
last changed *that* source: `f1d37c0` for the contracts doc, `1d96750` (#104)
for the checklist. Bodies are unchanged and verified byte-identical to the
repository sources.

**The patches were re-verified rather than assumed — using the command this
README actually documents.** All three were `git am`-ed in sequence onto a
fresh clone at the wiki's current `master` (`7286806`, 2026-08-01). All three
applied, in order, with no conflict and no rebase, producing **20 files
changed, +450/−169** and preserving each patch's authorship and commit
message. The "Publishing — apply in this order" block above is a straight
replay; nothing in it needs adjusting.

## Known remaining wiki debt (not in any patch)

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
