# Independent upstream sync

Run these stages sequentially. Do not merge `main` into `new-features` or `new-features` into `main`.

## Developed branch

```text
git fetch upstream
git checkout new-features
git pull --no-rebase --no-commit origin new-features
git merge --no-commit upstream/main
```

The pull integrates the fork's remote branch with merge semantics and prevents an automatic merge commit if those histories unexpectedly diverge. If that pull needs a merge commit or encounters a conflict, stop for the same staged-review or conflict decision before continuing to upstream. The upstream merge intentionally has no fast-forward-only restriction: `new-features` has its own commits. Report the upstream result clearly in Portuguese without raw Git output. If the merge says `Already up to date`, say that no new original-addon update exists and `new-features` is current. If commits arrived, say a new original-addon update was found and merged into `new-features`. If there is a conflict, stop and follow [merge conflicts](merge-conflicts.md). A fast-forward creates no new local commit or commit-approval checkpoint. If a clean non-fast-forward merge is staged, show its staged file list, stat, and complete diff to the user and wait for explicit approval before creating the merge commit with an English message and no AI signature. Then run `git push origin new-features`.

## Fork default branch

Immediately after the developed-branch sync:

```text
git checkout main
git pull --ff-only origin main
git merge --ff-only upstream/main
```

`main` has no fork-specific commits, so both its origin pull and upstream merge must fast-forward. Report the same two outcomes in Portuguese, naming `main` instead. If either operation cannot fast-forward, stop and explain the unexpected divergence before changing history; do not create a merge commit on `main` automatically. Otherwise run `git push origin main`.

Then run `git checkout new-features`. The following library check and install flow require `new-features`. Upstream `.pkgmeta` pin changes become visible to the library checker only after this sync because the checker reads the current branch's `.pkgmeta`.
