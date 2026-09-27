# One-time repository setup

Use this reference only when setup is incomplete. The fork remote `origin` must point to `https://github.com/hellsy55/AlterEgo.git`; `upstream` must point to `https://github.com/DennisRas/AlterEgo.git`. Add the latter with `git remote add upstream https://github.com/DennisRas/AlterEgo.git` if absent, then verify both with `git remote -v`.

If `new-features` does not exist, create it once from the fork default branch:

```text
git checkout main
git pull --ff-only origin main
git checkout -b new-features
git push -u origin new-features
```

On `new-features`, ensure `scripts/check_lib_updates.py` exists and is committed at that exact repository path. Keep `.pkgmeta-lock.json` committed as the source of truth for vendored library versions; never ignore it. Keep `.pkgmeta-cache/` ignored in `.gitignore` as a local diff aid. `Libs/` must be committed and must not be ignored on this branch. These requirements do not apply to `main`.

Every commit, including setup commits, follows the root `AGENTS.md` staged-list, staged-stat, complete-staged-diff, and explicit-approval checkpoint.
