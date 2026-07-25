---
description: Read-only pre-merge review of the current branch's landing-zone changes
argument-hint: [optional: path or PR number to focus on]
---

Run a pre-merge review of the changes on this branch. Focus: $ARGUMENTS

Start by collecting the diff:

```
git status
git diff main...HEAD --stat
```

Then hand the review to the `lz-change-reviewer` agent with the changed file list.
It checks for destructive plan operations on shared scopes, credential and OIDC
regressions, unpinned actions, weakened policy or secret scanning, drift between
the frontend generator and Terraform root variables, and workflow YAML context
errors.

Report findings ranked most severe first, each with file, line, the defect in one
sentence, and the concrete failure scenario. Separate confirmed findings from
plausible ones. Do not fix anything unless I ask.
