---
description: Root-cause a failing deployment, workflow run, or Terraform error
argument-hint: [the error, run URL, or what broke]
---

Diagnose this failure: **$ARGUMENTS**

Use the `deployment-troubleshooter` agent. Method:

1. Read `TODO.md` first — the pipeline has catalogued reliability issues and this
   may already be one of them.
2. Get the **actual** error text: the workflow run log (`gh run view --log-failed`),
   the Terraform plan/apply output, or the `az` error body. Quote it. Do not
   diagnose from a summary.
3. Locate the boundary — bootstrap, init, plan, apply, or post-apply in Azure.
4. Confirm the cause down to a specific line, permission, or resource. Label what
   you confirmed versus what remains a hypothesis.
5. Check for collateral: partial applies, orphaned resources, a held state lock,
   half-configured GitHub environments.
6. Recommend the fix and name the specialist who should implement it.

Investigate read-only. Do not rerun an apply, force-unlock state, remove anything
from state, or delete a resource — show me the command and I will run it.
