---
name: alterego-libs
description: Check or update AlterEgo vendored libraries for check libs or verificar libs and as the required library stage of update or implement PR.
---

# Vendored library version check

Run on `new-features` from the repository root. On the first run in a session, confirm `svn` is on `PATH` with `svn --version`; the checker also requires `git`. Use `python3` when available. If Windows has no `python3` on `PATH`, locate the Codex bundled Python runtime and use its absolute executable path with the same script and arguments; do not skip the check because of that alias.

1. Run `python3 scripts/check_lib_updates.py` without arguments. This is report-only and changes nothing. Its inputs are this branch's `.pkgmeta` and the committed `.pkgmeta-lock.json`.
2. If there are no pending updates, report that briefly in Portuguese and continue the parent workflow immediately. For a standalone check, finish without syncing or installing.
3. If any library is marked `[!]`, read [pending updates](references/pending-updates.md) before recommending or applying anything. Wait for explicit library choices. If a library is marked `[?]`, report that it could not be checked automatically, give its `.pkgmeta` URL for manual checking, and continue the rest of the workflow.
4. If the output flags directories under `Libs/` absent from `.pkgmeta`, mention them as informational. The checker does not check or update those directories. Never delete or change them automatically; they do not block the workflow.

Read [why libraries are vendored](references/vendoring.md) only when branch setup, ignored files, ZIP installation, or library ownership needs explanation. Never edit `.pkgmeta-lock.json` by hand.
