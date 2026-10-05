# One-time repository setup and Cloud checkout

Read this reference when remotes/branches/tooling are missing or the verified Codex Cloud checkout starts on isolated `work`. Complete [maintenance preflight](../../../references/maintenance-runtime.md) before any branch changes. `new-features` is the intended GitHub default/development branch; `main` is the upstream mirror. Never derive their roles from a generic default/HEAD.

Use `<PYTHON> scripts/prepare_update.py` as the preparation stage in [branch sync](branch-sync.md), adding `--cloud-work` only after positively identifying a real Codex Cloud host currently on `work`. Do not infer Cloud from Linux or a branch called `work`, and the helper explicitly rejects this exception on Windows. Missing tooling must be restored/reviewed before continuing; do not skip preflight.

The helper verifies `origin` is `https://github.com/hellsy55/AlterEgo.git` and verifies or adds `upstream` as `https://github.com/DennisRas/AlterEgo.git`. Dirty worktree/index stops before fetch or branch modification. A clean Cloud `work` must contain no unpublished commits relative to `origin/new-features` (validate before fetching when the tracking ref exists, and always after fetching); otherwise preserve it and stop for review. The work ref is preserved, never reset, merged or published.

The helper fetches `upstream/main` and both origin branches once with explicit destination refspecs, even when `remote.origin.fetch` lists only `new-features`. It verifies commit refs and `origin/main` ancestry to `upstream/main`, creates missing local branches only from the corresponding origin branch, configures their tracking explicitly, and then switches eligible Cloud `work` to `new-features`. No wildcard configuration, automatic merge, reset, commit or push is performed. If remote `new-features` or `main` is missing, fetch fails and preparation stops; do not manufacture development from the mirror.

Existing real local branches keep all commits and remain subject to branch sync's unpublished-history, divergence, overlap, conflict, commit and publication gates. Do not execute preparation twice or refetch in the same update. An ordinary local session already on `new-features` follows the same deterministic fetches without the Cloud branch exception or an unnecessary checkout.

On `new-features`, keep `scripts/maintenance_runtime.py`, `scripts/prepare_update.py`, `scripts/classify_lib_changes.py` and `scripts/check_lib_updates.py` committed. Keep `.pkgmeta-lock.json` committed as the vendoring source of truth and `.pkgmeta-cache/` ignored. Keep `Libs/` committed and unignored. These fork tooling/vendoring requirements do not apply to `main`.

Every commit, including setup commits, follows the root `AGENTS.md` staged-list, staged-stat, complete-staged-diff and explicit-approval checkpoint.
