---
name: alterego-implement-pr
description: Evaluate, apply, port, or implement a DennisRas/AlterEgo GitHub PR into new-features after the required library check and user decision.
---

# Implement an upstream PR

Use for an upstream PR URL accompanied by a request to implement, apply, port, or evaluate it. Work on `new-features`.

1. First read and run [the library skill](../alterego-libs/SKILL.md). If updates are pending, use its PR-specific update-or-leave-as-is checkpoint and wait for the user's choice before PR analysis.
2. Confirm the URL names a PR in `DennisRas/AlterEgo`. If it belongs to another repository, stop and ask before doing anything else.
3. Fetch the diff first with `gh pr diff <url>`. Fetch full raw file contents only when the diff does not establish the practical effect, such as logic split across untouched sections, renamed symbols, or dependencies on other functions. Compare against the current `new-features` branch.
4. Before applying anything, explain in plain Portuguese what the fork gains, what existing behavior or customization it loses, and what remains unchanged. For an actual Git merge conflict, use [merge conflicts](../alterego-update/references/merge-conflicts.md): practical explanation first, marked code second, then options and a user choice. For a large change without a technical conflict, offer apply as-is, apply with adaptation, skip that part, or apply nothing. For a smaller change, ask whether to apply or skip it. Wait for explicit confirmation of the chosen option. Do not treat a reviewer result as permission.
5. Apply only the chosen change. Commit with an English imperative subject and body, without AI signatures, and reference the PR number and source in the body. Before committing, follow the root `AGENTS.md` staged-list, staged-stat, complete-staged-diff, and explicit-approval checkpoint. Push the result to `new-features`.
6. After the commit, offer the same install menu as a regular update. Read [the install skill](../alterego-install/SKILL.md) if the user chooses installation.

Report the verified PR and install outcome in Portuguese. If a required choice remains, report the task as pending.
