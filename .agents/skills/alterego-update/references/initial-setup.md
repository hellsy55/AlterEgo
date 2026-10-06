# One-time repository setup

Read this reference when remotes/branches/tooling are missing. Complete or reuse [maintenance preflight](../../../references/maintenance-runtime.md) before any branch changes. `new-features` is the intended GitHub default/development branch; `main` is the upstream mirror. Never derive their roles from a generic default/HEAD.

Use the retained `<PYTHON> scripts/prepare_update.py` once as the preparation stage in [branch sync](branch-sync.md). Only verified Cloud `work` loads the [checkout adapter](../../../references/cloud-environment.md#checkout-preparation). Missing tooling must be restored/reviewed before continuing; do not repeat preflight.

The helper verifies `origin` is `https://github.com/hellsy55/AlterEgo.git` and verifies or adds `upstream` as `https://github.com/DennisRas/AlterEgo.git`. Dirty worktree/index stops before fetch or branch modification. Cloud-only `work` validation belongs to the conditional adapter.

The helper fetches `upstream/main` and both origin branches once with explicit destination refspecs, even when `remote.origin.fetch` lists only `new-features`. It verifies commit refs and `origin/main` ancestry to `upstream/main`, creates missing local branches only from the corresponding origin branch, and configures their tracking explicitly. No wildcard configuration, automatic merge, reset, commit or push is performed. If remote `new-features` or `main` is missing, fetch fails and preparation stops; do not manufacture development from the mirror.

Existing real local branches keep all commits and remain subject to branch sync's unpublished-history, divergence, overlap, conflict, commit and publication gates. Do not execute preparation twice or refetch in the same update. An ordinary local session already on `new-features` follows the same deterministic fetches without the Cloud branch exception or an unnecessary checkout.

On `new-features`, keep `scripts/maintenance_runtime.py`, `scripts/prepare_update.py`, `scripts/classify_lib_changes.py` and `scripts/check_lib_updates.py` committed. Keep `.pkgmeta-lock.json` committed as the vendoring source of truth and `.pkgmeta-cache/` ignored. Keep `Libs/` committed and unignored. These fork tooling/vendoring requirements do not apply to `main`.

Every commit, including setup commits, follows the root `AGENTS.md` staged-list, staged-stat, complete-staged-diff and explicit-approval checkpoint.
