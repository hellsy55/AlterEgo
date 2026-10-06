# Independent upstream sync

Run these stages sequentially. `main` and `new-features` each sync independently from `upstream/main`; never merge them into each other. Preserve `main` as fast-forward-only and `new-features` merge semantics.

## Preflight and compact gate

Complete or reuse [maintenance preflight](../../../references/maintenance-runtime.md) before branch setup, checkout or merge. Reuse its context and absolute Python executable for the entire update, including any triggered library workflow.

Check the current branch and working tree once through `<PYTHON> scripts/prepare_update.py`, using the retained context. For verified Cloud `work`, load the [checkout adapter](../../../references/cloud-environment.md#checkout-preparation) and use its update invocation instead. Read [initial setup](initial-setup.md) only for missing branches/remotes/tooling. Do not rerun preflight.

The helper stops on a dirty index/worktree before any fetch or branch change, verifies the remotes, adds the canonical `upstream` if absent, then performs exactly one fetch per remote with explicit destination refspecs:

```text
git fetch --quiet --no-tags upstream +refs/heads/main:refs/remotes/upstream/main
git fetch --quiet --no-tags origin +refs/heads/new-features:refs/remotes/origin/new-features +refs/heads/main:refs/remotes/origin/main
```

It validates the fetched commit refs and mirror ancestry, creates only missing local branches from their corresponding origin refs, and explicitly configures tracking without changing `remote.origin.fetch`. It preserves every existing local branch tip. Cloud-only `work` handling belongs to the conditional checkout adapter. The helper never merges, resets, commits or pushes.

Retain its compact result, including which branches were created, and continue the ancestry/publication gates below for all pre-existing real branches. Reuse these fetched refs for the entire update; do not fetch again or run `pull`. A failed helper is an error/pending decision, not a no-op. On an ordinary local no-op it does not check out either branch.

After preparation, before any further checkout or merge, compare ancestry and hashes:

- `git merge-base --is-ancestor upstream/main new-features` means no incoming upstream commits for `new-features`. Otherwise record `git merge-base new-features upstream/main` and count `git rev-list --count <base>..upstream/main`. This exact pending upstream range is the library and overlap gate; retain it before merging.
- Compare `new-features` with `origin/new-features`. If local is behind, fast-forward it; if divergent, stop for the merge-commit or conflict checkpoint before upstream work. If local is ahead before this update, stop before merging or pushing and review its unpublished commits; do not publish them automatically. If origin advancement changes the upstream merge base, recompute the pending upstream range before classifying or merging.
- Verify that `origin/main` is an ancestor of `upstream/main` before advancing `main`; otherwise stop because the upstream mirror may contain fork-specific commits. Compare local `main` with both refs by ancestry. Divergence that prevents fast-forward is an error requiring a decision; never create a merge commit on `main`.

Only call the update a no-op when both local branches equal their origin refs and already contain `upstream/main`. Then do not checkout either branch, merge, push, rerun status, open full diffs, invoke semantic review or create a commit. Do not classify an empty incoming range. Without an explicit library-check request, do not run the checker or load the library skill; an explicit check still runs once even when sync is a no-op. Report both branches current and proceed to the environment-aware install stage. A pre-existing local-ahead branch is not a no-op: stop for review of its unpublished history and an explicit publication decision before any push. After a fast-forward or merge, obtain the changed branch's result once; do not repeat full status when no operation could have changed the worktree.

## Developed branch

Update `new-features` from `origin/new-features` only if behind. A fast-forward needs no commit approval. If histories diverge, use `git merge --no-commit origin/new-features` and stop for the staged-review or conflict decision. Recompute the pending upstream range after any origin integration, then run the overlap and library path gates before the upstream merge.

## Cheap overlap gate

When incoming upstream commits exist, retain their SHAs, incoming count and changed paths/modules with `git diff --name-status <base> upstream/main` and the fork's relevant local changes with `git diff --name-only <base> new-features`. Cache compact facts by branch/base/target SHA for gates and reporting; invalidate only the affected range after origin integration or another ref change. Classify libraries once for the final exact incoming range, not again after upstream merging. Compare paths and module ownership before reading code. Do not open full diffs by default; the complete staged diff remains mandatory before every commit. No reasonable overlap means no general semantic review. If paths or modules overlap, read only the relevant diffs and code to identify shared functions, flow, or behavior and explain any feature at risk, including an upstream feature that choosing local alone would lose. If the interaction is complex or uncertain, request exactly one read-only `deep_reviewer` with only that context and wait before recommending. A real conflict always follows [merge conflicts](merge-conflicts.md).

After the gates, merge `upstream/main` only if it is not already an ancestor of `new-features`, using `git merge --no-commit upstream/main`. This keeps the established non-fast-forward merge semantics. If a clean merge requires a commit, show its staged file list, staged stat, and complete staged diff and wait for explicit approval before committing. Do not automatically commit a merge. Push `new-features` only after all locally created commits in its unpublished range have passed their required checkpoints; a pre-existing local-ahead range requires separate review and explicit publication approval. Fast-forwarding published upstream commits creates no local commit and needs no commit checkpoint. Verify the approved result is on `origin/new-features` before offering installation; never push an unapproved merge merely to make its ZIP available.

## Upstream mirror branch

After the developed branch, stop before advancing `main` if it was already ahead of `origin/main` at preflight; review that unpublished history and obtain explicit publication approval. Otherwise checkout `main` only if it needs a fast-forward. Fast-forward from `origin/main` if needed, then from `upstream/main` if needed. Stop if either step cannot fast-forward. Push an upstream fast-forward to `main` after verifying its ancestry. Return to `new-features` after any `main` checkout. Do not checkout `main` at all when it is already current.

Keep user-visible progress compact, for example `[1/3] Preflight — clean`, `[2/3] Sync — new-features +2; main +2`, `[3/3] Install — awaiting choice`. Give errors, conflicts, and pending decisions promptly. Suppress raw fetch progress, checkout chatter, repeated `Already up to date`, internal hashes, and routine file lists. Do not claim a branch is current unless its comparisons succeeded.
