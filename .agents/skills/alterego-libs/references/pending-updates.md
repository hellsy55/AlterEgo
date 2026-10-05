# Pending library updates

Load this reference only when the report-only checker shows `[!]`.

For each pending library, inspect its actual upstream changes before recommending an action. Prefer release notes or a changelog; compare relevant source changes if those are unavailable. Report in plain Portuguese the current version from the checker's `current` field, the newly found version, and the practical relevance for AlterEgo: bug fix, compatibility or security fix, new behavior, breaking change, or no meaningful change. Mention uncertainty where safety cannot be confirmed.

For standalone `check libs` and `update`, offer in Portuguese:

a) Update all pending libraries now.
b) Choose libraries one by one.
c) Skip library updates this time and continue the normal workflow.

Mark exactly one option with the lowercase Portuguese word for "recommended" in parentheses, explaining the reason in plain language. Recommend all only when every pending update is clearly appropriate; recommend per-library selection when relevance or risk differs; recommend skipping when no update is relevant or safety cannot be confirmed. Do not apply anything before an explicit choice.

For `implement PR`, preserve its narrower checkpoint before PR analysis: offer (a) update now or (b) leave libraries as they are, then wait. If the user chooses updating, identify the approved libraries; do not assume that every pending library was approved unless the user explicitly chooses all.

For each approved library, run `<PYTHON> scripts/check_lib_updates.py --apply <short-name>`. Use `--apply all` only when all pending libraries were approved. Use the retained preflight runtime. A failed export/clone/checkout/copy exits nonzero and leaves the previous lockfile unchanged; an apply with unresolved upstream lookups also stops before vendoring. Stop the action and inspect any partial library files before retrying or committing. The script updates `Libs/<name>` and rewrites `.pkgmeta-lock.json`; never edit the lockfile manually. Run and show `git diff --stat` before preparing a commit. Use one commit per selected library, or one combined commit for a batch approved as all. An English imperative subject can use the pattern `Libs (chore): update AceDB-3.0 to Release-r1400`.

Before each commit, inspect the staged list and show the user that list, a concise staged stat, and the complete staged diff; wait for explicit approval immediately before committing. After the approved commit, run `git push origin new-features`. Continue the parent workflow only after the update, skip, or no-pending result is settled.

For `[?]`, give the library URL from `.pkgmeta` and keep going. Remote resolution failures, especially at `repos.wowace.com`, may reflect a slow or stale service rather than a local setup problem. For directories absent from `.pkgmeta`, only report their names and that the checker neither checks nor updates them.
